`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : ALU_Decoder
//
// Description:
//  This module generates the 4-bit ALUControl signal used by the ALU.
//  It refines the high-level ALUOp signal (from the Main Decoder)
//  using instruction fields (funct3, funct7, opcode).
//
//  This module is purely combinational logic.
//
//  Inputs:
//      ALUOp   : High-level ALU category control
//      funct3  : Instruction bits [14:12]
//      funct7  : Instruction bits [31:25]
//      op      : Opcode bits [6:0]
//
//  Output:
//      ALUControl : Specific ALU operation selector
//
//  Assumption:
//      ALUControl encoding must match the ALU implementation.
//
//////////////////////////////////////////////////////////////////////////////////

module ALU_Decoder(ALUOp, funct3, funct7_30, op_5, ALUControl);

    // High-level ALU operation category from Main Decoder
    input  [1:0] ALUOp;

    // Instruction fields for detailed decoding
    input  [2:0] funct3;
   // input  [6:0] funct7;
    input funct7_30;
    input  op_5;

    // Final ALU control signal sent to ALU
    output [3:0] ALUControl;

    // -------------------------------------------------------------------------
    // ALUOp encoding (from Main Decoder):
    //
    // 00 → Load / Store        → ADD (address calculation)
    // 01 → Branch instructions → Comparison operation
    // 10 → R-type / I-type     → Arithmetic / Logical
    // 11 → JALR (assumed)      → Handled by default case
    //
    // ALUControl encoding (must match ALU module):
    //
    // 0000 : ADD
    // 0001 : SUB
    // 0100 : AND
    // 0101 : OR
    // 0111 : XOR
    // 1000 : SLL
    // 1001 : SRL
    // 1010 : SRA
    // 1100 : SLTU
    // 1111 : SLT
    // 0110 : JALR (as per your architecture)
    // -------------------------------------------------------------------------

    assign ALUControl =

        // ==============================================================
        // LOAD / STORE (ALUOp = 00)
        // Perform ADD to compute effective address
        // ==============================================================
        (ALUOp == 2'b00) ? 4'b0000 :

        // ==============================================================
        // BRANCH INSTRUCTIONS (ALUOp = 01)
        // ==============================================================

        // BEQ / BNE → subtraction-based comparison
        ((ALUOp == 2'b01) &&
         (funct3 == 3'b000 || funct3 == 3'b001)) ? 4'b0001 :

        // BLT / BGE → signed comparison
        ((ALUOp == 2'b01) &&
         (funct3 == 3'b100 || funct3 == 3'b101)) ? 4'b1111 :

        // BLTU / BGEU → unsigned comparison
        ((ALUOp == 2'b01) &&
         (funct3 == 3'b110 || funct3 == 3'b111)) ? 4'b1100 :

        // ==============================================================
        // R-TYPE / I-TYPE ARITHMETIC (ALUOp = 10)
        // ==============================================================

        // SUB detection:
        // R-type opcode has op[5] = 1
        // SUB has funct7[5] = 1
        // Therefore {op[5], funct7[5]} == 2'b11
        ((ALUOp == 2'b10) &&
         (funct3 == 3'b000) &&
         ({op_5, funct7_30} == 2'b11)) ? 4'b0001 :

        // ADD (funct3=000 but not SUB)
        ((ALUOp == 2'b10) &&
         (funct3 == 3'b000) &&
         ({op_5, funct7_30} != 2'b11)) ? 4'b0000 :

        // SLL
        ((ALUOp == 2'b10) &&
         (funct3 == 3'b001)) ? 4'b1000 :

        // SLT (signed)
        ((ALUOp == 2'b10) &&
         (funct3 == 3'b010)) ? 4'b1111 :

        // SLTU (unsigned)
        ((ALUOp == 2'b10) &&
         (funct3 == 3'b011)) ? 4'b1100 :

        // XOR
        ((ALUOp == 2'b10) &&
         (funct3 == 3'b100)) ? 4'b0111 :

        // SRA (Shift Right Arithmetic)
        ((ALUOp == 2'b10) &&
         (funct3 == 3'b101 && funct7_30 == 1)) ? 4'b1010 :

        // SRL (Shift Right Logical)
        ((ALUOp == 2'b10) &&
         (funct3 == 3'b101 && funct7_30 == 0)) ? 4'b1001 :

        // OR
        ((ALUOp == 2'b10) &&
         (funct3 == 3'b110)) ? 4'b0101 :

        // AND
        ((ALUOp == 2'b10) &&
         (funct3 == 3'b111)) ? 4'b0100 :

        // ==============================================================
        // DEFAULT CASE
        //
        // Assumed to correspond to JALR operation.
        // Triggered when ALUOp == 2'b11 or no condition matches.
        // ==============================================================
        4'b0110;

endmodule
