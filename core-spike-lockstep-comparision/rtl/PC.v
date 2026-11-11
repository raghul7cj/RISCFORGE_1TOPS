`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.01.2026 14:19:26
// Design Name: 
// Module Name: PC
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////



    
module PC #(
    // Address of the first instruction fetched out of reset.
    // Must land in a range the fetch path can decode — in the RISCFORGE SoC
    // that is the BootROM at 0x0000_0000 or the ISRAM at 0x0001_0000.
    parameter [31:0] RESET_PC = 32'h80000000
)(clk,rst,PC,PC_Next,StallF);
    input clk,rst,StallF;
    input [31:0]PC_Next;
    output [31:0]PC;
    reg [31:0]PC;

    always @(posedge clk or negedge rst)
    begin
        if(!rst) //== 1'b0)
            PC <= RESET_PC;
        else if(StallF==0)
            PC <= PC_Next;
        else
            PC<=PC;
            
    end
endmodule
