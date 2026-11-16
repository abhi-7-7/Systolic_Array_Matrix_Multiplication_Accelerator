`timescale 1ns/1ps
// =============================================================================
// tb_systolic_ctrl.v  --  self-checking testbench for the controller FSM
//
//   Checks the IDLE -> CLEAR -> RUN -> DONE sequence cycle by cycle, the
//   RUN counter t = 0 .. 3N-3, and the busy time of 3N - 1 cycles that the
//   latency and speedup results depend on. Also checks start handling, reset
//   in every state, and that the Moore outputs never contradict each other.
//
// Note on t: the counter clears one cycle after RUN ends, so on the first DONE
// cycle t still reads 3N-2. That is harmless because matrix_data_interface only
// uses t while run = 1. Checks pass T_ANY for t where its value does not matter.
//
// Run:
//   iverilog -g2005 -P tb_systolic_ctrl.N=3 -o sim_ctrl.vvp rtl/systolic_ctrl.v tb/tb_systolic_ctrl.v
//   vvp sim_ctrl.vvp
// =============================================================================
module tb_systolic_ctrl;
    parameter N   = 3;
    localparam T_W = $clog2(3*N);              // same width as systolic_matmul_top

    localparam integer RUN_CYCLES    = 3*N - 2;
    localparam integer EXPECTED_BUSY = 3*N - 1;
    localparam integer T_ANY         = -1;      // "don't care" value for t

    reg            clk, rst, start;
    wire           clr, run, busy, done;
    wire [T_W-1:0] t;

    systolic_ctrl #(.N(N), .T_W(T_W)) dut (
        .clk(clk), .rst(rst), .start(start),
        .clr(clr), .run(run), .t(t), .busy(busy), .done(done)
    );

    initial clk = 1'b0;
    always  #5 clk = ~clk;                       // 100 MHz

    integer checks, errors, busy_cycles, i, bad;

    // Advance one clock edge, then let the outputs settle
    task step;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    // Compare all controller outputs with the expected values
    task expect_out(input e_clr, input e_run, input e_busy, input e_done,
                    input integer e_t, input [8*24-1:0] name);
        begin
            checks = checks + 1;
            if (clr !== e_clr || run !== e_run || busy !== e_busy ||
                done !== e_done || (e_t != T_ANY && t !== e_t)) begin
                errors = errors + 1;
                bad    = bad + 1;
                $display("  FAIL  %0s: clr=%b run=%b busy=%b done=%b t=%0d, expected %b %b %b %b t=%0d",
                         name, clr, run, busy, done, t, e_clr, e_run, e_busy, e_done, e_t);
            end
        end
    endtask

    // Pulse start for one cycle, check CLEAR and every RUN cycle, end in DONE.
    // Counts the busy cycles so the 3N - 1 latency is measured, not assumed.
    task one_multiplication;
        begin
            busy_cycles = 0;
            start = 1'b1;
            step;
            start = 1'b0;
            expect_out(1, 0, 1, 0, 0, "CLEAR");
            if (busy) busy_cycles = busy_cycles + 1;
            for (i = 0; i < RUN_CYCLES; i = i + 1) begin
                step;
                expect_out(0, 1, 1, 0, i, "RUN");
                if (busy) busy_cycles = busy_cycles + 1;
            end
            step;
            expect_out(0, 0, 0, 1, T_ANY, "DONE");
            checks = checks + 1;
            if (busy_cycles !== EXPECTED_BUSY) begin
                errors = errors + 1;
                bad    = bad + 1;
                $display("  FAIL  busy for %0d cycles, expected %0d", busy_cycles, EXPECTED_BUSY);
            end
        end
    endtask

    task report(input [8*80-1:0] name);
        begin
            if (bad == 0) $display("  ok    %0s", name);
            bad = 0;
        end
    endtask

    // Invariant checked on every clock: at most one of clr/run/done is high,
    // and busy is exactly clr OR run
    always @(posedge clk) begin
        #2;
        if (!rst) begin
            checks = checks + 1;
            if ((clr + run + done) > 1 || busy !== (clr | run)) begin
                errors = errors + 1;
                $display("  FAIL  inconsistent outputs at %0t: clr=%b run=%b busy=%b done=%b",
                         $time, clr, run, busy, done);
            end
        end
    end

    initial begin
        checks = 0; errors = 0; bad = 0; busy_cycles = 0;
        rst = 1'b1; start = 1'b0;
        $dumpfile("tb_systolic_ctrl.vcd");
        $dumpvars(0, tb_systolic_ctrl);

        $display("");
        $display("=== Controller testbench (N=%0d, T_W=%0d) ===", N, T_W);

        $display("T1: reset puts the FSM in IDLE with all outputs low");
        step; step;
        expect_out(0, 0, 0, 0, 0, "reset");
        rst = 1'b0;
        step;
        expect_out(0, 0, 0, 0, 0, "IDLE after reset");
        report("IDLE after reset");

        $display("T2: IDLE holds while start is low");
        for (i = 0; i < 5; i = i + 1) begin
            step;
            expect_out(0, 0, 0, 0, 0, "IDLE");
        end
        report("stays in IDLE for 5 cycles");

        $display("T3: one multiplication: CLEAR (1) + RUN (3N-2 = %0d), t counts 0..%0d",
                 RUN_CYCLES, RUN_CYCLES - 1);
        one_multiplication;
        if (bad == 0)
            $display("  ok    busy for %0d cycles (3N-1), then DONE", busy_cycles);
        bad = 0;

        $display("T4: DONE holds while start is low (result stays readable)");
        for (i = 0; i < 5; i = i + 1) begin
            step;
            expect_out(0, 0, 0, 1, 0, "DONE hold");
        end
        report("stays in DONE for 5 cycles");

        $display("T5: start in DONE begins the next multiplication (back-to-back)");
        one_multiplication;
        one_multiplication;
        report("two more multiplications with identical timing");

        $display("T6: start while busy is ignored (timing unchanged)");
        start = 1'b1;
        step;
        start = 1'b0;
        expect_out(1, 0, 1, 0, 0, "CLEAR");
        busy_cycles = busy ? 1 : 0;
        for (i = 0; i < RUN_CYCLES; i = i + 1) begin
            start = (i == 0 || i == RUN_CYCLES / 2);   // start pulses in CLEAR and mid-RUN
            step;
            start = 1'b0;
            expect_out(0, 1, 1, 0, i, "RUN with start");
            if (busy) busy_cycles = busy_cycles + 1;
        end
        step;
        expect_out(0, 0, 0, 1, T_ANY, "DONE");
        checks = checks + 1;
        if (busy_cycles !== EXPECTED_BUSY) begin
            errors = errors + 1;
            bad    = bad + 1;
            $display("  FAIL  busy for %0d cycles, expected %0d", busy_cycles, EXPECTED_BUSY);
        end
        report("extra start pulses during CLEAR/RUN do not restart or stretch the run");

        $display("T7: start held high continuously restarts after one DONE cycle");
        start = 1'b1;
        step;  expect_out(1, 0, 1, 0, 0, "CLEAR");
        for (i = 0; i < RUN_CYCLES; i = i + 1) begin
            step;  expect_out(0, 1, 1, 0, i, "RUN");
        end
        step;  expect_out(0, 0, 0, 1, T_ANY, "DONE");
        step;  expect_out(1, 0, 1, 0, 0, "CLEAR again");
        start = 1'b0;
        for (i = 0; i < RUN_CYCLES; i = i + 1) step;
        step;  expect_out(0, 0, 0, 1, T_ANY, "DONE");
        report("DONE lasts one cycle, then CLEAR");

        $display("T8: synchronous reset returns to IDLE from CLEAR, RUN and DONE");
        start = 1'b1; step; start = 1'b0;        // now in CLEAR
        rst = 1'b1; step; rst = 1'b0;
        expect_out(0, 0, 0, 0, 0, "reset in CLEAR");
        start = 1'b1; step; start = 1'b0;
        for (i = 0; i < RUN_CYCLES / 2 + 1; i = i + 1) step;   // now in the middle of RUN
        rst = 1'b1; step; rst = 1'b0;
        expect_out(0, 0, 0, 0, 0, "reset in RUN");
        one_multiplication;                      // now in DONE
        rst = 1'b1; step; rst = 1'b0;
        expect_out(0, 0, 0, 0, 0, "reset in DONE");
        report("reset from every state, counter cleared");

        $display("T9: a full multiplication still works after reset in RUN");
        one_multiplication;
        report("normal timing after reset");

        $display("");
        $display("-------------------------------------------------------------");
        $display(" Controller testbench: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display(" CONTROLLER TESTBENCH PASSED");
        else             $display(" CONTROLLER TESTBENCH FAILED");
        $display("");
        $finish;
    end
endmodule
