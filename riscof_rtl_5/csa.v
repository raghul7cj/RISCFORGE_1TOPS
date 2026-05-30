`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.03.2026 18:04:35
// Design Name: 
// Module Name: csa
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


module csa #(parameter N = 66) (
    input  [N-1:0] a,
    input  [N-1:0] b,
    input  [N-1:0] c,
    output [N-1:0] s,    // sum bits
    output [N-1:0] co    // carry bits (shifted left by caller)
);
    assign s  = a ^ b ^ c;
    assign co = ((a & b) | (b & c) | (a & c));
endmodule
