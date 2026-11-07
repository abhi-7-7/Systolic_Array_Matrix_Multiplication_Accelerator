// =============================================================================
// input_buffer.v  --  tiny buffer holding ONE row of A or ONE column of B
//
//   * one synchronous write port, one asynchronous (combinational) read port
//   * on an FPGA this maps to registers / distributed RAM (a handful of LUTs)
//   * matrix_data_interface reads it with a *skewed* address
// =============================================================================
module input_buffer #(
    parameter DATA_W = 8,
    parameter DEPTH  = 3,
    parameter ADDR_W = 2
)(
    input  wire                     clk,
    input  wire                     wr_en,
    input  wire [ADDR_W-1:0]        wr_addr,
    input  wire signed [DATA_W-1:0] wr_data,
    input  wire [ADDR_W-1:0]        rd_addr,
    output wire signed [DATA_W-1:0] rd_data
);
    reg signed [DATA_W-1:0] mem [0:DEPTH-1];

    integer k;
    initial begin                              // power-up value 0: FPGA-friendly and
        for (k = 0; k < DEPTH; k = k + 1)      // avoids X values in simulation
            mem[k] = {DATA_W{1'b0}};
    end

    always @(posedge clk)
        if (wr_en) mem[wr_addr] <= wr_data;

    assign rd_data = mem[rd_addr];
endmodule
