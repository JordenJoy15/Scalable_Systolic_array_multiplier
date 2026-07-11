module buffer #(
    parameter WIDTH=8,
    parameter array_no=8,
    parameter DEPTH=1024,
    parameter offset=0
)(
    input wire [$clog2(DEPTH)-1:0]input_address,
    input wire signed [4*WIDTH*array_no-1:0] input_data,
    input clk,
    input reset,
    input input_drain,
    output output_drain,
    input wire [$clog2(array_no)-1:0] counter_select,
    output reg [$clog2(DEPTH)-1:0]pass_addr,
    output reg pass_drain,
    output reg [$clog2(array_no)-1:0] pass_counter,
    output wire [4*WIDTH-1:0] output_data,
    output wire [$clog2(DEPTH)-1:0] output_addr
);
assign output_data=input_data[counter_select*4*WIDTH+:4*WIDTH];
assign output_addr=input_address;
assign output_drain=input_drain;
always @(posedge clk)begin
if (reset)begin
pass_addr<=offset;
pass_drain<=0;
pass_counter<=0;

end
else begin
    pass_addr<=input_address;
    pass_drain<=input_drain;
    pass_counter<=counter_select;
    end

end
endmodule
