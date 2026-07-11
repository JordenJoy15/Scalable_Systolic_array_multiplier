`include "shiftregister.v"
module fifo #(
    parameter  WIDTH=8,
    parameter  array_no=8
)(
    input wire signed [WIDTH*array_no-1:0] in ,
    output wire signed [WIDTH*array_no-1:0] out ,
    input reset,
    input clk,
    input ena
);
genvar i;
generate
    for(i=0;i<array_no;i=i+1)begin:skew_array
        if(i==0)begin:first_element
            assign out[WIDTH-1:0]=in[WIDTH-1:0];
        end
        else begin:rest_elements
            shiftr #(
                .DEPTH(i),
                .WIDTH(WIDTH)
                )   step_array(
                .in(in[i*WIDTH+:WIDTH]),
                .out(out[i*WIDTH+:WIDTH]),
                .clk(clk),
                .reset(reset),
                .ena(ena)
            );
        end
    end
    endgenerate
endmodule