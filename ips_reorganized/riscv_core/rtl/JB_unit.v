`timescale 1ns / 1ps
module JB_unit (
    input [2:0] flags, 
    input [1:0] J,
    input [3:0] B,
    output yes,
    output JALR
);
    wire Branch = B[3];
    wire [2:0] funct3 = B[2:0];

    wire branch_taken = Branch & (
        (funct3 == 3'b000 & flags[2])  | // BEQ
        (funct3 == 3'b001 & !flags[2]) | // BNE
        (funct3 == 3'b100 & flags[1])  | // BLT
        (funct3 == 3'b101 & !flags[1]) | // BGE
        (funct3 == 3'b110 & flags[0])  | // BLTU
        (funct3 == 3'b111 & !flags[0])   // BGEU
    );

    assign yes = branch_taken | J[1];
    assign JALR = J[1] & ~J[0]; 
endmodule
