`timescale 1ns/1ps
module tb_sequential_matmul;
    parameter N      = 3;
    parameter DATA_W = 8;
    parameter ACC_W  = 20;
    localparam IDX_W = $clog2(N);
    localparam EXPECTED_BUSY = N*N*N + 1;

    reg clk, rst;
    reg wr_en, wr_sel;
    reg [IDX_W-1:0] wr_row, wr_col;
    reg signed [DATA_W-1:0] wr_data;
    reg start;
    wire busy, done;
    reg [IDX_W-1:0] rd_row, rd_col;
    wire signed [ACC_W-1:0] rd_data;

    sequential_matmul_top #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .rst(rst),
        .wr_en(wr_en), .wr_sel(wr_sel), .wr_row(wr_row), .wr_col(wr_col), .wr_data(wr_data),
        .start(start), .busy(busy), .done(done),
        .rd_row(rd_row), .rd_col(rd_col), .rd_data(rd_data)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    reg signed [DATA_W-1:0] A [0:N*N-1];
    reg signed [DATA_W-1:0] B [0:N*N-1];
    integer C_ref [0:N*N-1];
    integer checks, errors, busy_cycles, seed, n, r, c;

    always @(posedge clk)
        if (busy) busy_cycles = busy_cycles + 1;

    task apply_reset;
        begin
            rst = 1'b1;
            @(posedge clk); #1;
            @(posedge clk); #1;
            rst = 1'b0;
        end
    endtask

    task write_elem(input sel, input integer row, input integer col, input integer val);
        begin
            wr_en = 1'b1;
            wr_sel = sel;
            wr_row = row;
            wr_col = col;
            wr_data = val;
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

    task check_results(input integer id);
        integer rr, cc, got, bad;
        begin
            bad = 0;
            checks = checks + 1;
            if (!done) begin
                bad = 1;
                errors = errors + 1;
                $display("  T%0d FAIL: done was never asserted", id);
            end
            checks = checks + 1;
            if (busy_cycles != EXPECTED_BUSY) begin
                bad = 1;
                errors = errors + 1;
                $display("  T%0d FAIL: busy for %0d cycles, expected %0d",
                         id, busy_cycles, EXPECTED_BUSY);
            end
            for (rr = 0; rr < N; rr = rr + 1)
                for (cc = 0; cc < N; cc = cc + 1) begin
                    rd_row = rr;
                    rd_col = cc;
                    #0.1;
                    got = rd_data;
                    checks = checks + 1;
                    if (got !== C_ref[rr*N + cc]) begin
                        bad = 1;
                        errors = errors + 1;
                        $display("  T%0d FAIL: C[%0d][%0d] = %0d, expected %0d",
                                 id, rr, cc, got, C_ref[rr*N + cc]);
                    end
                end
            if (!bad)
                $display("  T%0d ok   (%0d elements match, busy %0d cycles)",
                         id, N*N, busy_cycles);
        end
    endtask

    task run_test(input integer id);
        begin
            compute_ref;
            load_all;
            start_pulse;
            wait_done;
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

    initial begin
        checks = 0;
        errors = 0;
        busy_cycles = 0;
        seed = 32'h51E0A1;
        rst = 1'b1;
        start = 1'b0;
        wr_en = 1'b0;
        wr_sel = 1'b0;
        wr_row = 0;
        wr_col = 0;
        wr_data = 0;
        rd_row = 0;
        rd_col = 0;

        $dumpfile("sequential_matmul.vcd");
        $dumpvars(0, tb_sequential_matmul);
        $display("");
        $display("=== Sequential matrix multiplier: N=%0d, DATA_W=%0d, ACC_W=%0d ===",
                 N, DATA_W, ACC_W);
        apply_reset;

        $display("T1: directed positive values");
        for (r = 0; r < N; r = r + 1)
            for (c = 0; c < N; c = c + 1) begin
                A[r*N + c] = r*N + c + 1;
                B[r*N + c] = N*N - (r*N + c);
            end
        run_test(1);

        $display("T2: identity matrix times random matrix");
        fill_random;
        for (r = 0; r < N; r = r + 1)
            for (c = 0; c < N; c = c + 1)
                A[r*N + c] = (r == c) ? 1 : 0;
        run_test(2);

        $display("T3: zero matrix times random matrix");
        fill_random;
        for (n = 0; n < N*N; n = n + 1)
            A[n] = 0;
        run_test(3);

        $display("T4-T6: signed operand extremes");
        fill_const(127, 127);
        run_test(4);
        fill_const(-128, -128);
        run_test(5);
        fill_const(-128, 127);
        run_test(6);

        $display("T7: 200 random matrix pairs");
        for (n = 0; n < 200; n = n + 1) begin
            fill_random;
            run_test(7);
        end

        $display("T8: writes while busy are ignored");
        for (r = 0; r < N*N; r = r + 1) begin
            A[r] = r - N;
            B[r] = N - r;
        end
        compute_ref;
        load_all;
        start_pulse;
        repeat (2) begin @(posedge clk); #1; end
        write_elem(1'b0, N-1, N-1, 99);
        write_elem(1'b1, N-1, N-1, -99);
        wait_done;
        check_results(8);

        $display("T9: restart from DONE without reloading");
        start_pulse;
        wait_done;
        check_results(9);

        $display("T10: reset during computation, then clean rerun");
        fill_random;
        compute_ref;
        load_all;
        start_pulse;
        repeat (3) begin @(posedge clk); #1; end
        apply_reset;
        start_pulse;
        wait_done;
        check_results(10);

        $display("");
        $display("-----------------------------------------------");
        $display(" %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display(" ALL TESTS PASSED");
        else             $display(" TESTS FAILED");
        $display("");
        $finish;
    end
endmodule
