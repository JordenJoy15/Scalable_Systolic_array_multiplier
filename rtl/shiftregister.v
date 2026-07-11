module shiftr#(
    parameter DEPTH=7,
    parameter WIDTH=8
)(
    input wire signed [WIDTH-1:0] in,
    output wire signed [WIDTH-1:0] out,
    input clk,
    input ena,
    input reset
);
reg signed [WIDTH-1:0] dff [0:DEPTH-1];
assign out=dff[DEPTH-1];
integer i,j;
always @(posedge clk)begin
    if(reset)begin
    
        for( i=0;i<DEPTH;i=i+1)begin
            dff[i]<=0;
        end
    end
    else if (ena)begin
        dff[0]<=in;
        for( j=1;j<DEPTH;j=j+1)begin
            dff[j]<=dff[j-1];
        end
    end
end
endmodule