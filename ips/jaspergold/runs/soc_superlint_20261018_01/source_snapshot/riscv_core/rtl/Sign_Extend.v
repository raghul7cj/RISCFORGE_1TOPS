`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : Sign_Extend
//
// Description:
//  Immediate generator for RV32I instructions.
//  Produces properly formatted 32-bit immediates
//  based on instruction format and control signals.
//
//  Supports:
//      - J-type (JAL)
//      - B-type (Branches)
//      - S-type (Stores)
//      - I-type (Loads, ALU-immediate)
//      - Shift-immediate (SLLI, SRLI, SRAI)
//      - U-type (LUI / AUIPC)
//
//  Pure combinational logic.
//
//////////////////////////////////////////////////////////////////////////////////

module Sign_Extend (In, ImmSrc, Imm_Ext, LUI);

    input  [31:0] In;       // Full 32-bit instruction
    input         LUI;      // U-type indicator (LUI/AUIPC)
    input  [1:0]  ImmSrc;   // Immediate type selector
    output [31:0] Imm_Ext;  // Formatted 32-bit immediate

    // ==================================================
    // Immediate generation logic
    // ==================================================
    //
    // ImmSrc encoding:
    // 11 → J-type
    // 10 → B-type
    // 01 → S-type
    // 00 → I-type (default)
    //
    // LUI overrides I-type for U-type instructions
    //

    assign Imm_Ext =

        // ------------------------------------------------
        // J-type immediate (JAL)
        // imm[20|10:1|11|19:12] << 1
        // ------------------------------------------------
        (ImmSrc == 2'b11) ?
            {{12{In[31]}}, In[19:12], In[20], In[30:21], 1'b0} :

        // ------------------------------------------------
        // B-type immediate (Branch)
        // imm[12|10:5|4:1|11] << 1
        // ------------------------------------------------
        (ImmSrc == 2'b10) ?
            {{20{In[31]}}, In[7], In[30:25], In[11:8], 1'b0} :

        // ------------------------------------------------
        // S-type immediate (Store)
        // imm[11:5|4:0]
        // ------------------------------------------------
        (ImmSrc == 2'b01) ?
            {{20{In[31]}}, In[31:25], In[11:7]} :

        // ------------------------------------------------
        // U-type immediate (LUI / AUIPC)
        // imm[31:12] << 12
        // ------------------------------------------------
        (LUI == 1'b1) ?
            {In[31:12], 12'b0} :

        // ------------------------------------------------
        // I-type shift instructions (SLLI, SRLI, SRAI)
        // shamt = In[24:20]
        // ------------------------------------------------
        (((In[6:0] == 7'b0010011) &
          ((In[14:12] == 3'b001) | (In[14:12] == 3'b101)))) ?
            {27'b0, In[24:20]} :

        // ------------------------------------------------
        // Default I-type immediate
        // ------------------------------------------------
            {{20{In[31]}}, In[31:20]};

endmodule
