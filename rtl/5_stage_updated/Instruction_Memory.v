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



module Instruction_Memory(
    input rst,
    input [29:0] A,
    output [31:0] RD
);

    // 1MB Memory Array
    reg [31:0] mem [262143:0]; 

    // FIXED: Sliced A down to 18 bits to prevent out-of-bounds fetches
    assign RD = (~rst || A === 30'bx) ? 32'b0 : mem[A[17:0]]; 
endmodule

//ORGINAL
// module Instruction_Memory(rst,A,RD);

//   input rst;
//   input [29:0]A;//[31:0]A;
//   output [31:0]RD;

//   reg [31:0] mem [262143:0];
  
//   assign RD = (!rst) ? {32{1'b0}} : mem[A];//[31:2]];

// /*  initial begin
//     $readmemh("instructions.mem",mem);
//   end
// */

// // Protects against reading X and crashing the simulator
//   assign RD = (~rst || A === 30'bx) ? 32'b0 : mem[A[17:0]]; 


// endmodule
