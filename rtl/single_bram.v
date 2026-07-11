module bram  #(
    parameter WIDTH = 8,
    parameter DEPTH = 1024
)(
    input  wire                  clk,
    input  wire                  reset,
    input  wire                  ena,
    input  wire                  we,
    input  wire [$clog2(DEPTH)-1:0]            addr,
    input  wire signed  [WIDTH-1:0]      in,
    output reg signed   [WIDTH-1:0]      out
 );
reg signed [WIDTH-1:0] bram0 [0:DEPTH-1];
always @(posedge clk)begin
    if(reset)
    out<=0;
    else begin
    if(ena)begin
        out<=bram0[addr];
        if(we)
        bram0[addr]<=in;
        end
    
    end
 end
 endmodule