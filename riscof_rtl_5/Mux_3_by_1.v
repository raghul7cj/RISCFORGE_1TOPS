`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.01.2026 12:48:38
// Design Name: 
// Module Name: Mux_3_by_1
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


module Mux_3_by_1 (a,b,c,s,d);
    input [31:0] a,b,c;
    input [1:0] s;
    output [31:0] d;
    wire [31:0] d1;
    //assign d = (s == 2'b00) ? a : (s == 2'b01) ? b : (s == 2'b10) ? c : a;
    //assign d=(s[0])?b:d1;
    assign d1=(s[1])?c:a;
    assign d=(s[0])?b:d1;
endmodule
