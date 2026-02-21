`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: execute_cycle
//
// Description:
// Execute (EX) stage of 5-stage RISC-V pipeline.
//
// Responsibilities:
//   - Apply forwarding to ALU operands
//   - Perform ALU operations
//   - Compute branch/jump decision
//   - Compute branch/jump target address
//   - Handle LUI/AUIPC special result path
//   - Pass results into EX/MEM pipeline registers
//
// Reset:
//   Active-low reset clears EX/MEM pipeline registers
//////////////////////////////////////////////////////////////////////////////////

module execute_cycle(clk, rst, RegWriteE, ALUSrcE, MemWriteE, LUISrcE,isLUIE, ResultSrcE, BranchE, ALUControlE, 
    RD1_E, RD2_E, Imm_Ext_E, RD_E, PCE, PCPlus4E, PCSrcE, PCTargetE, RegWriteM, MemWriteM, 
    lsunitE,JumpE,ResultSrcM, RD_M, PCPlus4M, WriteDataM, ALU_ResultM,lsunitM, 
    ResultW, ForwardA_E, ForwardB_E);  

    // ------------------------
    // Inputs
    // ------------------------
    input clk, rst;

    // Control signals from Decode stage
    input RegWriteE, ALUSrcE, MemWriteE;
    input LUISrcE, isLUIE;
    input [1:0] ResultSrcE, JumpE;
    input [3:0] BranchE;
    input [4:0] lsunitE;
    input [3:0] ALUControlE;

    // Data signals from Decode stage
    input [31:0] RD1_E, RD2_E, Imm_Ext_E;
    input [4:0] RD_E;
    input [31:0] PCE, PCPlus4E;

    // Forwarding input
    input [31:0] ResultW;
    input [1:0] ForwardA_E, ForwardB_E;

    // ------------------------
    // Outputs
    // ------------------------
    output PCSrcE;                 // Branch/jump taken
    output RegWriteM, MemWriteM;   // To Memory stage
    output [1:0] ResultSrcM;
    output [4:0] RD_M, lsunitM;
    output [31:0] PCPlus4M, WriteDataM, ALU_ResultM;
    output [31:0] PCTargetE;       // Next PC target if taken

    // ==================================================
    // Internal Wires
    // ==================================================

    wire [31:0] Src_A;             // ALU operand A (after forwarding)
    wire [31:0] Src_B_interim;     // Forwarded RD2
    wire [31:0] Src_B;             // Final ALU operand B
    wire [31:0] alu_r;             // Raw ALU result
    wire ZeroE;                    // Zero flag from ALU

    // ==================================================
    // Forwarding MUXes
    // ==================================================

    // Source A forwarding:
    // 00 → RD1_E
    // 01 → ResultW (WB stage)
    // 10 → ALU_ResultM (MEM stage)
    Mux_3_by_1 srca_mux (
        .a(RD1_E),
        .b(ResultW),
        .c(ALU_ResultM),
        .s(ForwardA_E),
        .d(Src_A)
    );

    // Source B forwarding (before ALUSrc selection)
    Mux_3_by_1 srcb_mux (
        .a(RD2_E),
        .b(ResultW),
        .c(ALU_ResultM),
        .s(ForwardB_E),
        .d(Src_B_interim)
    );

    // ALU second operand selection:
    // 0 → register value
    // 1 → immediate
    Mux2 alu_src_mux (
        .a(Src_B_interim),
        .b(Imm_Ext_E),
        .s(ALUSrcE),
        .c(Src_B)
    );

    // ==================================================
    // ALU
    // ==================================================

    ALU alu (
        .A(Src_A),
        .B(Src_B),
        .Result(alu_r),
        .ALUControl(ALUControlE),
        .Zero(ZeroE)
    );

    // ==================================================
    // Branch Target Calculation (PC + Imm)
    // ==================================================

    wire [31:0] PCTarget_jb;

    PC_Adder branch_adder (
        .a(PCE),
        .b(Imm_Ext_E),
        .c(PCTarget_jb)
    );

    // ==================================================
    // Jump / Branch Decision Logic
    // ==================================================

    wire yesE;        // Branch or jump taken
    wire JALRE;       // JALR detected

    JB_unit JB(
        .Zero(ZeroE),
        .J(JumpE),
        .B(BranchE),
        .yes(yesE),
        .JALR(JALRE)
    );

    // ==================================================
    // LUI / AUIPC Handling
    // ==================================================

    // For LUI:
    //   LUISrcE = 1 → use immediate
    // For AUIPC:
    //   LUISrcE = 0 → use PC + immediate
    wire [31:0] LUI_result_E;
    assign LUI_result_E = (LUISrcE) ? Imm_Ext_E : PCTarget_jb;

    // ==================================================
    // Final PC Target Selection
    // ==================================================

    // JALR target uses ALU result
    // Otherwise use PC + immediate
    assign PCTargetE = (JALRE) ? alu_r : PCTarget_jb;

    // ==================================================
    // Final Result Selection
    // ==================================================

    // If instruction is LUI/AUIPC, override ALU result
    wire [31:0] ResultE;
    assign ResultE = (isLUIE) ? LUI_result_E : alu_r;

    // ==================================================
    // EX → MEM Pipeline Registers
    // ==================================================

    reg RegWriteE_r, MemWriteE_r;
    reg [1:0] ResultSrcE_r;
    reg [4:0] RD_E_r, lsunitE_r;
    reg [31:0] PCPlus4E_r, RD2_E_r, ResultE_r;

    always @(posedge clk or negedge rst) begin
        if(!rst /*== 1'b0*/) begin
            RegWriteE_r <= 1'b0;
            MemWriteE_r <= 1'b0;
            ResultSrcE_r <= 2'b00;
            RD_E_r <= 5'h00;
            lsunitE_r <= 5'h00;
            PCPlus4E_r <= 32'h00000000;
            RD2_E_r <= 32'h00000000;
            ResultE_r <= 32'h00000000;
        end
        else begin
            RegWriteE_r <= RegWriteE;
            MemWriteE_r <= MemWriteE;
            ResultSrcE_r <= ResultSrcE;
            RD_E_r <= RD_E;
            lsunitE_r <= lsunitE;
            PCPlus4E_r <= PCPlus4E;

            // IMPORTANT:
            // Store data must use forwarded register value,
            // not the ALUSrc-selected value
            RD2_E_r <= Src_B_interim;

            ResultE_r <= ResultE;
        end
    end

    // ==================================================
    // Outputs to Memory Stage
    // ==================================================

    assign PCSrcE = yesE;
    assign RegWriteM = RegWriteE_r;
    assign MemWriteM = MemWriteE_r;
    assign ResultSrcM = ResultSrcE_r;
    assign RD_M = RD_E_r;
    assign PCPlus4M = PCPlus4E_r;
    assign WriteDataM = RD2_E_r;
    assign ALU_ResultM = ResultE_r;
    assign lsunitM = lsunitE_r;

endmodule
