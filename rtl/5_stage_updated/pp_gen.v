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


//module pp_gen (
//    input        neg,
//    input        zero,
//    input        two,
//    input  [32:0] mcand,        // sign- or zero-extended multiplicand
//    input  [6:0]  shift,        // left-shift amount = 2i (0,2,4,...,32)
//    output [65:0] pp,
//    output        pp_neg        // correction bit passed to Dadda adder
//);
//    wire [65:0] base  = two ? ({mcand, 1'b0} << shift) :  // ×2 shift
//                              (mcand << shift);             // ×1
//    wire [65:0] muxed = zero ? 66'b0 : base;
//    assign pp     = neg ? ~muxed : muxed;   // bitwise NOT (add pp_neg later)
//    assign pp_neg = neg & ~zero;            // 1-bit correction for each negated PP
//endmodule

// Fixed pp_gen - zero-extend mcand to 66 bits BEFORE shifting
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
    wire [65:0] muxed = zero ? 66'b0 : base;
    assign pp     = neg ? ~muxed : muxed;
    assign pp_neg = neg & ~zero;
endmodule
