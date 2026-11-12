// =============================================================================
// sequential_matmul_top.v -- C = A x B using one MAC for the whole matrix
//
// The host interface matches systolic_matmul_top. During RUN, the controller
// visits each output in row-major order and accumulates its N products over N
// clocks. The completed output is stored before moving to the next element.
// =============================================================================
module sequential_matmul_top #(
    parameter N      = 3,
    parameter DATA_W = 8,
    parameter ACC_W  = 20,
    parameter IDX_W  = $clog2(N)
)(
    input  wire                     clk,
    input  wire                     rst,

    input  wire                     wr_en,
    input  wire                     wr_sel,
    input  wire [IDX_W-1:0]         wr_row,
    input  wire [IDX_W-1:0]         wr_col,
    input  wire signed [DATA_W-1:0] wr_data,

    input  wire                     start,
    output wire                     busy,
    output wire                     done,

    input  wire [IDX_W-1:0]         rd_row,
    input  wire [IDX_W-1:0]         rd_col,
    output wire signed [ACC_W-1:0]  rd_data
);
    localparam [1:0] S_IDLE  = 2'd0,
                     S_CLEAR = 2'd1,
                     S_RUN   = 2'd2,
                     S_DONE  = 2'd3;

    reg [1:0] state;
    reg signed [DATA_W-1:0] a_mem [0:N*N-1];
    reg signed [DATA_W-1:0] b_mem [0:N*N-1];
    reg signed [ACC_W-1:0]  c_mem [0:N*N-1];
    reg signed [ACC_W-1:0]  accumulator;
    reg [IDX_W-1:0] row_idx, col_idx, k_idx;

    wire signed [2*DATA_W-1:0] product;
    wire signed [ACC_W-1:0] product_extended;
    wire signed [ACC_W-1:0] mac_result;

    assign product = a_mem[row_idx*N + k_idx] * b_mem[k_idx*N + col_idx];
    assign product_extended = product;
    assign mac_result = accumulator + product_extended;

    integer init_idx;
    initial begin
        state = S_IDLE;
        accumulator = {ACC_W{1'b0}};
        row_idx = {IDX_W{1'b0}};
        col_idx = {IDX_W{1'b0}};
        k_idx = {IDX_W{1'b0}};
        for (init_idx = 0; init_idx < N*N; init_idx = init_idx + 1) begin
            a_mem[init_idx] = {DATA_W{1'b0}};
            b_mem[init_idx] = {DATA_W{1'b0}};
            c_mem[init_idx] = {ACC_W{1'b0}};
        end
    end

    always @(posedge clk) begin
        if (wr_en && !busy && (wr_row < N) && (wr_col < N)) begin
            if (wr_sel)
                b_mem[wr_row*N + wr_col] <= wr_data;
            else
                a_mem[wr_row*N + wr_col] <= wr_data;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start)
                        state <= S_CLEAR;
                end

                S_CLEAR: begin
                    accumulator <= {ACC_W{1'b0}};
                    row_idx <= {IDX_W{1'b0}};
                    col_idx <= {IDX_W{1'b0}};
                    k_idx <= {IDX_W{1'b0}};
                    state <= S_RUN;
                end

                S_RUN: begin
                    if (k_idx == N-1) begin
                        c_mem[row_idx*N + col_idx] <= mac_result;
                        accumulator <= {ACC_W{1'b0}};
                        k_idx <= {IDX_W{1'b0}};

                        if (col_idx == N-1) begin
                            col_idx <= {IDX_W{1'b0}};
                            if (row_idx == N-1)
                                state <= S_DONE;
                            else
                                row_idx <= row_idx + 1'b1;
                        end else begin
                            col_idx <= col_idx + 1'b1;
                        end
                    end else begin
                        accumulator <= mac_result;
                        k_idx <= k_idx + 1'b1;
                    end
                end

                S_DONE: begin
                    if (start)
                        state <= S_CLEAR;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign busy = (state == S_CLEAR) || (state == S_RUN);
    assign done = (state == S_DONE);

    wire [31:0] rd_idx = rd_row * N + rd_col;
    assign rd_data = ((rd_row < N) && (rd_col < N)) ? c_mem[rd_idx]
                                                    : {ACC_W{1'b0}};
endmodule
