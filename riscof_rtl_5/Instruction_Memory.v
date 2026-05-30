`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.01.2026 14:19:07
// Design Name: 
// Module Name: Instruction_Memory
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




module Instruction_Memory(rst,A,RD);

  input rst;
  input [29:0]A;//[31:0]A;
  output [31:0]RD;

  reg [31:0] mem [1048575:0];
  
  assign RD = (!rst) ? {32{1'b0}} : mem[A];

  initial begin : init_block
    integer i;
    for (i = 0; i <1048576; i = i + 1) begin
      mem[i] = 32'h0;
    end
    $readmemh("imem.hex", mem);
  end

endmodule
