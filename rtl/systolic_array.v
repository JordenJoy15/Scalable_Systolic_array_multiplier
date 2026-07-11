`include "PE.v"
module systolic_array #(
    parameter WIDTH=8,
    parameter array_no=8
)(
    input wire signed [WIDTH*array_no-1:0] in_top,
    input wire signed [WIDTH*array_no-1:0] in_side,
    input reset,
    input skew_reset,
    input clk,
    input ena,
    output wire signed [4*array_no*array_no*WIDTH-1:0] out  
);


wire signed [WIDTH-1:0] q_side [0:array_no-1][0:array_no-1];
wire signed [WIDTH-1:0] q_bottom [0:array_no-1][0:array_no-1];

wire [array_no*array_no:0] ena_pin;
wire [array_no*array_no:0] skew_pin;
reg ena_reg;
reg skew_reset_reg;
always@(posedge clk)begin
    ena_reg<=reset?1'b0:ena;
    skew_reset_reg<=reset?1'b0:skew_reset;
end
assign ena_pin[0]=ena_reg;
assign skew_pin[0]=skew_reset_reg;
genvar i,j;
generate
    for(i=0;i<array_no;i=i+1)begin:row_array
    for (j=0;j<array_no;j=j+1)begin:coloumn_array
    wire signed [WIDTH-1:0] top_in;
    wire signed [WIDTH-1:0] side_in;
    wire enablepin;
    wire skew_reset_pin;
    if(i==0  )begin:first_row
        assign top_in=in_top[WIDTH*j+:WIDTH];   
    end
    else begin:rest_rows
        assign top_in=q_bottom[j][i-1];
    end

    if(j==0)begin:first_column
        assign side_in=in_side[i*WIDTH+:WIDTH]; 
        if(i==0)begin:first_element
        assign enablepin=ena_reg;
        assign skew_reset_pin=skew_reset_reg;
        end
        else begin:rest_elements
        assign enablepin=ena_pin[(i-1)*array_no+1];
        assign skew_reset_pin=skew_pin[(i-1)*array_no+1];
        end
    end
    else begin:rest_columns
        assign side_in=q_side[j-1][i];
        assign enablepin=ena_pin[i*array_no+j] ;
        assign skew_reset_pin=skew_pin[i*array_no+j];

    end
    
PE #(
    .WIDTH(WIDTH)
    ) PE_array(
    .reset(reset),
    .in_side(side_in),
    .in_top(top_in),
    .clk(clk),
    .ena(enablepin),
    .out_bottom(q_bottom[j][i]),
    .out_side(q_side[j][i]),
    .enable_out(ena_pin[i*array_no+j+1]),
    .cout(out[4*WIDTH*(i*array_no+j)+:4*WIDTH]),
    .skew_reset_in(skew_reset_pin),
    .skew_reset_out(skew_pin[i*array_no+j+1])
);
    end
    end
endgenerate

endmodule