`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: rv32_core
// Description: Standalone RISC-V RV32I Processor Core with Decoupled Memory Bus
//////////////////////////////////////////////////////////////////////////////////

module rv32_core (
    input         clk,
    input         rst,

    // Instruction Memory Interface
    output [31:0] imem_addr,    // Instruction Address (PC)
    input  [31:0] imem_rdata,   // Instruction Read Data

    // Data Memory Interface
    output [31:0] dmem_addr,    // Data Address
    output [31:0] dmem_wdata,   // Data Write Data (aligned)
    input  [31:0] dmem_rdata,   // Data Read Data
    output        dmem_we,      // Data Write Enable
    output [3:0]  dmem_strobe,  // Data Byte Enable Strobe

    // Output Signals
    output        WE1,
    output [31:0] a0_val
);

    // =========================================================
    // INTERMEDIATE WIRES
    // =========================================================

    // Program Counter signals
    wire [31:0] PC;                // Current PC
    wire [31:0] PC_Next;           // Next PC

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
    wire        isLUI;             // LUI instruction indicator

    // ALU signals
    wire [31:0] operand1;          // ALU input A
    wire [31:0] operand2;          // ALU input B
    wire [31:0] alu_r;             // ALU output
    wire [31:0] alu_result;        // Final ALU/LUI output
    wire [3:0]  ctrl;              // ALU control
    wire        flags;             // ALU flags
    wire        ALUSrc;            // Immediate select

    // PC computation
    wire [31:0] pc_plus;           // PC + 4
    wire [31:0] pc_target_jb;      // Branch/JAL target
    wire [31:0] pc_target;         // Final jump target
    wire        isJALR;            // JALR flag
    wire        PCSrc;             // PC select

    // LUI/AUIPC
    wire        LUISrc;            // Select between LUI/AUIPC
    wire [31:0] lui_result;        // LUI/AUIPC output

    // Data memory signals
    wire        WE;                // Memory write enable

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
    // INSTRUCTION BUS ASSIGNMENT
    // =========================================================
    assign imem_addr = PC;

    // =========================================================
    // PROGRAM COUNTER
    // =========================================================
    program_counter program_counter (
        .clk     (clk),
        .rst     (rst),
        .PC_Next (PC_Next),
        .PC      (PC)
    );

    // =========================================================
    // REGISTER FILE
    // =========================================================
    assign A1 = imem_rdata[19:15];    // rs1
    assign A2 = imem_rdata[24:20];    // rs2
    assign A3 = imem_rdata[11:7];     // rd

    register_file register_file (
        .clk (clk),
        .rst (rst),
        .WE3 (WE3),
        .A1  (A1),
        .A2  (A2),
        .A3  (A3),
        .WD3    (WD3),
        .RD1    (RD1),
        .RD2    (RD2),
        .a0_val (a0_val)
    );

    // =========================================================
    // IMMEDIATE EXTENSION
    // =========================================================
    sign_extend sign_extend (
        .In      (imem_rdata),
        .Imm_Ext (Imm_Ext),
        .ImmSrc  (ImmSrc),
        .isLUI   (isLUI)
    );

    // =========================================================
    // ALU
    // =========================================================
    assign operand1 = RD1;
    assign operand2 = (ALUSrc) ? Imm_Ext : RD2;

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
    pc_adder pc_plus4 (
        .a (PC),
        .b (32'd4),
        .c (pc_plus)
    );

    // =========================================================
    // BRANCH / JUMP TARGET
    // =========================================================
    pc_adder pc_target1 (
        .a (PC),
        .b (Imm_Ext),
        .c (pc_target_jb)
    );

    assign pc_target = (isJALR) ? alu_r : pc_target_jb;

    // =========================================================
    // LUI / AUIPC
    // =========================================================
    assign lui_result = (LUISrc) ? Imm_Ext : pc_target_jb;
    assign alu_result = (isLUI)  ? lui_result : alu_r;

    // =========================================================
    // PC SELECTION
    // =========================================================
    assign PC_Next = (PCSrc) ? pc_target : pc_plus;

    // =========================================================
    // DATA MEMORY BUS ASSIGNMENT
    // =========================================================
    assign dmem_addr  = alu_result;
    assign dmem_we    = WE;
    assign dmem_wdata = (lsunit[4:3] == 2'b11) ? out_s : RD2;
    assign WE1        = WE;

    // =========================================================
    // LOAD-STORE UNIT
    // =========================================================
    assign in_l  = dmem_rdata;
    assign RD_dd = (lsunit[4:3] == 2'b10) ? out_l : dmem_rdata;

    ls_unit ls_unit (
        .in      (in_l),
        .lsunit  (lsunit),
        .out     (out_l),
        .strobe  (dmem_strobe),
        .address (dmem_addr[1:0]),
        .in_s    (RD2),
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

    // =========================================================
    // CONTROL UNIT
    // =========================================================
    control_unit control_unit (
        .Op        (imem_rdata[6:0]),   // Opcode field
        .funct7_30 (imem_rdata[30]),    // funct7 field
        .funct3    (imem_rdata[14:12]),
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
