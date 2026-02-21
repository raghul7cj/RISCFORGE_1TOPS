`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : ALU
//
// Description:
//  Arithmetic Logic Unit for RV32I subset.
//
//  Performs arithmetic, logical, shift, comparison,
//  and JALR address computation operations.
//
//  Outputs:
//      Result : 32-bit result
//      Zero   : Asserted when Result == 0
//
//////////////////////////////////////////////////////////////////////////////////

module ALU(A, B, Result, ALUControl, Zero);

    input  [31:0] A, B;
    input  [3:0]  ALUControl;

    output [31:0] Result;
    output        Zero;

    //wire Cout;
    wire signed [31:0] A_signed, B_signed;

    assign A_signed = A;
    assign B_signed = B;

    // --------------------------------------------------
    // ALU operation selection
    // --------------------------------------------------

    assign {Result} =
        (ALUControl == 4'b0000) ? A + B :                  // ADD
        (ALUControl == 4'b0001) ? A - B :                  // SUB
        (ALUControl == 4'b0100) ? A & B :                  // AND
        (ALUControl == 4'b0101) ? A | B :                  // OR
        (ALUControl == 4'b0110) ? (A + B) & (~32'd1) :     // JALR (clear LSB)
        (ALUControl == 4'b0111) ? A ^ B :                  // XOR
        (ALUControl == 4'b1000) ? A << B[4:0] :            // SLL
        (ALUControl == 4'b1001) ? A >> B[4:0] :            // SRL
        (ALUControl == 4'b1010) ? A_signed >>> B[4:0] :    // SRA
        (ALUControl == 4'b1100) ? A < B :                  // SLTU
        (ALUControl == 4'b1111) ? A_signed < B_signed :    // SLT
        {33{1'b0}};                                        // Default

    // --------------------------------------------------
    // Zero flag
    // --------------------------------------------------

    assign Zero = &(~Result);  // True when Result == 0

endmodule
