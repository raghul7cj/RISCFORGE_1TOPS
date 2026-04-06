`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.01.2026 14:41:06
// Design Name: 
// Module Name: register_file
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


module register_file(

    input clk,
    input rst,
    input WE3,
    input [4:0]A1,
    input [4:0]A2,
    input [4:0]A3,
    input [31:0]WD3,
    output [31:0]RD1,
    output [31:0]RD2);

    reg [31:0] Register [31:0];

    always @ (posedge clk)
    begin
        if(WE3 && A3!=5'd0)
            Register[A3] <= WD3;
        else
         Register[0]<=32'd0;
    end

    assign RD1 = (~rst) ? 32'd0 : Register[A1];
    assign RD2 = (~rst) ? 32'd0 : Register[A2];

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            Register[i] = 32'h0000_0000;
    end

endmodule
