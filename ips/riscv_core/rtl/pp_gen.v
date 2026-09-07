`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.03.2026 18:03:26
// Design Name: 
// Module Name: pp_gen
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


module pp_gen (
    input        neg,
    input        zero,
    input        two,
    input  [32:0] mcand,
    input  [5:0]  shift,
    output [65:0] pp,
    output        pp_neg
);
    // FIXED: extend to full 66 bits FIRST, then shift - no bits ever lost
    wire [65:0] mcand_ext = {{33{mcand[32]}}, mcand};
    wire [65:0] base  = two ? (mcand_ext << (shift + 6'd1))
                            : (mcand_ext << shift);
    wire [65:0] mask  = ~66'b0 << shift;
    assign pp     = zero ? 66'b0 : (neg ? (~base & mask) : base);
    assign pp_neg = neg & ~zero;
endmodule
