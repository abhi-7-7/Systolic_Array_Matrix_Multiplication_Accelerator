`timescale 1ns/1ps
// =============================================================================
// tb_pe.v  --  directed + random self-checking testbench for one PE
// =============================================================================
module tb_pe;
    localparam DATA_W = 8;
    localparam ACC_W  = 20;

    reg                      clk;
    reg                      clr;
    reg  signed [DATA_W-1:0] a_in, b_in;
    wire signed [DATA_W-1:0] a_out, b_out;
    wire signed [ACC_W-1:0]  acc;

    pe #(.DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .clr(clr), .a_in(a_in), .b_in(b_in),
        .a_out(a_out), .b_out(b_out), .acc(acc)
    );

    initial clk = 1'b0;
    always  #5 clk = ~clk;                       // 100 MHz

    integer checks, errors, seed, model, n, bad, verbose;

    // Apply one operand pair for exactly one clock edge, then look at the result
    task tick(input integer a, input integer b);
        begin
            a_in = a;
            b_in = b;
            @(posedge clk);
            #1;
            if (verbose) $write("    %4d * %4d  ->", a_in, b_in);
        end
    endtask

    // Clear the PE; the inputs are held at the given values to prove clr has priority
    task clear_pe(input integer a, input integer b);
        begin
            clr  = 1'b1;
            a_in = a;
            b_in = b;
            @(posedge clk);
            #1;
            clr  = 1'b0;
            $write("    clear (inputs %0d, %0d held)  ->", a, b);
        end
    endtask

    task expect_acc(input integer expected);
        begin
            checks = checks + 1;
            if (acc !== expected) begin
                errors = errors + 1;
                $display("  FAIL  acc = %0d, expected %0d", acc, expected);
            end else
                $display("  ok    acc = %0d", acc);
        end
    endtask

    task expect_pass(input integer ea, input integer eb);
        begin
            checks = checks + 1;
            if (a_out !== ea || b_out !== eb) begin
                errors = errors + 1;
                $display("  FAIL  a_out/b_out = %0d/%0d, expected %0d/%0d", a_out, b_out, ea, eb);
            end else
                $display("  ok    a_out/b_out = %0d/%0d", a_out, b_out);
        end
    endtask

    initial begin
        checks = 0; errors = 0; seed = 32'hBEEF; model = 0; bad = 0; verbose = 1;
        clr = 1'b0; a_in = 0; b_in = 0;
        $dumpfile("tb_pe.vcd");
        $dumpvars(0, tb_pe);

        $display("");
        $display("=== PE testbench (DATA_W=%0d, ACC_W=%0d) ===", DATA_W, ACC_W);

        $display("T0: initial clear");
        clear_pe(0, 0);                 expect_acc(0);

        $display("T1: clear has priority over the MAC (inputs non-zero while clr = 1)");
        tick(9, 9);                     expect_acc(81);
        clear_pe(5, 5);                 expect_acc(0);
        $write("    pass-through registers also cleared ->");
        expect_pass(0, 0);

        $display("T2: single multiply-accumulate; operands reappear on a_out/b_out one clock later");
        tick(3, 4);                     expect_acc(12);
        $write("    pass-through ->");
        expect_pass(3, 4);

        $display("T3: accumulation with negative numbers (2*5, -3*4, 7*-6)");
        clear_pe(0, 0);                 expect_acc(0);
        tick(2, 5);                     expect_acc(10);
        tick(-3, 4);                    expect_acc(-2);
        tick(7, -6);                    expect_acc(-44);

        $display("T4: a zero operand leaves the accumulator unchanged (skew padding relies on this)");
        tick(0, 99);                    expect_acc(-44);
        tick(55, 0);                    expect_acc(-44);
        tick(0, 0);                     expect_acc(-44);

        $display("T5: extremes: (-128)*(-128) = 16384 per term; three terms = 49152 (does not fit in 16 bits)");
        clear_pe(0, 0);                 expect_acc(0);
        tick(-128, -128);               expect_acc(16384);
        tick(-128, -128);               expect_acc(32768);
        tick(-128, -128);               expect_acc(49152);
        tick(-128, 127);                expect_acc(32896);      // 49152 - 16256

        $display("T6: pass-through registers delay A and B by exactly one clock");
        clear_pe(0, 0);                 expect_acc(0);
        tick(1, 10);                    expect_pass(1, 10);
        tick(2, 20);                    expect_pass(2, 20);
        tick(3, 30);                    expect_pass(3, 30);

        $display("T7: 64 random MACs against an integer reference model");
        clear_pe(0, 0);                 expect_acc(0);
        model   = 0;
        bad     = 0;
        verbose = 0;
        for (n = 0; n < 64; n = n + 1) begin
            tick($random(seed), $random(seed));
            model  = model + a_in * b_in;
            checks = checks + 1;
            if (acc !== model) begin
                bad    = bad + 1;
                errors = errors + 1;
                $display("  FAIL  step %0d: acc = %0d, expected %0d", n, acc, model);
            end
        end
        verbose = 1;
        if (bad == 0) $display("  ok    all 64 running sums match (final acc = %0d)", acc);

        $display("");
        $display("-------------------------------------------------------------");
        $display(" PE testbench: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display(" PE TESTBENCH PASSED");
        else             $display(" PE TESTBENCH FAILED");
        $display("");
        $finish;
    end
endmodule
