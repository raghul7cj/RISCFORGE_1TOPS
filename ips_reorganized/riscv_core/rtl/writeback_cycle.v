`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.01.2026 21:36:51
// Design Name: 
// Module Name: writeback_cycle
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


module writeback_cycle(ResultSrcW, PCPlus4W, ALU_ResultW, ReadDataW, old_csr_W, ResultW);

// Declaration of IOs
//input clk, rst;
input [1:0] ResultSrcW;
input [31:0] PCPlus4W, ALU_ResultW, ReadDataW, old_csr_W;
//input [31:0] LUI_result_W;

output [31:0] ResultW;

// Declaration of Module
assign ResultW=(ResultSrcW==2'b00)?ALU_ResultW:
               (ResultSrcW==2'b01)?ReadDataW:
               (ResultSrcW==2'b10)?PCPlus4W:old_csr_W
               ;
endmodule
