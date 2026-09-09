`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : Main_Decoder
//
// Description:
//  Main opcode decoder for RV32I subset.
//  Decodes the 7-bit instruction opcode and generates
//  high-level control signals used in the pipeline.
//
//  Purely combinational logic.
//  No sequential elements.
//
//////////////////////////////////////////////////////////////////////////////////

module Main_Decoder(
    Op,
    RegWrite,
    ImmSrc,
    ALUSrc,
    MemWrite,
    ResultSrc,
    Branche,
    ALUOp,
    lse,
    Jumpe,
    LUISrcE,
    isLUIE,
    illegal_instr,
    
    is_M_instruction
);

    // ==================================================
    // Input
    // ==================================================
    input  [6:0] Op;   // Instruction opcode field

    // ==================================================
    // Outputs
    // ==================================================
    output lse;        // Load/Store enable
    output RegWrite;   // Register write enable
    output ALUSrc;     // Select immediate as ALU operand B
    output MemWrite;   // Data memory write enable
    output Branche;    // Branch enable
    output Jumpe;      // Jump enable

    output [1:0] ImmSrc;     // Immediate format selector
    output [1:0] ALUOp;      // ALU operation category
    output [1:0] ResultSrc;  // Write-back source selector

    output LUISrcE;    // Exposes Op[5] (used for LUI/AUIPC distinction)
    output isLUIE;     // Indicates U-type instructions (LUI/AUIPC)
    output illegal_instr;
    
    output is_M_instruction;
    
    
    assign is_M_instruction=(Op==7'b0110011)?1:0;

    // ==================================================
    // U-type detection (LUI / AUIPC)
    // ==================================================
    assign isLUIE = (Op == 7'b0110111 || 
                     Op == 7'b0010111) ? 1'b1 : 1'b0;

    // Direct exposure of opcode bit 5
    assign LUISrcE = Op[5];

    // ==================================================
    // Load / Store detection
    // ==================================================
    // Load  = 0000011
    // Store = 0100011
    assign lse = (Op == 7'b0000011 | Op == 7'b0100011) ? 1'b1 : 1'b0;

    // ==================================================
    // Register write enable
    // ==================================================
    assign RegWrite = (Op == 7'b0110111 |  // LUI
                       Op == 7'b0010111 |  // AUIPC
                       Op == 7'b0000011 |  // LOAD
                       Op == 7'b1101111 |  // JAL
                       Op == 7'b1100111 |  // JALR
                       Op == 7'b0010011 |  // I-type ALU
                       Op == 7'b0110011 |
                       Op == 7'b0110011) ? // R-type ALU
                       1'b1 : 1'b0;

    // ==================================================
    // Immediate type selection
    //
    // 00 : I-type
    // 01 : S-type
    // 10 : B-type
    // 11 : J-type
    // ==================================================
    assign ImmSrc = (Op == 7'b0100011) ? 2'b01 :
                    (Op == 7'b1100011) ? 2'b10 :
                    (Op == 7'b1101111) ? 2'b11 :
                                         2'b00;

    // ==================================================
    // ALU operand B source selection
    // ==================================================
    assign ALUSrc = (Op == 7'b0110111 |   // LUI
                     Op == 7'b0010111 |   // AUIPC
                     Op == 7'b1101111 |   // JAL
                     Op == 7'b1100111 |   // JALR
                     Op == 7'b0100011 |   // STORE
                     Op == 7'b0000011 |   // LOAD
                     Op == 7'b0010011) ?  // I-type ALU
                     1'b1 : 1'b0;

    // ==================================================
    // Data memory write enable
    // ==================================================
    assign MemWrite = (Op == 7'b0100011) ? 1'b1 : 1'b0;

    // ==================================================
    // Write-back result selection
    //
    // 00 : ALU result
    // 01 : Data memory read
    // 10 : PC + 4
    // ==================================================
    assign ResultSrc = (Op == 7'b0000011) ? 2'b01 :
                       (Op == 7'b1101111 || 
                        Op == 7'b1100111) ? 2'b10 :
                                             2'b00;

    // ==================================================
    // Branch detection
    // ==================================================
    assign Branche = (Op == 7'b1100011) ? 1'b1 : 1'b0;

    // ==================================================
    // Jump detection
    // ==================================================
    assign Jumpe = (Op == 7'b1101111 | Op == 7'b1100111) ? 1'b1 : 1'b0;

    // ==================================================
    // ALU operation category
    //
    // 00 : Load/Store/JAL
    // 01 : Branch
    // 10 : Arithmetic (R/I)
    // 11 : JALR
    // ==================================================
    assign ALUOp = (Op == 7'b1101111 ||   // JAL
                    Op == 7'b0000011 ||   // LOAD
                    Op == 7'b0100011)     // STORE
                    ? 2'b00 :
                   (Op == 7'b1100011)     // BRANCH
                    ? 2'b01 :
                   (Op == 7'b0010011 ||   // I-type
                    Op == 7'b0110011)     // R-type
                    ? 2'b10 :
                   (Op == 7'b1100111)     // JALR
                    ? 2'b11 :
                      2'b00;
                      
    opcode_check op_check(
    .opcode(Op),
    .illegal_instr(illegal_instr));

endmodule

