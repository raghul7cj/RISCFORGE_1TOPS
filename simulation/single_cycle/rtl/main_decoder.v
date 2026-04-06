`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.01.2026 16:01:41
// Design Name: 
// Module Name: main_decoder
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


module main_decoder(
    input  [31:0] in,          // 32-bit instruction word

    // Control outputs
    output        LUI_Src,      // Selects LUI (1) or AUIPC (0)
    output        isLUI,        // Indicates U-type instruction
    output        isJALR,       // Indicates JALR instruction
    output        regwrite,     // Register file write enable
    output [1:0]  ImmSrc,       // Immediate format selector
    output        Memwrite,     // Data memory write enable
    output [1:0]  ResultSrc,    // Writeback source selector
    output        ALUSrc,       // ALU operand source select
    output [1:0]  ALUop,        // High-level ALU operation type
    output        Branch,       // Branch instruction indicator
    output [4:0]  lsunit        // Load-store unit control
);

    // =========================================================
    // OPCODE REFERENCE (in[6:0])
    // =========================================================
    // 0110111 : LUI
    // 0010111 : AUIPC
    // 1101111 : JAL
    // 1100111 : JALR
    // 0000011 : LOAD
    // 0100011 : STORE
    // 1100011 : BRANCH
    // 0010011 : I-TYPE ALU
    // 0110011 : R-TYPE ALU
    // =========================================================

    // =========================================================
    // LOAD / STORE UNIT CONTROL
    // =========================================================
    // lsunit[4] : Valid load/store instruction
    // lsunit[3] : 0 = Load, 1 = Store
    // lsunit[2:0] : Load/store type (funct3)

    assign lsunit[4]   = (in[6:0] == 7'b0000011 || in[6:0] == 7'b0100011) ? 1'b1 : 1'b0;
    assign lsunit[3]   = in[5];             // Store = 1, Load = 0
    assign lsunit[2:0] = in[14:12];          // Byte/Half/Word type

    // =========================================================
    // U-TYPE INSTRUCTION CONTROL
    // =========================================================
    // in[5] differentiates LUI and AUIPC
    // 0 -> AUIPC, 1 -> LUI

    assign LUI_Src = in[5];

    assign isLUI   = (in[6:0] == 7'b0110111 || 
                      in[6:0] == 7'b0010111) ? 1'b1 : 1'b0;

    // =========================================================
    // JUMP INSTRUCTION CONTROL
    // =========================================================

    assign isJALR  = (in[6:0] == 7'b1100111) ? 1'b1 : 1'b0;

    // =========================================================
    // REGISTER FILE WRITE ENABLE
    // =========================================================
    // Disabled for:
    // - Branch instructions
    // - Store instructions

    assign regwrite = (in[6:0] == 7'b1100011 || 
                       in[6:0] == 7'b0100011) ? 1'b0 : 1'b1;

    // =========================================================
    // IMMEDIATE TYPE SELECTION
    // =========================================================
    // 00 : I-type / Load / JALR
    // 01 : S-type (Store)
    // 10 : B-type (Branch)
    // 11 : J-type (JAL)

    assign ImmSrc = (in[6:0] == 7'b0100011) ? 2'b01 :
                    (in[6:0] == 7'b1100011) ? 2'b10 :
                    (in[6:0] == 7'b1101111) ? 2'b11 :
                                               2'b00;

    // =========================================================
    // DATA MEMORY WRITE ENABLE
    // =========================================================

    assign Memwrite = (in[6:0] == 7'b0100011) ? 1'b1 : 1'b0;

    // =========================================================
    // WRITEBACK SOURCE SELECTION
    // =========================================================
    // 00 : ALU result
    // 01 : Data memory read
    // 10 : PC + 4 (JAL / JALR)

    assign ResultSrc = (in[6:0] == 7'b0000011) ? 2'b01 :
                       (in[6:0] == 7'b1101111 || 
                        in[6:0] == 7'b1100111) ? 2'b10 :
                                                 2'b00;

    // =========================================================
    // ALU OPERAND SOURCE SELECTION
    // =========================================================
    // 1 -> Immediate
    // 0 -> Register rs2

    assign ALUSrc = (in[6:0] == 7'b0110111 ||  // LUI
                     in[6:0] == 7'b0010111 ||  // AUIPC
                     in[6:0] == 7'b1101111 ||  // JAL
                     in[6:0] == 7'b1100111 ||  // JALR
                     in[6:0] == 7'b0100011 ||  // STORE
                     in[6:0] == 7'b0000011 ||  // LOAD
                     in[6:0] == 7'b0010011)    // I-type
                     ? 1'b1 : 1'b0;

    // =========================================================
    // BRANCH CONTROL
    // =========================================================

    assign Branch = (in[6:0] == 7'b1100011) ? 1'b1 : 1'b0;

    // =========================================================
    // HIGH-LEVEL ALU OPERATION SELECT
    // =========================================================
    // 00 : ADD (Load, Store, JAL)
    // 01 : Branch comparison
    // 10 : R-type / I-type ALU ops
    // 11 : JALR

    assign ALUop = (in[6:0] == 7'b1101111 ||   // JAL
                    in[6:0] == 7'b0000011 ||   // LOAD
                    in[6:0] == 7'b0100011)     // STORE
                    ? 2'b00 :
                   (in[6:0] == 7'b1100011)     // BRANCH
                    ? 2'b01 :
                   (in[6:0] == 7'b0010011 ||   // I-type
                    in[6:0] == 7'b0110011)     // R-type
                    ? 2'b10 :
                   (in[6:0] == 7'b1100111)     // JALR
                    ? 2'b11 :
                      2'b00;

endmodule

