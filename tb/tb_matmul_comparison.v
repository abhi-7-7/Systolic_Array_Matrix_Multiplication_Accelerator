`timescale 1ns/1ps
module tb_matmul_comparison;
    parameter N      = 3;
    parameter DATA_W = 8;
    parameter ACC_W  = 20;
    localparam IDX_W = $clog2(N);
    localparam SYSTOLIC_BUSY_EXPECTED = 3*N - 1;
    localparam SEQUENTIAL_BUSY_EXPECTED = N*N*N + 1;
    localparam LOAD_CYCLES = 2*N*N;
    localparam START_ACCEPT_CYCLES = 1;

    reg clk, rst;
    reg wr_en, wr_sel;
    reg [IDX_W-1:0] wr_row, wr_col;
    reg signed [DATA_W-1:0] wr_data;
    reg start;
    wire systolic_busy, systolic_done;
    wire sequential_busy, sequential_done;
    reg [IDX_W-1:0] rd_row, rd_col;
    wire signed [ACC_W-1:0] systolic_rd_data, sequential_rd_data;

    systolic_matmul_top #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) systolic (
        .clk(clk), .rst(rst),
        .wr_en(wr_en), .wr_sel(wr_sel), .wr_row(wr_row), .wr_col(wr_col), .wr_data(wr_data),
        .start(start), .busy(systolic_busy), .done(systolic_done),
        .rd_row(rd_row), .rd_col(rd_col), .rd_data(systolic_rd_data)
    );

    sequential_matmul_top #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) sequential (
        .clk(clk), .rst(rst),
        .wr_en(wr_en), .wr_sel(wr_sel), .wr_row(wr_row), .wr_col(wr_col), .wr_data(wr_data),
        .start(start), .busy(sequential_busy), .done(sequential_done),
        .rd_row(rd_row), .rd_col(rd_col), .rd_data(sequential_rd_data)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    reg signed [DATA_W-1:0] A [0:N*N-1];
    reg signed [DATA_W-1:0] B [0:N*N-1];
    integer C_ref [0:N*N-1];
    integer systolic_busy_cycles, sequential_busy_cycles;
    integer errors, seed, r, c, k, sum, load_cycles;
    integer systolic_end_to_end_cycles, sequential_end_to_end_cycles;
    real systolic_speedup, systolic_compute_mmatmuls, sequential_compute_mmatmuls;
    real systolic_end_to_end_mmatmuls, sequential_end_to_end_mmatmuls;
    localparam real CLOCK_MHZ = 100.0;
    localparam real CLOCK_PERIOD_NS = 10.0;

    always @(posedge clk) begin
        if (systolic_busy)
            systolic_busy_cycles = systolic_busy_cycles + 1;
        if (sequential_busy)
            sequential_busy_cycles = sequential_busy_cycles + 1;
    end

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

    task load_both;
        integer rr, cc;
        begin
            load_cycles = 0;
            for (rr = 0; rr < N; rr = rr + 1)
                for (cc = 0; cc < N; cc = cc + 1) begin
                    write_elem(1'b0, rr, cc, A[rr*N + cc]);
                    load_cycles = load_cycles + 1;
                    write_elem(1'b1, rr, cc, B[rr*N + cc]);
                    load_cycles = load_cycles + 1;
                end
        end
    endtask

    task compute_reference;
        integer rr, cc, kk, reference_sum;
        begin
            for (rr = 0; rr < N; rr = rr + 1)
                for (cc = 0; cc < N; cc = cc + 1) begin
                    reference_sum = 0;
                    for (kk = 0; kk < N; kk = kk + 1)
                        reference_sum = reference_sum + A[rr*N + kk] * B[kk*N + cc];
                    C_ref[rr*N + cc] = reference_sum;
                end
        end
    endtask

    task check_outputs;
        integer rr, cc;
        begin
            for (rr = 0; rr < N; rr = rr + 1)
                for (cc = 0; cc < N; cc = cc + 1) begin
                    rd_row = rr;
                    rd_col = cc;
                    #0.1;
                    if (systolic_rd_data !== C_ref[rr*N + cc]) begin
                        errors = errors + 1;
                        $display("FAIL systolic C[%0d][%0d]=%0d, expected %0d",
                                 rr, cc, systolic_rd_data, C_ref[rr*N + cc]);
                    end
                    if (sequential_rd_data !== C_ref[rr*N + cc]) begin
                        errors = errors + 1;
                        $display("FAIL sequential C[%0d][%0d]=%0d, expected %0d",
                                 rr, cc, sequential_rd_data, C_ref[rr*N + cc]);
                    end
                end
        end
    endtask

    task run_comparison;
        begin
            systolic_busy_cycles = 0;
            sequential_busy_cycles = 0;
            start = 1'b1;
            @(posedge clk); #1;
            start = 1'b0;

            while ((!systolic_done || !sequential_done) &&
                   (systolic_busy_cycles < 1000) && (sequential_busy_cycles < 1000))
                begin @(posedge clk); #1; end

            if (!systolic_done || !sequential_done) begin
                errors = errors + 1;
                $display("FAIL: one or both designs did not complete");
            end
            if (systolic_busy_cycles != SYSTOLIC_BUSY_EXPECTED) begin
                errors = errors + 1;
                $display("FAIL: systolic busy cycles %0d, expected %0d",
                         systolic_busy_cycles, SYSTOLIC_BUSY_EXPECTED);
            end
            if (sequential_busy_cycles != SEQUENTIAL_BUSY_EXPECTED) begin
                errors = errors + 1;
                $display("FAIL: sequential busy cycles %0d, expected %0d",
                         sequential_busy_cycles, SEQUENTIAL_BUSY_EXPECTED);
            end
            check_outputs;
        end
    endtask

    initial begin
        errors = 0;
        seed = 32'hC0FFEE;
        rst = 1'b1;
        wr_en = 1'b0;
        wr_sel = 1'b0;
        wr_row = 0;
        wr_col = 0;
        wr_data = 0;
        start = 1'b0;
        rd_row = 0;
        rd_col = 0;
        systolic_busy_cycles = 0;
        sequential_busy_cycles = 0;

        $display("");
        $display("=== Side-by-side matrix multiplier comparison: N=%0d ===", N);
        $display("Clock assumption: %0.1f MHz (%0.1f ns period)", CLOCK_MHZ, CLOCK_PERIOD_NS);
        apply_reset;

        for (r = 0; r < N*N; r = r + 1) begin
            A[r] = $random(seed);
            B[r] = $random(seed);
        end
        compute_reference;
        load_both;
        if (load_cycles != LOAD_CYCLES) begin
            errors = errors + 1;
            $display("FAIL: loaded in %0d cycles, expected %0d", load_cycles, LOAD_CYCLES);
        end

        run_comparison;

        systolic_end_to_end_cycles = load_cycles + START_ACCEPT_CYCLES + systolic_busy_cycles;
        sequential_end_to_end_cycles = load_cycles + START_ACCEPT_CYCLES + sequential_busy_cycles;
        systolic_speedup = 1.0 * sequential_busy_cycles / systolic_busy_cycles;
        systolic_compute_mmatmuls = CLOCK_MHZ / systolic_busy_cycles;
        sequential_compute_mmatmuls = CLOCK_MHZ / sequential_busy_cycles;
        systolic_end_to_end_mmatmuls = CLOCK_MHZ / systolic_end_to_end_cycles;
        sequential_end_to_end_mmatmuls = CLOCK_MHZ / sequential_end_to_end_cycles;

        $display("");
        $display("All output elements checked against the same integer reference.");
        $display("Matrix loading: %0d cycles for both designs", load_cycles);
        $display("Compute (busy cycles: CLEAR + RUN; excludes start acceptance):");
        $display("  Systolic:   %0d cycles, %0.1f ns, %0.3f million matrix multiplications/s",
                 systolic_busy_cycles, systolic_busy_cycles*CLOCK_PERIOD_NS,
                 systolic_compute_mmatmuls);
        $display("  Sequential: %0d cycles, %0.1f ns, %0.3f million matrix multiplications/s",
                 sequential_busy_cycles, sequential_busy_cycles*CLOCK_PERIOD_NS,
                 sequential_compute_mmatmuls);
        $display("Compute cycle speedup (sequential / systolic): %0.3fx", systolic_speedup);
        $display("End-to-end cycles (load + start acceptance + compute):");
        $display("  Systolic:   %0d cycles, %0.1f ns, %0.3f million matrix multiplications/s",
                 systolic_end_to_end_cycles, systolic_end_to_end_cycles*CLOCK_PERIOD_NS,
                 systolic_end_to_end_mmatmuls);
        $display("  Sequential: %0d cycles, %0.1f ns, %0.3f million matrix multiplications/s",
                 sequential_end_to_end_cycles, sequential_end_to_end_cycles*CLOCK_PERIOD_NS,
                 sequential_end_to_end_mmatmuls);
        $display("Rates are simulated cycle rates at the stated assumed clock, not FPGA timing results.");
        if (errors == 0) $display("COMPARISON PASSED");
        else             $display("COMPARISON FAILED: %0d errors", errors);
        $display("");
        $finish;
    end
endmodule
