`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.03.2026 18:01:24
// Design Name: 
// Module Name: booth_enc
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


module booth_enc (
    input  [2:0] bits,
    output       neg,
    output       zero,
    output       two
);
    // neg  = bits[2]
    // zero = all bits equal  (000 → 0, 111 → 0)
    // two  = 011 or 100       (±2X cases)
    assign neg  = bits[2];
    assign zero = ~(bits[2] ^ bits[1]) & ~(bits[1] ^ bits[0]);
    assign two  = ~(bits[0] ^ bits[1]) &  (bits[1] ^ bits[2]);
endmodule
