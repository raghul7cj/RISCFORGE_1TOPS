`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 20.02.2026 12:11:52
// Design Name: 
// Module Name: opcode_check
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


module opcode_check(
    input  [6:0] opcode,
    output       illegal_instr
);

wire valid_opcode;

assign valid_opcode =
       (opcode == 7'b0110111) ||  // LUI
       (opcode == 7'b0010111) ||  // AUIPC
       (opcode == 7'b1101111) ||  // JAL
       (opcode == 7'b1100111) ||  // JALR
       (opcode == 7'b1100011) ||  // BRANCH
       (opcode == 7'b0000011) ||  // LOAD
       (opcode == 7'b0100011) ||  // STORE
       (opcode == 7'b0010011) ||  // OP-IMM
       (opcode == 7'b0110011) ||  // OP
       (opcode == 7'b0001111) ||  // FENCE
       (opcode == 7'b1110011);    // SYSTEM (CSR/MRET)

assign illegal_instr = ~valid_opcode;

endmodule


