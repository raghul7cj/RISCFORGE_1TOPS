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
    output [31:0]RD2,
    output [31:0]a0_val);

    reg [31:0] Register [31:0];

    always @ (posedge clk)
    begin
        if(WE3 && A3!=5'd0)
            Register[A3] <= WD3;
        else
         Register[0]<=32'd0;      //value of x0 is fixed that is zero and cannot be changed
    end

    assign RD1    = (~rst) ? 32'd0 : Register[A1];
    assign RD2    = (~rst) ? 32'd0 : Register[A2];
    assign a0_val = (~rst) ? 32'd0 : Register[10];

    initial begin
        //Register[9] = 32'h00000020;
        //Register[6] = 32'h00000040;
        //Register[11] = 32'h00000028;
        //Register[12] = 32'h00000030;
        //Register[5] = 32'h00000006;
        //Register[6] = 32'h0000000A;
        Register[0]=32'h00000000;
       // Register[1]=32'h00000020;
        //Register[2]=32'h0000000A;
        
    end

endmodule
