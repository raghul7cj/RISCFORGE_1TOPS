`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.01.2026 15:07:28
// Design Name: 
// Module Name: RISC_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Top-level module for single-cycle RISC-V processor
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module RISC_top(
    input  rst,
    input  clk,
    output WE1

    // ===================== DEBUG OUTPUTS =====================

    // Program Counter
 //   output [31:0] PC_next1,      // Next PC value
 //   output [31:0] PC1,           // Current PC value

    // Instruction Memory
//    output [31:0] A_i1,           // Instruction memory address
//    output [31:0] RD_i1,          // Instruction read data

//    // Register File
//    output [31:0] A11,            // rs1 address
//    output [31:0] A21,            // rs2 address
//    output [31:0] A31,            // rd address
//    output [31:0] WD31,           // Write data to register file
//    output [31:0] RD11,           // Read data 1
//    output [31:0] RD21,           // Read data 2
//    output [31:0] WE31,           // Register write enable

//    // ALU
//    output [31:0] operand11,      // ALU operand A
//    output [31:0] operand21,      // ALU operand B
//    output [31:0] alu_result1,    // Final ALU result
//    output [31:0] alu_r1,          // Raw ALU output
//    output [3:0]  ctrl1,          // ALU control signals
//    output [3:0]  flags1,         // ALU flags
//    output        ALUSrc1,         // ALU source select

//    // Data Memory
//    output        WE1,             // Data memory write enable
//    output [31:0] A_d1,            // Data memory address
//    output [31:0] WD_d1,           // Data memory write data
//    output [31:0] RD_d1,           // Data memory read data
//    output [3:0]  strobe1,         // Write strobe

//    // PC logic
//    output [31:0] pc_plus1,        // PC + 4
//    output        PCSrc1,           // PC source select

//    // Immediate / LUI / Jumps
//    output [31:0] Imm_Ext1,        // Sign-extended immediate
//    output [1:0]  ImmSrc1,         // Immediate type select
//    output        LUISrc1,          // LUI/AUIPC select
//    output        isLUI1,           // LUI instruction flag
//    output        isJALR1,          // JALR instruction flag
//    output [31:0] pc_target_jb1,   // Branch/Jump target
//    output [31:0] lui_result1,     // LUI/AUIPC result

//    // Writeback
//    output [31:0] result1,         // Final writeback data
//    output [1:0]  ResultSrc1,      // Writeback source select

//    // Load-Store Unit
//    output [31:0] in_l1,            // Input to load unit
//    output [31:0] out_l1            // Output from load unit
);

    // =========================================================
    // INTERMEDIATE WIRES
    // =========================================================

    // Program Counter signals
    wire [31:0] PC;                // Current PC
    wire [31:0] PC_Next;           // Next PC

    // Instruction memory signals
    wire [29:0] A_i;               // Instruction memory address
    wire [31:0] RD_i;              // Instruction fetched

    // Register file addressing
    wire [4:0]  A1;                // rs1
    wire [4:0]  A2;                // rs2
    wire [4:0]  A3;                // rd

    // Register file data
    wire [31:0] RD1;               // Data from rs1
    wire [31:0] RD2;               // Data from rs2
    wire [31:0] WD3;               // Writeback data
    wire        WE3;               // Register write enable

    // Immediate generation
    wire [31:0] Imm_Ext;           // Extended immediate
    wire [1:0]  ImmSrc;            // Immediate format selector
    wire        isLUI;              // LUI instruction indicator

    // ALU signals
    wire [31:0] operand1;          // ALU input A
    wire [31:0] operand2;          // ALU input B
    wire [31:0] alu_r;             // ALU output
    wire [31:0] alu_result;        // Final ALU/LUI output
    wire [3:0]  ctrl;              // ALU control
    wire   flags;             // ALU flags
    wire        ALUSrc;             // Immediate select

    // PC computation
    wire [31:0] pc_plus;           // PC + 4
    wire [31:0] pc_target_jb;      // Branch/JAL target
    wire [31:0] pc_target;         // Final jump target
    wire        isJALR;             // JALR flag
    wire        PCSrc;              // PC select

    // LUI/AUIPC
    wire        LUISrc;             // Select between LUI/AUIPC
    wire [31:0] lui_result;        // LUI/AUIPC output

    // Data memory
    wire        WE;                 // Memory write enable
    wire [31:0] A_d;               // Data memory address
    wire [31:0] WD_d;              // Store data
    wire [31:0] RD_d;              // Load data
    wire [3:0]  strobe;            // Byte enable

    // Load-store unit
    wire [4:0]  lsunit;            // Load/store control encoding
    wire [31:0] in_l;              // Input to LS unit
    wire [31:0] out_l;             // Output from LS unit
    wire [31:0] out_s;             // Store-aligned output
    wire [31:0] RD_dd;             // Final load-aligned data

    // Writeback
    wire [31:0] result;            // Final result to register file
    wire [1:0]  ResultSrc;         // Writeback mux select

    // =========================================================
    // PROGRAM COUNTER
    // =========================================================

  //  assign PC1      = PC;
  //  assign PC_next1 = PC_Next;

    program_counter program_counter (
        .clk     (clk),
        .rst     (rst),
        .PC_Next (PC_Next),
        .PC      (PC)
    );

    // =========================================================
    // INSTRUCTION MEMORY
    // =========================================================

    assign A_i   = PC[31:2];
   // assign A_i1  = A_i;
  //  assign RD_i1 = RD_i;

    instruction_memory instruction_memory (
        .rst (rst),
        .A   (A_i),
        .RD  (RD_i)
    );

    // =========================================================
    // REGISTER FILE
    // =========================================================

    assign A1 = RD_i[19:15];    // rs1
    assign A2 = RD_i[24:20];    // rs2
    assign A3 = RD_i[11:7];     // rd

  //  assign A11  = A1;
//    assign A21  = A2;
//    assign A31  = A3;
//    assign RD11 = RD1;
//    assign RD21 = RD2;
//    assign WD31 = WD3;
    //assign WE31 = WE3;

    register_file register_file (
        .clk (clk),
        .rst (rst),
        .WE3 (WE3),
        .A1  (A1),
        .A2  (A2),
        .A3  (A3),
        .WD3 (WD3),
        .RD1 (RD1),
        .RD2 (RD2)
    );

    // =========================================================
    // IMMEDIATE EXTENSION
    // =========================================================

//    assign Imm_Ext1 = Imm_Ext;
//    assign ImmSrc1  = ImmSrc;
//    assign isLUI1   = isLUI;

    sign_extend sign_extend (
        .In      (RD_i),
        .Imm_Ext (Imm_Ext),
        .ImmSrc  (ImmSrc),
        .isLUI   (isLUI)
    );

    // =========================================================
    // ALU
    // =========================================================

    assign operand1 = RD1;
    assign operand2 = (ALUSrc) ? Imm_Ext : RD2;

//    assign operand11   = operand1;
//    assign operand21   = operand2;
//    assign alu_r1      = alu_r;
//    assign alu_result1 = alu_result;
//    assign ctrl1       = ctrl;
//    assign flags1      = flags;
//    assign ALUSrc1     = ALUSrc;

    alu alu (
        .A      (operand1),
        .B      (operand2),
        .ctrl   (ctrl),
        .result (alu_r),
        .flags  (flags)
    );

    // =========================================================
    // PC + 4
    // =========================================================

   // assign pc_plus1 = pc_plus;

    pc_adder pc_plus4 (
        .a (PC),
        .b (32'd4),
        .c (pc_plus)
    );

    // =========================================================
    // BRANCH / JUMP TARGET
    // =========================================================

//    assign pc_target_jb1 = pc_target_jb;
//    assign isJALR1       = isJALR;

    pc_adder pc_target1 (
        .a (PC),
        .b (Imm_Ext),
        .c (pc_target_jb)
    );

    assign pc_target = (isJALR) ? alu_r : pc_target_jb;

    // =========================================================
    // LUI / AUIPC
    // =========================================================

//    assign LUISrc1     = LUISrc;
//    assign lui_result1 = lui_result;

    assign lui_result = (LUISrc) ? Imm_Ext : pc_target_jb;
    assign alu_result = (isLUI)  ? lui_result : alu_r;

    // =========================================================
    // PC SELECTION
    // =========================================================

//    assign PCSrc1  = PCSrc;
    assign PC_Next = (PCSrc) ? pc_target : pc_plus;

    // =========================================================
    // DATA MEMORY
    // =========================================================

    assign A_d  = alu_result;
    assign WD_d = RD2;

    assign WE1      = WE;
//    assign A_d1     = A_d;
//    assign WD_d1    = WD_d;
//    assign RD_d1    = RD_d;
//    assign strobe1  = strobe;

    data_memory data_memory (
        .clk   (clk),
        .rst   (rst),
        .WE    (WE),
        .WD    ((lsunit[4:3] == 2'b11) ? out_s : WD_d),
        .A     (A_d[31:2]),
        .RD    (RD_d),
        .WSTRB (strobe)
    );

    // =========================================================
    // LOAD-STORE UNIT
    // =========================================================

    assign in_l   = RD_d;
//    assign in_l1  = in_l;
//    assign out_l1 = out_l;

    assign RD_dd = (lsunit[4:3] == 2'b10) ? out_l : RD_d;

    ls_unit ls_unit (
        .in      (in_l),
        .lsunit  (lsunit),
        .out     (out_l),
        .strobe  (strobe),
        .address (A_d[1:0]),
        .in_s    (WD_d),
        .out_s   (out_s)
    );

    // =========================================================
    // WRITEBACK
    // =========================================================

    assign result =
        (ResultSrc == 2'b00) ? alu_result :
        (ResultSrc == 2'b01) ? RD_dd      :
                               pc_plus;

    assign WD3 = result;

//    assign result1    = result;
//    assign ResultSrc1 = ResultSrc;

    // =========================================================
    // CONTROL UNIT
    // =========================================================

    control_unit control_unit (
        //.in        (RD_i),
        .Op(RD_i[6:0]),        // Opcode field
   .funct7_30(RD_i[30]),    // funct7 field
    .funct3(RD_i[14:12]),
        .flags     (flags),
        .LUI_Src   (LUISrc),
        .isLUI     (isLUI),
        .isJALR    (isJALR),
        .regwrite  (WE3),
        .ImmSrc    (ImmSrc),
        .Memwrite  (WE),
        .ResultSrc (ResultSrc),
        .ALUSrc    (ALUSrc),
        .alu_ctrl  (ctrl),
        .PCSrc     (PCSrc),
        .lsunit    (lsunit)
    );

endmodule

