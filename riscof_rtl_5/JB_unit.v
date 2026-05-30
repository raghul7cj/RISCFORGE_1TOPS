`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : JB_unit
//
// Description:
//  Jump / Branch decision unit.
//
//  Determines whether control flow should change based on:
//
//      - Branch control bus (B)
//      - Jump control bus (J)
//      - ALU Zero flag
//
//  Outputs:
//      yes   : asserted when branch or jump is taken
//      JALR  : asserted when instruction is JALR
//
//////////////////////////////////////////////////////////////////////////////////

module JB_unit(Zero, J, B, yes, JALR);

    input Zero;        // Zero flag from ALU
    input [1:0] J;     // Jump control bus
    input [3:0] B;     // Branch control bus

    output yes;        // Control flow change (branch/jump taken)
    output JALR;       // Indicates JALR instruction

    // --------------------------------------------------
    // Branch decision logic
    //
    // B[3]   : branch enable
    // B[2:0] : funct3 (branch type)
    // --------------------------------------------------

    wire B_yes;

    assign B_yes =
        (B[3] == 0) ? 1'b0 :

        ((B[2:0] == 3'b000) & (Zero == 1)) ? 1'b1 :  // BEQ
        ((B[2:0] == 3'b001) & (Zero == 0)) ? 1'b1 :  // BNE
        ((B[2:0] == 3'b100) & (Zero == 0)) ? 1'b1 :  // BLT
        ((B[2:0] == 3'b101) & (Zero == 1)) ? 1'b1 :  // BGE
        ((B[2:0] == 3'b110) & (Zero == 0)) ? 1'b1 :  // BLTU
        ((B[2:0] == 3'b111) & (Zero == 1)) ? 1'b1 :  // BGEU
        1'b0;

    // --------------------------------------------------
    // Jump logic
    //
    // J[1] : jump enable
    // J[0] : JAL vs JALR distinction
    // --------------------------------------------------

    wire J_yes = J[1];

    assign JALR = (J == 2'b10) ? 1'b1 : 1'b0;

    // --------------------------------------------------
    // Final decision
    // --------------------------------------------------

    assign yes = J_yes | B_yes;

endmodule
