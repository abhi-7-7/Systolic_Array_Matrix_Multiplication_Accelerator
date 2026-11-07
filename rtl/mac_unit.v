// =============================================================================
// mac_unit.v  --  Multiply-Accumulate unit (purely combinational)
//
//     acc_out = acc_in + a * b
//
// Operands are signed two's complement. The product of two DATA_W-bit numbers
// needs 2*DATA_W bits and is sign-extended to ACC_W before the addition.
//
// Accumulator width rule (worst case is (-2^(DATA_W-1))^2 in every term):
//     ACC_W >= ceil(log2(N * 4^(DATA_W-1) + 1)) + 1
//     DATA_W = 8:  N = 3 -> 17 bits,  N = 4 -> 18 bits   (default ACC_W = 20)
// =============================================================================
module mac_unit #(
    parameter DATA_W = 8,
    parameter ACC_W  = 20
)(
    input  wire signed [DATA_W-1:0] a,
    input  wire signed [DATA_W-1:0] b,
    input  wire signed [ACC_W-1:0]  acc_in,
    output wire signed [ACC_W-1:0]  acc_out
);
    wire signed [2*DATA_W-1:0] product;

    assign product = a * b;
    assign acc_out = acc_in + product;      // product is sign-extended to ACC_W
endmodule
