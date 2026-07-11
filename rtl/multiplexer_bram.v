module multiplexer_2x1 #(
    parameter WIDTH=8,
    parameter array_no=8
)(
    input wire sel,
    input wire clk,
    input wire signed [array_no*WIDTH-1:0] in1,
    input wire signed [array_no*WIDTH-1:0] in2,
    output wire signed [array_no*WIDTH-1:0] out   
);
reg sel_reg;
always @(posedge clk)begin
    sel_reg<=sel;
    end
assign out=sel_reg?in1:in2;
endmodule
