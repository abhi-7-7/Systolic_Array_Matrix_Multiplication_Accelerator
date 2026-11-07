// =============================================================================
// systolic_array.v  --  N x N grid of processing elements (output-stationary)
//
//              b_in[0]   b_in[1]   b_in[2]
//                 |         |         |
//   a_in[0] --> PE(0,0) -> PE(0,1) -> PE(0,2)      A flows to the right
//                 |         |         |
//   a_in[1] --> PE(1,0) -> PE(1,1) -> PE(1,2)      B flows downward
//                 |         |         |
//   a_in[2] --> PE(2,0) -> PE(2,1) -> PE(2,2)
//
// Every PE keeps its own running sum: c_out[i*N + j] = C[i][j].
// All buses are flattened vectors; element k lives at bits [k*W +: W].
// =============================================================================
module systolic_array #(
    parameter N      = 3,
    parameter DATA_W = 8,
    parameter ACC_W  = 20
)(
    input  wire                  clk,
    input  wire                  clr,
    input  wire [N*DATA_W-1:0]   a_in,      // a_in[i] feeds row i    (left edge)
    input  wire [N*DATA_W-1:0]   b_in,      // b_in[j] feeds column j (top edge)
    output wire [N*N*ACC_W-1:0]  c_out      // c_out[i*N + j] = accumulator of PE(i,j)
);
    // Horizontal links: row i has N+1 slots, slot j is the A input of PE(i,j)
    wire [N*(N+1)*DATA_W-1:0] a_link;
    // Vertical links: column j has N+1 slots, slot i is the B input of PE(i,j)
    wire [(N+1)*N*DATA_W-1:0] b_link;

    genvar i, j;
    generate
        // ---- edge connections
        for (i = 0; i < N; i = i + 1) begin : g_left_edge
            assign a_link[(i*(N+1))*DATA_W +: DATA_W] = a_in[i*DATA_W +: DATA_W];
        end
        for (j = 0; j < N; j = j + 1) begin : g_top_edge
            assign b_link[j*DATA_W +: DATA_W] = b_in[j*DATA_W +: DATA_W];
        end

        // ---- the grid of PEs
        for (i = 0; i < N; i = i + 1) begin : g_row
            for (j = 0; j < N; j = j + 1) begin : g_col
                pe #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_pe (
                    .clk  (clk),
                    .clr  (clr),
                    .a_in (a_link[(i*(N+1) + j    )*DATA_W +: DATA_W]),
                    .b_in (b_link[(i*N     + j    )*DATA_W +: DATA_W]),
                    .a_out(a_link[(i*(N+1) + j + 1)*DATA_W +: DATA_W]),
                    .b_out(b_link[((i+1)*N + j    )*DATA_W +: DATA_W]),
                    .acc  (c_out [(i*N + j)*ACC_W        +: ACC_W])
                );
            end
        end
    endgenerate
endmodule
