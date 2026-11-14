// =============================================================================
// systolic_matmul_top.v  --  C = A x B on an N x N systolic array
//
//   host --write--> [matrix_data_interface] --skewed streams--> [systolic_array]
//   host --start--> [systolic_ctrl] --clr / run / t-------------^       |
//   host <--read--- [read mux] <---------- accumulators (C) ------------+
//
// Usage:  1) write all N*N elements of A (wr_sel = 0) and of B (wr_sel = 1)
//         2) pulse start
//         3) wait for done
//         4) read C[row][col] through rd_row / rd_col / rd_data
// =============================================================================
module systolic_matmul_top #(
    parameter N      = 3,
    parameter DATA_W = 8,
    parameter ACC_W  = 20,
    parameter IDX_W  = $clog2(N),         // derived - do not override
    parameter T_W    = $clog2(3*N)        // derived - do not override
)(
    input  wire                     clk,
    input  wire                     rst,        // synchronous, active high (FSM only)

    // ---- host write port: one element per clock; ignored while busy or out of range
    input  wire                     wr_en,
    input  wire                     wr_sel,     // 0 -> A, 1 -> B
    input  wire [IDX_W-1:0]         wr_row,
    input  wire [IDX_W-1:0]         wr_col,
    input  wire signed [DATA_W-1:0] wr_data,

    // ---- control / status
    input  wire                     start,      // 1-clock pulse, accepted in IDLE and DONE
    output wire                     busy,
    output wire                     done,       // stays high until the next start

    // ---- host read port: C[rd_row][rd_col], valid while done = 1
    input  wire [IDX_W-1:0]         rd_row,
    input  wire [IDX_W-1:0]         rd_col,
    output wire signed [ACC_W-1:0]  rd_data
);
    wire                  clr, run;
    wire [T_W-1:0]        t;
    wire [N*DATA_W-1:0]   a_stream, b_stream;
    wire [N*N*ACC_W-1:0]  c_flat;

    systolic_ctrl #(.N(N), .T_W(T_W)) u_ctrl (
        .clk  (clk),
        .rst  (rst),
        .start(start),
        .clr  (clr),
        .run  (run),
        .t    (t),
        .busy (busy),
        .done (done)
    );

    matrix_data_interface #(.N(N), .DATA_W(DATA_W), .IDX_W(IDX_W), .T_W(T_W)) u_mdi (
        .clk     (clk),
        .wr_en   (wr_en && !busy &&           // matrices are frozen while computing
                  (wr_row < N) && (wr_col < N)),
        .wr_sel  (wr_sel),
        .wr_row  (wr_row),
        .wr_col  (wr_col),
        .wr_data (wr_data),
        .run     (run),
        .t       (t),
        .a_stream(a_stream),
        .b_stream(b_stream)
    );

    systolic_array #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) u_array (
        .clk  (clk),
        .clr  (clr),
        .a_in (a_stream),
        .b_in (b_stream),
        .c_out(c_flat)
    );

    // ---- read mux: pick one accumulator (keeps the pin count small)
    wire [31:0] rd_idx = rd_row * N + rd_col;
    assign rd_data = ((rd_row < N) && (rd_col < N)) ? c_flat[rd_idx*ACC_W +: ACC_W]
                                                    : {ACC_W{1'b0}};
endmodule
