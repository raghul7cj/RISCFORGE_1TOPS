`timescale 1ns / 1ps
module booth_enc (
    input  [2:0] bits,
    output       neg,
    output       zero,
    output       two
);
    assign neg  = bits[2];
    assign zero = ~(bits[2] ^ bits[1]) & ~(bits[1] ^ bits[0]);
    assign two  = ~(bits[0] ^ bits[1]) &  (bits[1] ^ bits[2]);
endmodule
