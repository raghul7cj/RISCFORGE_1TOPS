`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.01.2026 14:42:33
// Design Name: 
// Module Name: data_memory
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


module data_memory(clk,rst,WE,WD,A,RD,WSTRB);
 
    input [3:0]  WSTRB;     // Byte write strobes
    input clk,rst,WE;
    input [29:0]A;
    input [31:0]WD;
    output [31:0]RD;

    reg [31:0] mem [4095:0];

    always @ (posedge clk )
    begin
        if (WE) begin
            if (WSTRB[0]) mem[A][7:0]   <= WD[7:0];
            if (WSTRB[1]) mem[A][15:8]  <= WD[15:8];     //depending upon active store only those bytes will be stored in memory
            if (WSTRB[2]) mem[A][23:16] <= WD[23:16];
            if (WSTRB[3]) mem[A][31:24] <= WD[31:24];
        end
        
    end

    assign RD = (~rst) ? 32'd0 : mem[A];
endmodule
