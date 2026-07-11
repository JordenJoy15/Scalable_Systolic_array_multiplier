`include "buffer.v"
module combined_buffer #(
    parameter WIDTH=8,
    parameter array_no=8,
    parameter DEPTH=1024,
    parameter offset=0
)(
    input wire signed [4*WIDTH*array_no*array_no-1:0] input_data,
    input wire drain,
    input wire reset,
    input clk,
    output wire [array_no-1:0] drain_out,
    output wire [array_no*$clog2(DEPTH)-1:0] addr,
    output wire [array_no*4*WIDTH-1:0] output_data
);
reg [$clog2(array_no)-1:0]counter;
reg drain_reg;
wire [$clog2(DEPTH)-1:0] address_first_element;
assign address_first_element=counter+offset;
always @(posedge clk)begin
drain_reg<=reset?1'b0:drain;
if(reset)
counter<=0;
else if (drain_reg)
counter<=counter+1;
end
wire [$clog2(array_no)*array_no-1:0] counter_conn;
wire [$clog2(DEPTH)*array_no-1:0] addr_conn;
wire [array_no-1:0] drain_conn;
genvar i;
generate
for(i=0;i<array_no;i=i+1)begin:interconnects
wire [$clog2(array_no)-1:0] counter_input;
wire [$clog2(DEPTH)-1:0] addr_in;
wire drain_in;
if(i==0)begin:first_column
assign counter_input=counter;
assign addr_in=address_first_element;
assign drain_in=drain_reg;
end
else begin:first_column2
assign counter_input=counter_conn[(i-1)*$clog2(array_no)+:$clog2(array_no)];
assign addr_in=addr_conn[(i-1)*$clog2(DEPTH)+:$clog2(DEPTH)];
assign drain_in=drain_conn[(i-1)];
end

buffer #(
    .WIDTH(WIDTH),
    .offset(offset),
    .DEPTH(DEPTH),
    .array_no(array_no)
)   buffer1(
    .clk(clk),
    .reset(reset),
    .input_drain(drain_in),
    .input_data(input_data[i*4*WIDTH*array_no+:4*WIDTH*array_no]),
    .input_address(addr_in),
    .counter_select(counter_input),
    .pass_addr(addr_conn[i*$clog2(DEPTH)+:$clog2(DEPTH)]),
    .pass_drain(drain_conn[i]),
    .pass_counter(counter_conn[i*$clog2(array_no)+:$clog2(array_no)]),
    .output_drain(drain_out[i]),
    .output_addr(addr[i*$clog2(DEPTH)+:$clog2(DEPTH)]),
    .output_data(output_data[i*4*WIDTH+:4*WIDTH])
);
end
endgenerate
endmodule