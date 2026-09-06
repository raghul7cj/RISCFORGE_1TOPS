`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.01.2026 15:00:01
// Design Name: 
// Module Name: Data_Memory
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


module Data_Memory(clk,rst,WE,WD,A,RD,WSTRB);
 
    input [3:0]  WSTRB;     // Byte write strobes
    input clk,rst,WE;
    input [29:0]A;
    input [31:0]WD; //initially A was [31:0] but issues in linting as only 31:2 was used
    output [31:0]RD;

    // DMEM base address (word-aligned): 0x1000 >> 2 = 0x400
    // The linker places .data at 0x1000, but dmem.hex is rebased to 0x0000.
    // We subtract the base so address 0x1000 maps to mem[0].
    localparam DMEM_BASE = 30'h400;  // 0x1000 >> 2

    wire [29:0] local_addr = A - DMEM_BASE;

    reg [31:0] mem [1048575:0];

    always @ (posedge clk)
    begin
        if (WE) begin
            if (WSTRB[0]) mem[local_addr][7:0]   <= WD[7:0];
            if (WSTRB[1]) mem[local_addr][15:8]  <= WD[15:8];
            if (WSTRB[2]) mem[local_addr][23:16] <= WD[23:16];
            if (WSTRB[3]) mem[local_addr][31:24] <= WD[31:24];
        end
    end

    assign RD = (~rst) ? 32'd0 : mem[local_addr];

    initial begin : init_block
        integer i;
        for (i = 0; i < 1048576; i = i + 1) begin
            mem[i] = 32'h0;
        end
        $readmemh("dmem.hex", mem);
    end

endmodule


//module Data_Memory(clk,rst,WE,WD,A,RD,WSTRB);

//    input [3:0]  WSTRB;
//    input clk, rst,WE;
//    input [31:0] A, WD;
//    output reg [31:0] RD;

//    reg [31:0] mem [1023:0];

//    always @(posedge clk) begin

//        if (WE) begin
//            if (WSTRB[0]) mem[A[31:2]][7:0]   <= WD[7:0];
//            if (WSTRB[1]) mem[A[31:2]][15:8]  <= WD[15:8];
//            if (WSTRB[2]) mem[A[31:2]][23:16] <= WD[23:16];
//            if (WSTRB[3]) mem[A[31:2]][31:24] <= WD[31:24];
//        end

//        RD <= mem[A[31:2]];

//    end

//endmodule
