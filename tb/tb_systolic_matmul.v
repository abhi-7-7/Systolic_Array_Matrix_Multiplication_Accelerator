`timescale 1ns/1ps
// =============================================================================
// tb_systolic_matmul.v  --  self-checking testbench for the whole accelerator
//
//   * loads A and B through the matrix data interface
//   * starts the array, waits for done, reads C back through the read port
//   * compares every element with a reference model (plain triple loop)
//   * checks the latency: busy for 1 (CLEAR) + (3N - 2) (RUN) = 3N - 1 cycles
//   * prints a cycle-by-cycle trace of all accumulators for the demo test
//
//   Other array size:    iverilog -P tb_systolic_matmul.N=4 ...
//   Other accumulator:   iverilog -P tb_systolic_matmul.ACC_W=16 ...  (should FAIL)
// =============================================================================
module tb_systolic_matmul;
    parameter N      = 3;
    parameter DATA_W = 8;
    parameter ACC_W  = 20;
    localparam IDX_W         = $clog2(N);
    localparam EXPECTED_BUSY = 3*N - 1;

    // ---------------- DUT connections
    reg                      clk, rst;
    reg                      wr_en, wr_sel;
    reg  [IDX_W-1:0]         wr_row, wr_col;
    reg  signed [DATA_W-1:0] wr_data;
    reg                      start;
    wire                     busy, done;
    reg  [IDX_W-1:0]         rd_row, rd_col;
    wire signed [ACC_W-1:0]  rd_data;

    systolic_matmul_top #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .rst(rst),
        .wr_en(wr_en), .wr_sel(wr_sel), .wr_row(wr_row), .wr_col(wr_col), .wr_data(wr_data),
        .start(start), .busy(busy), .done(done),
        .rd_row(rd_row), .rd_col(rd_col), .rd_data(rd_data)
    );

    initial clk = 1'b0;
    always  #5 clk = ~clk;                       // 100 MHz

    // ---------------- test data and bookkeeping
    reg signed [DATA_W-1:0] A [0:N*N-1];         // row-major: A[r*N + c]
    reg signed [DATA_W-1:0] B [0:N*N-1];
    integer                 C_ref [0:N*N-1];

    integer checks, errors, errors_before, busy_cycles, demo_latency, seed, verbose, n, r, c;
    reg     trace_en;

    // busy-cycle counter (counts every clock edge at which busy = 1)
    always @(posedge clk) if (busy) busy_cycles = busy_cycles + 1;

    // ---------------- cycle-by-cycle trace of all accumulators (demo test only)
    integer tr_r, tr_c, tr_t;
    reg signed [ACC_W-1:0] tr_val;
    always @(posedge clk) begin
        if (trace_en && dut.run) begin
            tr_t = dut.t;                        // RUN cycle that is ending at this edge
            #1;
            $write("  t=%0d :", tr_t);
            for (tr_r = 0; tr_r < N; tr_r = tr_r + 1) begin
                $write("  |");
                for (tr_c = 0; tr_c < N; tr_c = tr_c + 1) begin
                    tr_val = dut.c_flat[(tr_r*N + tr_c)*ACC_W +: ACC_W];
                    $write("%6d", tr_val);
                end
            end
            $write("  |\n");
        end
    end

    // ---------------- tasks
    task apply_reset;
        begin
            rst = 1'b1;
            @(posedge clk); #1;
            @(posedge clk); #1;
            rst = 1'b0;
        end
    endtask

    // write one matrix element through the data interface (one clock)
    task write_elem(input sel, input integer row, input integer col, input integer val);
        begin
            wr_en = 1'b1; wr_sel = sel; wr_row = row; wr_col = col; wr_data = val;
            @(posedge clk); #1;
            wr_en = 1'b0;
        end
    endtask

    task load_all;
        integer rr, cc;
        begin
            for (rr = 0; rr < N; rr = rr + 1)
                for (cc = 0; cc < N; cc = cc + 1) begin
                    write_elem(1'b0, rr, cc, A[rr*N + cc]);
                    write_elem(1'b1, rr, cc, B[rr*N + cc]);
                end
        end
    endtask

    // golden reference model: C = A x B with plain integer arithmetic
    task compute_ref;
        integer rr, cc, kk, sum;
        begin
            for (rr = 0; rr < N; rr = rr + 1)
                for (cc = 0; cc < N; cc = cc + 1) begin
                    sum = 0;
                    for (kk = 0; kk < N; kk = kk + 1)
                        sum = sum + A[rr*N + kk] * B[kk*N + cc];
                    C_ref[rr*N + cc] = sum;
                end
        end
    endtask

    task start_pulse;
        begin
            busy_cycles = 0;
            start = 1'b1;
            @(posedge clk); #1;
            start = 1'b0;
        end
    endtask

    task wait_done;
        integer guard;
        begin
            guard = 0;
            while (!done && guard < 200) begin
                @(posedge clk); #1;
                guard = guard + 1;
            end
        end
    endtask

    task run_accelerator;
        begin
            start_pulse;
            wait_done;
        end
    endtask

    // read every C element through the read port and compare with the reference
    task check_results(input integer id);
        integer rr, cc, got, bad;
        begin
            bad = 0;
            checks = checks + 1;
            if (!done) begin
                bad = 1; errors = errors + 1;
                $display("  T%0d FAIL: done was never asserted", id);
            end
            checks = checks + 1;
            if (busy_cycles != EXPECTED_BUSY) begin
                bad = 1; errors = errors + 1;
                $display("  T%0d FAIL: busy for %0d cycles, expected %0d", id, busy_cycles, EXPECTED_BUSY);
            end
            for (rr = 0; rr < N; rr = rr + 1)
                for (cc = 0; cc < N; cc = cc + 1) begin
                    rd_row = rr;
                    rd_col = cc;
                    #0.1;
                    got = rd_data;
                    checks = checks + 1;
                    if (got !== C_ref[rr*N + cc]) begin
                        bad = 1; errors = errors + 1;
                        $display("  T%0d FAIL: C[%0d][%0d] = %0d, expected %0d",
                                 id, rr, cc, got, C_ref[rr*N + cc]);
                    end
                end
            if (!bad && verbose)
                $display("  T%0d ok   (%0d elements match, busy %0d cycles)", id, N*N, busy_cycles);
        end
    endtask

    task run_test(input integer id);
        begin
            compute_ref;
            load_all;
            run_accelerator;
            check_results(id);
        end
    endtask

    task fill_const(input integer a, input integer b);
        integer ii;
        begin
            for (ii = 0; ii < N*N; ii = ii + 1) begin
                A[ii] = a;
                B[ii] = b;
            end
        end
    endtask

    task fill_random;
        integer ii;
        begin
            for (ii = 0; ii < N*N; ii = ii + 1) begin
                A[ii] = $random(seed);
                B[ii] = $random(seed);
            end
        end
    endtask

    task fill_demo;                              // A = 1..N^2,  B = N^2..1
        integer rr, cc;
        begin
            for (rr = 0; rr < N; rr = rr + 1)
                for (cc = 0; cc < N; cc = cc + 1) begin
                    A[rr*N + cc] = rr*N + cc + 1;
                    B[rr*N + cc] = N*N - (rr*N + cc);
                end
        end
    endtask

    task print_demo;
        integer rr, cc;
        begin
            $display("           A                    B            C = A x B (reference)");
            for (rr = 0; rr < N; rr = rr + 1) begin
                $write("  ");
                for (cc = 0; cc < N; cc = cc + 1) $write("%4d", A[rr*N + cc]);
                $write("      ");
                for (cc = 0; cc < N; cc = cc + 1) $write("%4d", B[rr*N + cc]);
                $write("      ");
                for (cc = 0; cc < N; cc = cc + 1) $write("%6d", C_ref[rr*N + cc]);
                $write("\n");
            end
        end
    endtask

    // ---------------- test sequence
    initial begin
        checks = 0; errors = 0; busy_cycles = 0; demo_latency = 0;
        seed = 32'h5EED1234; verbose = 1; trace_en = 1'b0;
        rst = 1'b1; start = 1'b0; wr_en = 1'b0; wr_sel = 1'b0;
        wr_row = 0; wr_col = 0; wr_data = 0; rd_row = 0; rd_col = 0;

        $dumpfile("systolic_matmul.vcd");
        $dumpvars(0, tb_systolic_matmul);

        $display("");
        $display("=== Systolic array matrix multiplier: N=%0d, DATA_W=%0d, ACC_W=%0d ===", N, DATA_W, ACC_W);
        apply_reset;

        // ---- T1: demo with a cycle-by-cycle trace
        $display("T1: demo, A = 1..N^2 and B = N^2..1");
        fill_demo;
        compute_ref;
        print_demo;
        load_all;
        $display("  accumulators after each RUN cycle (one block per PE row; watch the diagonal wavefront):");
        trace_en = 1'b1;
        run_accelerator;
        trace_en = 1'b0;
        demo_latency = busy_cycles;
        check_results(1);
        $dumpoff;                                // keep the VCD small: only T1 is recorded

        // ---- T2: identity matrix
        $display("T2: A = identity, B random  ->  C must equal B");
        fill_random;
        for (r = 0; r < N; r = r + 1)
            for (c = 0; c < N; c = c + 1)
                A[r*N + c] = (r == c) ? 1 : 0;
        run_test(2);

        // ---- T3: zero matrix
        $display("T3: A = 0, B random  ->  C must be all zeros");
        fill_random;
        for (n = 0; n < N*N; n = n + 1) A[n] = 0;
        run_test(3);

        // ---- T4..T6: extreme values (accumulator-width stress)
        $display("T4: all 127 (largest positive operands)");
        fill_const(127, 127);
        run_test(4);

        $display("T5: all -128  ->  every C element = N * 16384, the worst case for the accumulator");
        fill_const(-128, -128);
        run_test(5);

        $display("T6: A = -128, B = 127  ->  most negative sums");
        fill_const(-128, 127);
        run_test(6);

        // ---- T7: random matrices
        $display("T7: 200 random matrix pairs");
        verbose = 0;
        errors_before = errors;
        for (n = 0; n < 200; n = n + 1) begin
            fill_random;
            run_test(7);
        end
        verbose = 1;
        if (errors == errors_before) $display("  T7 ok   (200 random matrix pairs match)");

        // ---- T8: writes during a run must be ignored
        $display("T8: writes while busy are ignored (the result must still match the original data)");
        fill_demo;
        compute_ref;
        load_all;
        start_pulse;
        repeat (2) begin @(posedge clk); #1; end
        write_elem(1'b0, N-1, N-1, ~A[(N-1)*N + (N-1)]);       // would corrupt C if accepted
        write_elem(1'b1, N-1, N-1, ~B[(N-1)*N + (N-1)]);
        wait_done;
        check_results(8);

        // ---- T9: start again from DONE with the same data
        $display("T9: start from the DONE state again (no reload) gives the same result");
        run_accelerator;
        check_results(9);

        // ---- T10: reset in the middle of a run
        $display("T10: reset in the middle of a run, then a clean re-run");
        fill_random;
        compute_ref;
        load_all;
        start_pulse;
        repeat (3) begin @(posedge clk); #1; end
        apply_reset;
        run_accelerator;
        check_results(10);

        // ---- summary
        $display("");
        $display("-------------------------------------------------------------");
        $display(" %0d checks, %0d errors", checks, errors);
        $display(" latency of one multiplication: %0d busy cycles = 1 clear + %0d compute (3N-2)",
                 demo_latency, demo_latency - 1);
        if (errors == 0) $display(" ALL TESTS PASSED");
        else             $display(" TESTS FAILED");
        $display("");
        $finish;
    end
endmodule
