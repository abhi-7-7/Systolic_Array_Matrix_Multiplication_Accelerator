// =============================================================================
// systolic_ctrl.v  --  Systolic array controller (Moore FSM + cycle counter)
//
//                  start                 (1 cycle)            cnt == 3N-3
//      +------+ ---------> +-------+ ------------> +-----+ ------------> +------+
//      | IDLE |            | CLEAR |               | RUN |               | DONE |
//      +------+            +-------+               +-----+               +------+
//                              ^                                             |
//                              +------------------- start -------------------+
//
//   CLEAR : clr = 1   -> every PE zeroes its accumulator and pass-through regs
//   RUN   : run = 1   -> inputs are streamed in; cnt = 0 .. 3N-3  (3N-2 cycles)
//   DONE  : done = 1  -> accumulators hold C; stays until the next start
//
// Cycle cost of one multiplication:  1 (CLEAR) + (3N - 2) (RUN)  =  3N - 1 busy cycles
// =============================================================================
module systolic_ctrl #(
    parameter N   = 3,
    parameter T_W = 4
)(
    input  wire           clk,
    input  wire           rst,       // synchronous, active high
    input  wire           start,     // accepted in IDLE and DONE
    output wire           clr,
    output wire           run,
    output wire [T_W-1:0] t,         // cycle index inside RUN
    output wire           busy,
    output wire           done
);
    localparam [1:0] S_IDLE  = 2'd0,
                     S_CLEAR = 2'd1,
                     S_RUN   = 2'd2,
                     S_DONE  = 2'd3;

    localparam [T_W-1:0] LAST = 3*N - 3;      // last RUN cycle: PE(N-1,N-1) does its final MAC

    reg [1:0]     state, next_state;
    reg [T_W-1:0] cnt;

    // ---- 1) state register
    always @(posedge clk) begin
        if (rst) state <= S_IDLE;
        else     state <= next_state;
    end

    // ---- 2) next-state logic
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:  if (start)       next_state = S_CLEAR;
            S_CLEAR:                  next_state = S_RUN;
            S_RUN:   if (cnt == LAST) next_state = S_DONE;
            S_DONE:  if (start)       next_state = S_CLEAR;
            default:                  next_state = S_IDLE;
        endcase
    end

    // ---- 3) cycle counter: only counts inside RUN
    always @(posedge clk) begin
        if (rst || state != S_RUN) cnt <= {T_W{1'b0}};
        else                       cnt <= cnt + 1'b1;
    end

    // ---- 4) Moore outputs (depend on the state only)
    assign clr  = (state == S_CLEAR);
    assign run  = (state == S_RUN);
    assign busy = (state == S_CLEAR) || (state == S_RUN);
    assign done = (state == S_DONE);
    assign t    = cnt;
endmodule
