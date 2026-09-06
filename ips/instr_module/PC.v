`timescale 1ns / 1ps
// Module : PC
// Program counter.

module PC(clk, rst, PC, PC_Next, StallF);
    input clk, rst, StallF;
    input [31:0] PC_Next;
    output [31:0] PC;
    reg [31:0] PC;

    always @(posedge clk or negedge rst)
    begin
        if(!rst)
            PC <= 32'h80000000;
        else if(StallF==0)
            PC <= PC_Next;
        else
            PC <= PC;
    end
endmodule