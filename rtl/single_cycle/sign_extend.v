`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.01.2026 15:05:11
// Design Name: 
// Module Name: sign_extend
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




//module sign_extend (In,Imm_Ext,ImmSrc,isLUI);

//    input [31:0]In;
//    input isLUI;
//    input [1:0] ImmSrc;
//    output [31:0]Imm_Ext;

//   /* assign Imm_Ext = (ImmSrc==3'b000) ?((In[6:0]==7'b0010011 && (In[14:12]==3'b001 || In[14:12]==3'b101))?In[24:20]: ({{20{In[31]}},In[31:20]})):
//                     (ImmSrc==3'b001) ? ({{20{In[31]}},In[31:25],In[11:7]}):
//                     (ImmSrc==3'b010) ? ({{20{In[31]}},In[7],In[30:25],In[11:8],1'b0}):
//                     (ImmSrc==3'b011) ? ({{12{In[31]}},In[19:12],In[20],In[30:21],1'b0}):
//                     ({In[31:12],{12{1'b0}}});
//           */
           
//    assign Imm_Ext=(ImmSrc==2'b11)?{{12{In[31]}}, In[19:12], In[20], In[30:21], 1'b0}:
//                   (ImmSrc==2'b10)?{{20{In[31]}}, In[7], In[30:25], In[11:8], 1'b0}:
//                   (ImmSrc==2'b01)?{{20{In[31]}}, In[31:25], In[11:7]}:
//                   ((isLUI==1'b1)?{In[31:12],{12{1'b0}}}:
//                   ((In[6:0]==7'b0010011 & (In[14:12]==3'b001 | In[14:12]==3'b101))?In[24:20]: ({{20{In[31]}},In[31:20]})));       
//           /*
//           00,0-Immediate if 00,1 then U type
//           01-Store
//           10-Branch
//           11-Jump
//           */
//endmodule


module sign_extend (
    input  [31:0] In,          // 32-bit instruction
    input         isLUI,        // Indicates U-type instruction (LUI / AUIPC)
    input  [1:0]  ImmSrc,       // Immediate type selector
    output [31:0] Imm_Ext       // Sign-extended immediate
);

    // =========================================================
    // IMMEDIATE TYPE ENCODING (ImmSrc)
    // =========================================================
    // 00 : I-type immediate
    //      - Loads
    //      - JALR
    //      - I-type ALU instructions
    //      - Shift immediates handled separately
    //
    // 01 : S-type immediate (Store)
    //
    // 10 : B-type immediate (Branch)
    //
    // 11 : J-type immediate (JAL)
    //
    // U-type immediates (LUI / AUIPC) are selected using isLUI
    // =========================================================

    assign Imm_Ext =
        // -----------------------------------------------------
        // J-type (JAL)
        // -----------------------------------------------------
        (ImmSrc == 2'b11) ? {{12{In[31]}}, In[19:12], In[20], In[30:21], 1'b0} :

        // -----------------------------------------------------
        // B-type (Branch)
        // -----------------------------------------------------
        (ImmSrc == 2'b10) ? {{20{In[31]}}, In[7], In[30:25], In[11:8], 1'b0} :

        // -----------------------------------------------------
        // S-type (Store)
        // -----------------------------------------------------
        (ImmSrc == 2'b01) ? {{20{In[31]}}, In[31:25], In[11:7]} :

        // -----------------------------------------------------
        // I-type / U-type
        // -----------------------------------------------------
        (isLUI == 1'b1)   ? {In[31:12], 12'b0} :

        // -----------------------------------------------------
        // I-type shift instructions (SLLI, SRLI, SRAI)
        // -----------------------------------------------------
        ((In[6:0] == 7'b0010011) &&
         (In[14:12] == 3'b001 || In[14:12] == 3'b101))
                           ? In[24:20] :

        // -----------------------------------------------------
        // Standard I-type immediate (sign-extended)
        // -----------------------------------------------------
                           {{20{In[31]}}, In[31:20]};

endmodule
