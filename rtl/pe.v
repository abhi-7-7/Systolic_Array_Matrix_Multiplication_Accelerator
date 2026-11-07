// =============================================================================
// pe.v  --  Processing Element of the systolic array (output-stationary)
//
//                    b_in
//                      |
//          a_in --> [  PE  ] --> a_out        A flows left  -> right
//                      |                      B flows top   -> bottom
//                    b_out                    acc stays in the PE = C[i][j]
//
// Every clock (when clr = 0):
//     acc   <= acc + a_in * b_in      (the MAC)
//     a_out <= a_in                   (hand A to the right neighbour, 1 cycle later)
//     b_out <= b_in                   (hand B to the lower neighbour, 1 cycle later)
// clr is a synchronous clear and has priority over everything else.
// =============================================================================
module pe #(
    parameter DATA_W = 8,
    parameter ACC_W  = 20
)(
    input  wire                     clk,
    input  wire                     clr,
    input  wire signed [DATA_W-1:0] a_in,
    input  wire signed [DATA_W-1:0] b_in,
    output reg  signed [DATA_W-1:0] a_out,
    output reg  signed [DATA_W-1:0] b_out,
    output reg  signed [ACC_W-1:0]  acc
);
    wire signed [ACC_W-1:0] mac_result;

    mac_unit #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_mac (
        .a      (a_in),
        .b      (b_in),
        .acc_in (acc),
        .acc_out(mac_result)
    );

    always @(posedge clk) begin
        if (clr) begin
            a_out <= {DATA_W{1'b0}};
            b_out <= {DATA_W{1'b0}};
            acc   <= {ACC_W{1'b0}};
        end else begin
            a_out <= a_in;
            b_out <= b_in;
            acc   <= mac_result;
        end
    end
endmodule
