module PE #(
    parameter WIDTH=8
) (
    input wire signed [WIDTH-1:0] in_top,
    input wire signed [WIDTH-1:0] in_side,
    input clk,
    input wire ena,
    input wire reset,
    input wire skew_reset_in,
    output reg signed [4*WIDTH-1:0] cout, //need correction
    output reg signed [WIDTH-1:0] out_bottom,
    output reg signed [WIDTH-1:0] out_side,
    output reg enable_out,
    output reg skew_reset_out
);
always @(posedge clk)begin
    enable_out<=reset|skew_reset_in?0:ena;// need corrrection
    skew_reset_out<=reset?0:skew_reset_in;
    if(reset|skew_reset_in)begin
        cout<=0;
        out_bottom<=0;
        out_side<=0;
    end
    else if(ena)begin
        out_bottom<=in_top;
        out_side<=in_side;
        cout<=cout+(in_side*in_top);
    end
end
endmodule