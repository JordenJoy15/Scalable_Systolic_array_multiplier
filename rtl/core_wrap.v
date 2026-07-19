`include "systolic_array.v"
`include "fifo.v"
`include "combined_buffer.v"
module core_wrap #(
    parameter WIDTH=8,
    parameter array_no=8,
    parameter SWEEP_LAG=0   // set 1 if latched PE drain regs return (spec sec 9 Q1)
)(
    input  wire                        clk,
    input  wire                        rst,
    // pre-skew feed (from stream_engine)
    input  wire [WIDTH*array_no-1:0]   feed_act,  // lane i = output pixel i
    input  wire [WIDTH*array_no-1:0]   feed_wt,   // lane j = output channel j
    input  wire                        feed_en,
    input  wire                        feed_last, // asserted with the final beat
    // drain sweep (to drain_engine), 8 lanes, lane i lags lane 0 by i cycles
    output wire [array_no-1:0]         drn_valid,
    output wire [4*WIDTH*array_no-1:0] drn_data,
    output wire                        busy
);


reg sr_pulse;
always @(posedge clk)
sr_pulse <= rst ? 1'b0 : (feed_en & feed_last);

wire core_ena = feed_en | sr_pulse;

wire [WIDTH*array_no-1:0] act_q;
wire [WIDTH*array_no-1:0] wt_q;

fifo #(.WIDTH(WIDTH), .array_no(array_no)) skew_side (
    .in(feed_act), .out(act_q), .reset(rst), .clk(clk), .ena(core_ena));

fifo #(.WIDTH(WIDTH), .array_no(array_no)) skew_top (
    .in(feed_wt), .out(wt_q), .reset(rst), .clk(clk), .ena(core_ena));

wire [4*array_no*array_no*WIDTH-1:0] arr_out;

systolic_array #(.WIDTH(WIDTH), .array_no(array_no)) arr (
    .in_top(wt_q), .in_side(act_q), .reset(rst),
    .skew_reset(sr_pulse), .clk(clk), .ena(core_ena), .out(arr_out));


wire sr_del;
generate
    if (SWEEP_LAG == 0) begin : g_lag0
        assign sr_del = sr_pulse;
    end else begin : g_lag1
        reg sr_q;
        always @(posedge clk) sr_q <= rst ? 1'b0 : sr_pulse;
        assign sr_del = sr_q;
    end
endgenerate

reg [2:0] dcnt;
reg       dact;
always @(posedge clk) begin
    if (rst) begin
        dcnt <= 3'd0;
        dact <= 1'b0;
    end else if (sr_del) begin
        dcnt <= 3'd6;          // sr_del cycle + 7 dact cycles -> 8 total
        dact <= 1'b1;
    end else if (dact) begin
        if (dcnt == 3'd0) dact <= 1'b0;
        else              dcnt <= dcnt - 3'd1;
    end
end
wire cb_drain = sr_del | dact;

combined_buffer #(.WIDTH(WIDTH), .array_no(array_no), .DEPTH(1024), .offset(0)) cb (
    .input_data(arr_out), .drain(cb_drain), .reset(rst), .clk(clk),
    .drain_out(drn_valid), .addr(), .output_data(drn_data));

assign busy = feed_en | sr_pulse | cb_drain;

endmodule
