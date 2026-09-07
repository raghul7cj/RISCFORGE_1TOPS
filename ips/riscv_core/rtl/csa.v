`timescale 1ns / 1ps
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
