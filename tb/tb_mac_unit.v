`timescale 1ns/1ps
// =============================================================================
// tb_mac_unit.v  --  exhaustive self-checking testbench for the MAC unit
//
//   Part 1: directed cases that are easy to get wrong with signed arithmetic
//   Part 2: every signed DATA_W x DATA_W operand pair, for several acc_in values
//
// mac_unit is purely combinational, so each check sets the inputs, waits 1 ns
// for the outputs to settle, and compares against an integer reference model.
// The reference is truncated to ACC_W bits, which matches what the hardware
// does if the sum ever overflows (two's-complement wrap-around).
//
// Run:
//   iverilog -g2005 -o sim_mac.vvp rtl/mac_unit.v tb/tb_mac_unit.v
//   vvp sim_mac.vvp
// =============================================================================
module tb_mac_unit;
    parameter DATA_W = 8;
    parameter ACC_W  = 20;

    localparam integer A_MIN   = -(1 << (DATA_W-1));       // -128 for DATA_W = 8
    localparam integer A_MAX   =  (1 << (DATA_W-1)) - 1;   //  127
    localparam integer ACC_MIN = -(1 << (ACC_W-1));        // -524288 for ACC_W = 20
    localparam integer ACC_MAX =  (1 << (ACC_W-1)) - 1;    //  524287
    localparam integer MAX_REPORTED = 10;                  // limit FAIL lines printed

    reg  signed [DATA_W-1:0] a, b;
    reg  signed [ACC_W-1:0]  acc_in;
    wire signed [ACC_W-1:0]  acc_out;

    mac_unit #(.DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .a(a), .b(b), .acc_in(acc_in), .acc_out(acc_out)
    );

    integer checks, errors, bad, ia, ib, k;
    integer acc_values [0:6];
    reg signed [ACC_W-1:0] expected;

    // Drive one input combination and compare with the reference model
    task check(input integer ta, input integer tb, input integer tacc, input integer show);
        begin
            a      = ta;
            b      = tb;
            acc_in = tacc;
            #1;
            expected = tacc + ta * tb;              // truncated to ACC_W bits
            checks   = checks + 1;
            if (acc_out !== expected) begin
                errors = errors + 1;
                bad    = bad + 1;
                if (bad <= MAX_REPORTED)
                    $display("  FAIL  %0d + %0d * %0d = %0d, expected %0d",
                             tacc, ta, tb, acc_out, expected);
            end else if (show)
                $display("  ok    %7d + %4d * %4d = %0d", tacc, ta, tb, acc_out);
        end
    endtask

    initial begin
        checks = 0; errors = 0; bad = 0;
        a = 0; b = 0; acc_in = 0;

        $display("");
        $display("=== MAC unit testbench (DATA_W=%0d, ACC_W=%0d) ===", DATA_W, ACC_W);

        $display("T1: basic products with acc_in = 0");
        check(0, 0, 0, 1);
        check(3, 4, 0, 1);
        check(A_MAX, 1, 0, 1);

        $display("T2: sign handling (an unsigned multiply would give 65025 for -1 * -1)");
        check(-1, -1, 0, 1);
        check(-3, 4, 0, 1);
        check(3, -4, 0, 1);
        check(-3, -4, 0, 1);

        $display("T3: extreme operands; (-128)*(-128) = 16384 is the worst case used to size ACC_W");
        check(A_MIN, A_MIN, 0, 1);
        check(A_MIN, A_MAX, 0, 1);
        check(A_MAX, A_MAX, 0, 1);

        $display("T4: negative product is sign-extended before it is added to acc_in");
        check(-1, 1, 1000, 1);
        check(A_MIN, A_MAX, 20000, 1);
        check(A_MAX, A_MAX, -20000, 1);

        $display("T5: N worst-case terms (N = 3, 4) fit without overflow at the default ACC_W = 20");
        check(A_MIN, A_MIN, 2 * 16384, 1);         // 3rd term of a 3x3 dot product -> 49152
        check(A_MIN, A_MIN, 3 * 16384, 1);         // 4th term of a 4x4 dot product -> 65536

        $display("T6: accumulator boundaries wrap like two's-complement hardware");
        check(1, 1, ACC_MAX, 1);                   // ACC_MAX + 1 wraps to ACC_MIN
        check(-1, 1, ACC_MIN, 1);                  // ACC_MIN - 1 wraps to ACC_MAX

        // ---------------------------------------------------------------------
        acc_values[0] = 0;
        acc_values[1] = 1;
        acc_values[2] = -1;
        acc_values[3] = 12345;
        acc_values[4] = -12345;
        acc_values[5] = ACC_MAX;
        acc_values[6] = ACC_MIN;

        $display("T7: exhaustive sweep, all %0d operand pairs x 7 acc_in values",
                 (A_MAX - A_MIN + 1) * (A_MAX - A_MIN + 1));
        for (k = 0; k < 7; k = k + 1) begin
            bad = 0;
            for (ia = A_MIN; ia <= A_MAX; ia = ia + 1)
                for (ib = A_MIN; ib <= A_MAX; ib = ib + 1)
                    check(ia, ib, acc_values[k], 0);
            if (bad == 0)
                $display("  ok    acc_in = %7d: all pairs match", acc_values[k]);
            else
                $display("  FAIL  acc_in = %7d: %0d mismatches", acc_values[k], bad);
        end

        $display("");
        $display("-------------------------------------------------------------");
        $display(" MAC testbench: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display(" MAC TESTBENCH PASSED");
        else             $display(" MAC TESTBENCH FAILED");
        $display("");
        $finish;
    end
endmodule
