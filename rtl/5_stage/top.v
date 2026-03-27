`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : top
//
// Description:
//  Top-level integration of a 5-stage pipelined RISC-V processor.
//
//  Pipeline stages:
//      IF  → fetch_cycle
//      ID  → decode_cycle
//      EX  → execute_cycle
//      MEM → memory_cycle
//      WB  → writeback_cycle
//
//  Also integrates:
//      - Hazard unit (forwarding + stall logic)
//
//  Notes:
//      - Active-low reset
//      - All stage interconnections handled here
//
//////////////////////////////////////////////////////////////////////////////////

module top(

    input clk,
    input rst,

    // Debug output
    output PCSrcE1
);

    // ==================================================
    // Global Inter-Stage Wires
    // ==================================================

    wire PCSrcE;

    wire RegWriteW;
    wire RegWriteE;
    wire ALUSrcE;
    wire MemWriteE;
    wire RegWriteM;
    wire MemWriteM;

    wire [3:0] ALUControlE;
    wire [3:0] BranchE;

    wire [4:0] RD_E;
    wire [4:0] RD_M;
    wire [4:0] RDW;

    wire [4:0] lsunitE;
    wire [4:0] lsunitM;

    wire [31:0] PCTargetE;
    wire [31:0] InstrD;
    wire [31:0] PCD;
    wire [31:0] PCPlus4D;

    wire [31:0] ResultW;

    wire [31:0] RD1_E;
    wire [31:0] RD2_E;
    wire [31:0] Imm_Ext_E;

    wire [31:0] PCE;
    wire [31:0] PCPlus4E;
    wire [31:0] PCPlus4M;
    wire [31:0] WriteDataM;
    wire [31:0] ALU_ResultM;

    wire [31:0] PCPlus4W;
    wire [31:0] ALU_ResultW;
    wire [31:0] ReadDataW;

    wire [4:0] RS1_E;
    wire [4:0] RS2_E;
    wire [4:0] RS1_D;
    wire [4:0] RS2_D;

    wire [1:0] ForwardBE;
    wire [1:0] ForwardAE;
    wire [1:0] ResultSrcE;
    wire [1:0] ResultSrcM;
    wire [1:0] ResultSrcW;
    wire [1:0] JumpE;

    wire StallF;
    wire StallD;
    wire FlushE;
    wire FlushD;

    // --------------------------------------------------
    // ❗ Missing wires in your original code
    // --------------------------------------------------

    wire LUISrcE;
    wire isLUIE;
    
    wire [2:0] op;

    assign PCSrcE1 = PCSrcE;

    // ==================================================
    // Stage Instantiations
    // ==================================================

    // ---------------- IF ----------------
    fetch_cycle Fetch (
        .clk(clk),
        .rst(rst),
        .PCSrcE(PCSrcE),
        .PCTargetE(PCTargetE),
        .InstrD(InstrD),
        .PCD(PCD),
        .PCPlus4D(PCPlus4D),
        .StallF(StallF),
        .StallD(StallD),
        .FlushD(FlushD)
    );

    // ---------------- ID ----------------
    decode_cycle Decode (
        .clk(clk),
        .rst(rst),
        .InstrD(InstrD),
        .PCD(PCD),
        .PCPlus4D(PCPlus4D),
        .RegWriteW(RegWriteW),
        .RDW(RDW),
        .ResultW(ResultW),
        .RegWriteE(RegWriteE),
        .ALUSrcE(ALUSrcE),
        .MemWriteE(MemWriteE),
        .ResultSrcE(ResultSrcE),
        .BranchE(BranchE),
        .ALUControlE(ALUControlE),
        .RD1_E(RD1_E),
        .RD2_E(RD2_E),
        .Imm_Ext_E(Imm_Ext_E),
        .RD_E(RD_E),
        .PCE(PCE),
        .PCPlus4E(PCPlus4E),
        .RS1_E(RS1_E),
        .RS2_E(RS2_E),
        .JumpE(JumpE),
        .lsunitE(lsunitE),
        .RS1_D(RS1_D),
        .RS2_D(RS2_D),
        .FlushE(FlushE),
        .LUISrcE(LUISrcE),
        .isLUIE(isLUIE),
        .illegal_instr(illegal_instr),
        .is_M_instruction(is_M_instruction),
        .op(op)
    );

    // ---------------- EX ----------------
    execute_cycle Execute (
        .clk(clk),
        .rst(rst),
        .RegWriteE(RegWriteE),
        .ALUSrcE(ALUSrcE),
        .MemWriteE(MemWriteE),
        .ResultSrcE(ResultSrcE),
        .BranchE(BranchE),
        .ALUControlE(ALUControlE),
        .RD1_E(RD1_E),
        .RD2_E(RD2_E),
        .Imm_Ext_E(Imm_Ext_E),
        .RD_E(RD_E),
        .PCE(PCE),
        .PCPlus4E(PCPlus4E),
        .PCSrcE(PCSrcE),
        .PCTargetE(PCTargetE),
        .RegWriteM(RegWriteM),
        .MemWriteM(MemWriteM),
        .ResultSrcM(ResultSrcM),
        .RD_M(RD_M),
        .PCPlus4M(PCPlus4M),
        .WriteDataM(WriteDataM),
        .ALU_ResultM(ALU_ResultM),
        .ResultW(ResultW),
        .ForwardA_E(ForwardAE),
        .ForwardB_E(ForwardBE),
        .lsunitE(lsunitE),
        .JumpE(JumpE),
        .lsunitM(lsunitM),
        .LUISrcE(LUISrcE),
        .isLUIE(isLUIE),
        .stallM(stallM),
        .is_M_instruction(is_M_instruction),
        .op(op)
    );

    // ---------------- MEM ----------------
    memory_cycle Memory (
        .clk(clk),
        .rst(rst),
        .RegWriteM(RegWriteM),
        .MemWriteM(MemWriteM),
        .ResultSrcM(ResultSrcM),
        .RD_M(RD_M),
        .lsunitM(lsunitM),
        .PCPlus4M(PCPlus4M),
        .WriteDataM(WriteDataM),
        .ALU_ResultM(ALU_ResultM),
        .RegWriteW(RegWriteW),
        .ResultSrcW(ResultSrcW),
        .RD_W(RDW),
        .PCPlus4W(PCPlus4W),
        .ALU_ResultW(ALU_ResultW),
        .ReadDataW(ReadDataW)
    );

    // ---------------- WB ----------------
    writeback_cycle WriteBack (
       // .clk(clk),
       // .rst(rst),
        .ResultSrcW(ResultSrcW),
        .PCPlus4W(PCPlus4W),
        .ALU_ResultW(ALU_ResultW),
        .ReadDataW(ReadDataW),
        .ResultW(ResultW)
    );

    // ---------------- Hazard ----------------
    hazard_unit Forwarding_block (
        .rst(rst),
        .RegWriteM(RegWriteM),
        .RegWriteW(RegWriteW),
        .RD_M(RD_M),
        .RD_W(RDW),
        .Rs1_E(RS1_E),
        .Rs2_E(RS2_E),
        .Rs1_D(RS1_D),
        .Rs2_D(RS2_D),
        .RdE(RD_E),
        .ForwardAE(ForwardAE),
        .ForwardBE(ForwardBE),
        .ResultSrcE(ResultSrcE),
        .PCSrcE(PCSrcE),
        .StallF(StallF),
        .StallD(StallD),
        .FlushE(FlushE),
        .FlushD(FlushD),
        .illegal_instr(illegal_instr),
        .stallM(stallM)
    );

endmodule
