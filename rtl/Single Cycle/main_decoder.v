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


//module main_decoder(
//    input [31:0] in,
//    //output [2:0] ctrl_l,
//    output  LUI_Src,
//    output isLUI,
//    output isJALR,
//    output regwrite,
//    output [1:0] ImmSrc,
//    output Memwrite,
//    output [1:0] ResultSrc,
//    output ALUSrc,
//    output [1:0] ALUop,
//    output Branch,
//    output [4:0] lsunit);
    
//    //assign ctrl_l=in[14:12];
//    /*
//        0110111: LUI
//        0010111: AUIPC
//        1101111: JAL
//        1100111: JALR
//        0000011: Load
//        0100011: Store
//        1100011: Branch
//        0010011: I type
//        0110011: R type
//    */
//    assign lsunit[4]=(in[6:0]==7'b0000011 || in[6:0]==7'b0100011)?1:0;  //sets bit 4 to 1 if it is a valid load/store operation
//    assign lsunit[3]=in[5];  // tells if aload  operation or a store operation. if 1 then store else load
//    assign lsunit[2:0]=in[14:12];   //tells the type of load/store operation
//    assign LUI_Src=in[5];  // tells which type of U instruction if 1 then LUI else AUIPC
//    assign isJALR=(in[6:0]==7'b1100111)?1:0;   //if JALR instruction or not
//    assign isLUI=(in[6:0]==7'b0110111 || in[6:0]==7'b0010111)?1'b1:1'b0;   //if U type or not
//    assign regwrite=(in[6:0]==7'b1100011 || in[6:0]==7'b0100011)?0:1;
//   /*assign ImmSrc=(in[6:0]==7'b0010011 || in[6:0]==7'b0000011 || in[6:0]==7'b1100111)?3'b000:
//                  (in[6:0]==7'b0100011)?3'b001:
//                  (in[6:0]==7'b1100011)?3'b010:
//                  (in[6:0]==7'b1101111)?3'b011:
//                  (in[6:0]==7'b0110111 || in[6:0]==7'b0010111)?3'b100: 3'b000;*/
//    assign ImmSrc=(in[6:0]==7'b0100011)?2'b01:
//                  (in[6:0]==7'b1100011)?2'b10:
//                  (in[6:0]==7'b1101111)?2'b11:
//                                   2'b00;
                  
//    assign Memwrite=(in[6:0]==7'b0100011)?1:0;
    
//    assign ResultSrc=(in[6:0]==7'b0000011)?2'b01:
//                     (in[6:0]==7'b1101111 || in[6:0]==7'b1100111)?2'b10:2'b00;
//                     //(in[6:0]==7'b0110111 || in[6:0]==7'b0010111)?2'b11:2'b00;
//    assign ALUSrc=(in[6:0]==7'b0110111 || in[6:0]==7'b0010111 || 
//                   in[6:0]==7'b1101111 || in[6:0]==7'b1100111 || in[6:0]==7'b0100011 || 
//                   in[6:0]==7'b0000011 || (in[6:0]==7'b0010011 ))?1:0;
               
//    assign Branch=(in[6:0]==7'b1100011)?1:0;
    
//    assign ALUop=(in[6:0]==7'b1101111 || in[6:0]==7'b0000011 || in[6:0]==7'b0100011)?2'b00: //ADD
//                 (in[6:0]==7'b1100011)?2'b01: //branch
//                 (in[6:0]==7'b0010011 || in[6:0]==7'b0110011)?2'b10:
//                 (in[6:0]==7'b1100111)?2'b11:2'b00;    //11 is for JALR
    
    
//endmodule


module main_decoder(
//    input  [31:0] in,          // 32-bit instruction word
    input  [6:0] Op,        // Opcode field
   // input  [6:0] funct7,    // funct7 field
    input  [2:0] funct3,    // funct3 field

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
    output [4:0]  lsunit,        // Load-store unit control
    output illegal_instr
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

    assign lsunit[4]   = (Op == 7'b0000011 || Op == 7'b0100011) ? 1'b1 : 1'b0;
    assign lsunit[3]   = Op[5];             // Store = 1, Load = 0
    assign lsunit[2:0] = funct3;          // Byte/Half/Word type

    // =========================================================
    // U-TYPE INSTRUCTION CONTROL
    // =========================================================
    // in[5] differentiates LUI and AUIPC
    // 0 -> AUIPC, 1 -> LUI

    assign LUI_Src = Op[5];

    assign isLUI   = (Op == 7'b0110111 || 
                      Op == 7'b0010111) ? 1'b1 : 1'b0;

    // =========================================================
    // JUMP INSTRUCTION CONTROL
    // =========================================================

    assign isJALR  = (Op == 7'b1100111) ? 1'b1 : 1'b0;

    // =========================================================
    // REGISTER FILE WRITE ENABLE
    // =========================================================
    // Disabled for:
    // - Branch instructions
    // - Store instructions

    assign regwrite = (!illegal_instr)&&((Op == 7'b1100011 || 
                       Op == 7'b0100011) ? 1'b0 : 1'b1);

    // =========================================================
    // IMMEDIATE TYPE SELECTION
    // =========================================================
    // 00 : I-type / Load / JALR
    // 01 : S-type (Store)
    // 10 : B-type (Branch)
    // 11 : J-type (JAL)

    assign ImmSrc = (Op == 7'b0100011) ? 2'b01 :
                    (Op == 7'b1100011) ? 2'b10 :
                    (Op == 7'b1101111) ? 2'b11 :
                                               2'b00;

    // =========================================================
    // DATA MEMORY WRITE ENABLE
    // =========================================================

    assign Memwrite = (!illegal_instr)&&((Op == 7'b0100011) ? 1'b1 : 1'b0);

    // =========================================================
    // WRITEBACK SOURCE SELECTION
    // =========================================================
    // 00 : ALU result
    // 01 : Data memory read
    // 10 : PC + 4 (JAL / JALR)

    assign ResultSrc = (Op == 7'b0000011) ? 2'b01 :
                       (Op == 7'b1101111 || 
                        Op == 7'b1100111) ? 2'b10 :
                                                 2'b00;

    // =========================================================
    // ALU OPERAND SOURCE SELECTION
    // =========================================================
    // 1 -> Immediate
    // 0 -> Register rs2

    assign ALUSrc = (Op == 7'b0110111 ||  // LUI
                     Op == 7'b0010111 ||  // AUIPC
                     Op == 7'b1101111 ||  // JAL
                     Op == 7'b1100111 ||  // JALR
                     Op == 7'b0100011 ||  // STORE
                     Op == 7'b0000011 ||  // LOAD
                     Op == 7'b0010011)    // I-type
                     ? 1'b1 : 1'b0;

    // =========================================================
    // BRANCH CONTROL
    // =========================================================

    assign Branch = (Op == 7'b1100011) ? 1'b1 : 1'b0;

    // =========================================================
    // HIGH-LEVEL ALU OPERATION SELECT
    // =========================================================
    // 00 : ADD (Load, Store, JAL)
    // 01 : Branch comparison
    // 10 : R-type / I-type ALU ops
    // 11 : JALR

    assign ALUop = (Op == 7'b1101111 ||   // JAL
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
    .illegal_instr(illegal_instr));    //when illegal instruction is detected then regwrite
                                       //and memwrite should be made low and pcsrc should be
                                       //made to select pc+4 for pc_next

endmodule

