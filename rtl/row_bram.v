`include "single_bram.v"
module bramslot #(
    parameter array_no =8,
    parameter WIDTH=8,
    parameter DEPTH=1024
)(
    input wire signed  [array_no*(WIDTH)-1:0] in,
    input clk, 
    input reset, 
    input we,
    input ena,
    input wire [$clog2(DEPTH)-1:0]addr,
    output signed  [array_no*(WIDTH)-1:0] out
    );
genvar i;
generate
    for(i=0;i<array_no;i=i+1)begin:bram_blocks
        bram #(
            .WIDTH(WIDTH),
            .DEPTH(DEPTH)
        )BR_A (
            .clk(clk),
            .reset(reset),
            .ena(ena),
            .we(we),
            .addr(addr),
            .in(in[i*WIDTH+:WIDTH]),
            .out(out[i*WIDTH+:WIDTH])
            );
     end
endgenerate
endmodule