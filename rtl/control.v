module systolic_array_control(
    input wire reset,
    input wire start,
    input wire clk,
    output reg ena,
    output reg drain,
    output reg skew_reg
);
parameter IDLE=0,COMPUTE=1,DEPTH=1024,array_no=8;
reg state, enable;
reg [$clog2(DEPTH)-1:0] counter;
reg [array_no-1:0] drain_counter;
wire next_state;
always @(posedge clk)begin  
    if (reset)begin
        state<=IDLE;
        counter<=0;
        ena<=0;
    end

    else 
        state<=next_state;
end

always@(*)begin
    if(start)
        next_state=COMPUTE;
    else if(drain_counter==array_no-1)
        next_state=IDLE;
end

always @(posedge clk)begin
    if(state==COMPUTE)begin
        ena<=1'b1;
        end
    if(ena & counter<=DEPTH-1)
    counter<=counter+1;
    if(counter==DEPTH-1)begin
    drain<=1;
    skew_reg<=1;
    end
    if(skew_reg)
    skew_reg<=0;
    if (drain)begin
    drain_counter<=drain_counter+1;
    end
    if (drain_counter==array_no-1)begin
    drain<=0;
    end
    if(state==IDLE)begin
    counter<=0;
    drain_counter<=0;
    end
    end
endmodule