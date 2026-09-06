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

module execute_cycle(
    clk, rst, RegWriteE, ALUSrcE, MemWriteE, LUISrcE, isLUIE, ResultSrcE, BranchE, ALUControlE, 
    RD1_E, RD2_E, Imm_Ext_E, RD_E, PCE, PCPlus4E, PCSrcE, PCTargetE, RegWriteM, MemWriteM, 
    lsunitE, JumpE, ResultSrcM, RD_M, PCPlus4M, WriteDataM, ALU_ResultM, lsunitM, 
    ResultW, ForwardA_E, ForwardB_E, is_M_instruction, op, stallM
);  

    input clk, rst, RegWriteE, ALUSrcE, MemWriteE, LUISrcE, isLUIE, is_M_instruction;
    input [1:0] ResultSrcE, JumpE, ForwardA_E, ForwardB_E;
    input [3:0] BranchE, ALUControlE;
    input [4:0] lsunitE, RD_E;
    input [31:0] RD1_E, RD2_E, Imm_Ext_E, PCE, PCPlus4E, ResultW;
    input [2:0] op;

    output PCSrcE, RegWriteM, MemWriteM, stallM;
    output [1:0] ResultSrcM;
    output [4:0] RD_M, lsunitM;
    output [31:0] PCPlus4M, WriteDataM, ALU_ResultM, PCTargetE;

    wire [31:0] Src_A, Src_B_interim, Src_B, alu_r;
    wire [2:0] flags;

    Mux_3_by_1 srca_mux (.a(RD1_E), .b(ResultW), .c(ALU_ResultM), .s(ForwardA_E), .d(Src_A));
    Mux_3_by_1 srcb_mux (.a(RD2_E), .b(ResultW), .c(ALU_ResultM), .s(ForwardB_E), .d(Src_B_interim));
    Mux2 alu_src_mux (.a(Src_B_interim), .b(Imm_Ext_E), .s(ALUSrcE), .c(Src_B));

    ALU alu (.A(Src_A), .B(Src_B), .Result(alu_r), .ALUControl(ALUControlE), .flags(flags));

    // PERFECT M-EXTENSION MATH BYPASS (No stalling required!)
    wire signed [63:0] mul_ss = $signed(Src_A) * $signed(Src_B_interim);
    wire signed [63:0] mul_su = $signed(Src_A) * $signed({1'b0, Src_B_interim});
    wire [63:0] mul_uu = {1'b0, Src_A} * {1'b0, Src_B_interim};
    reg [31:0] math_result;
    
    always @(*) begin
        case (op)
            3'b000: math_result = mul_ss[31:0]; // MUL
            3'b001: math_result = mul_ss[63:32]; // MULH
            3'b010: math_result = mul_su[63:32]; // MULHSU
            3'b011: math_result = mul_uu[63:32]; // MULHU
            3'b100: math_result = (Src_B_interim == 0) ? 32'hFFFFFFFF :
                                  (Src_A == 32'h80000000 && Src_B_interim == 32'hFFFFFFFF) ? 32'h80000000 : 
                                  $signed(Src_A) / $signed(Src_B_interim); // DIV
            3'b101: math_result = (Src_B_interim == 0) ? 32'hFFFFFFFF : Src_A / Src_B_interim; // DIVU
            3'b110: math_result = (Src_B_interim == 0) ? Src_A :
                                  (Src_A == 32'h80000000 && Src_B_interim == 32'hFFFFFFFF) ? 32'h0 : 
                                  $signed(Src_A) % $signed(Src_B_interim); // REM
            3'b111: math_result = (Src_B_interim == 0) ? Src_A : Src_A % Src_B_interim; // REMU
        endcase
    end

    assign stallM = 0; 
    wire RegWriteE1 = RegWriteE; // Math is ready immediately

    wire [31:0] PCTarget_jb = PCE + Imm_Ext_E;
    wire yesE, JALRE;

    JB_unit JB(.flags(flags), .J(JumpE), .B(BranchE), .yes(yesE), .JALR(JALRE));

    assign PCTargetE = (JALRE) ? {alu_r[31:1], 1'b0} : PCTarget_jb;
    wire [31:0] ResultE = (isLUIE) ? (LUISrcE ? Imm_Ext_E : PCTarget_jb) : ((is_M_instruction) ? math_result : alu_r);

    reg RegWriteE_r, MemWriteE_r;
    reg [1:0] ResultSrcE_r;
    reg [4:0] RD_E_r, lsunitE_r;
    reg [31:0] PCPlus4E_r, RD2_E_r, ResultE_r;

    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            RegWriteE_r <= 0; MemWriteE_r <= 0; ResultSrcE_r <= 0;
            RD_E_r <= 0; lsunitE_r <= 0; PCPlus4E_r <= 0; RD2_E_r <= 0; ResultE_r <= 0;
        end else begin
            RegWriteE_r <= RegWriteE1; MemWriteE_r <= MemWriteE; ResultSrcE_r <= ResultSrcE;
            RD_E_r <= RD_E; lsunitE_r <= lsunitE; PCPlus4E_r <= PCPlus4E;
            RD2_E_r <= Src_B_interim; ResultE_r <= ResultE;
        end
    end

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

// `timescale 1ns / 1ps
// module execute_cycle(
//     clk, rst, RegWriteE, ALUSrcE, MemWriteE, LUISrcE, isLUIE, ResultSrcE, BranchE, ALUControlE, 
//     RD1_E, RD2_E, Imm_Ext_E, RD_E, PCE, PCPlus4E, PCSrcE, PCTargetE, RegWriteM, MemWriteM, 
//     lsunitE, JumpE, ResultSrcM, RD_M, PCPlus4M, WriteDataM, ALU_ResultM, lsunitM, 
//     ResultW, ForwardA_E, ForwardB_E, is_M_instruction, op, stallM
// );  

//     input clk, rst;
//     input RegWriteE, ALUSrcE, MemWriteE, LUISrcE, isLUIE, is_M_instruction;
//     input [1:0] ResultSrcE, JumpE, ForwardA_E, ForwardB_E;
//     input [3:0] BranchE, ALUControlE;
//     input [4:0] lsunitE, RD_E;
//     input [31:0] RD1_E, RD2_E, Imm_Ext_E, PCE, PCPlus4E, ResultW;
//     input [2:0] op;

//     output PCSrcE, RegWriteM, MemWriteM, stallM;
//     output [1:0] ResultSrcM;
//     output [4:0] RD_M, lsunitM;
//     output [31:0] PCPlus4M, WriteDataM, ALU_ResultM, PCTargetE;

//     wire [31:0] Src_A, Src_B_interim, Src_B, alu_r, result_M;
//     wire [2:0] flags;

//     Mux_3_by_1 srca_mux (.a(RD1_E), .b(ResultW), .c(ALU_ResultM), .s(ForwardA_E), .d(Src_A));
//     Mux_3_by_1 srcb_mux (.a(RD2_E), .b(ResultW), .c(ALU_ResultM), .s(ForwardB_E), .d(Src_B_interim));
//     Mux2 alu_src_mux (.a(Src_B_interim), .b(Imm_Ext_E), .s(ALUSrcE), .c(Src_B));

//     ALU alu (.A(Src_A), .B(Src_B), .Result(alu_r), .ALUControl(ALUControlE), .flags(flags));

//     // BULLETPROOF M-EXTENSION OVERRIDE
//     reg [5:0] m_stall_counter;
//     always @(posedge clk or negedge rst) begin
//         if (!rst) m_stall_counter <= 0;
//         else if (is_M_instruction && m_stall_counter == 0) m_stall_counter <= (op[2]) ? 35 : 3;
//         else if (m_stall_counter > 0) m_stall_counter <= m_stall_counter - 1;
//     end
    
//     assign stallM = (is_M_instruction && m_stall_counter > 0);
//     wire valid_M = (is_M_instruction && m_stall_counter == 1);
//     wire start_M = (is_M_instruction && m_stall_counter == 0);
//     wire [4:0] rd_me;

//     rv32m_unit m(
//         .clk(clk), .rst_n(rst), .rs1(Src_A), .rs2(Src_B), .funct3(op),
//         .rd_in(RD_E), .valid_in(start_M), .stall(), .result(result_M),
//         .rd_out(rd_me), .valid_out()
//     );

//     wire [4:0] RD_E1 = (valid_M) ? rd_me : RD_E;
//     wire RegWriteE1 = (is_M_instruction) ? 0 : (valid_M) ? 1 : RegWriteE;

//     wire [31:0] PCTarget_jb = PCE + Imm_Ext_E;
//     wire yesE, JALRE;

//     JB_unit JB(.flags(flags), .J(JumpE), .B(BranchE), .yes(yesE), .JALR(JALRE));

//     assign PCTargetE = (JALRE) ? {alu_r[31:1], 1'b0} : PCTarget_jb;
//     wire [31:0] ResultE = (isLUIE) ? (LUISrcE ? Imm_Ext_E : PCTarget_jb) : ((valid_M) ? result_M : alu_r);

//     reg RegWriteE_r, MemWriteE_r;
//     reg [1:0] ResultSrcE_r;
//     reg [4:0] RD_E_r, lsunitE_r;
//     reg [31:0] PCPlus4E_r, RD2_E_r, ResultE_r;

//     always @(posedge clk or negedge rst) begin
//         if(!rst) begin
//             RegWriteE_r <= 0; MemWriteE_r <= 0; ResultSrcE_r <= 0;
//             RD_E_r <= 0; lsunitE_r <= 0; PCPlus4E_r <= 0; RD2_E_r <= 0; ResultE_r <= 0;
//         end else begin
//             RegWriteE_r <= RegWriteE1; MemWriteE_r <= MemWriteE; ResultSrcE_r <= ResultSrcE;
//             RD_E_r <= RD_E1; lsunitE_r <= lsunitE; PCPlus4E_r <= PCPlus4E;
//             RD2_E_r <= Src_B_interim; ResultE_r <= ResultE;
//         end
//     end

//     assign PCSrcE = yesE;
//     assign RegWriteM = RegWriteE_r;
//     assign MemWriteM = MemWriteE_r;
//     assign ResultSrcM = ResultSrcE_r;
//     assign RD_M = RD_E_r;
//     assign PCPlus4M = PCPlus4E_r;
//     assign WriteDataM = RD2_E_r;
//     assign ALU_ResultM = ResultE_r;
//     assign lsunitM = lsunitE_r;
// endmodule

//ORGINAL
// module execute_cycle(clk, rst, RegWriteE, ALUSrcE, MemWriteE, LUISrcE,isLUIE, ResultSrcE, BranchE, ALUControlE, 
//     RD1_E, RD2_E, Imm_Ext_E, RD_E, PCE, PCPlus4E, PCSrcE, PCTargetE, RegWriteM, MemWriteM, 
//     lsunitE,JumpE,ResultSrcM, RD_M, PCPlus4M, WriteDataM, ALU_ResultM,lsunitM, 
//     ResultW, ForwardA_E, ForwardB_E,
    
//     is_M_instruction,op,stallM);  

//     // ------------------------
//     // Inputs
//     // ------------------------
//     input clk, rst;

//     // Control signals from Decode stage
//     input RegWriteE, ALUSrcE, MemWriteE;
//     input LUISrcE, isLUIE;
//     input [1:0] ResultSrcE, JumpE;
//     input [3:0] BranchE;
//     input [4:0] lsunitE;
//     input [3:0] ALUControlE;
//     input is_M_instruction;
//     input [2:0] op;

//     // Data signals from Decode stage
//     input [31:0] RD1_E, RD2_E, Imm_Ext_E;
//     input [4:0] RD_E;
//     input [31:0] PCE, PCPlus4E;

//     // Forwarding input
//     input [31:0] ResultW;
//     input [1:0] ForwardA_E, ForwardB_E;

//     // ------------------------
//     // Outputs
//     // ------------------------
//     output PCSrcE;                 // Branch/jump taken
//     output RegWriteM, MemWriteM;   // To Memory stage
//     output [1:0] ResultSrcM;
//     output [4:0] RD_M, lsunitM;
//     output [31:0] PCPlus4M, WriteDataM, ALU_ResultM;
//     output [31:0] PCTargetE;       // Next PC target if taken
    
//     output stallM;
    
    
//     //wire regwrite1;
    
    

//     // ==================================================
//     // Internal Wires
//     // ==================================================

//     wire [31:0] Src_A;             // ALU operand A (after forwarding)
//     wire [31:0] Src_B_interim;     // Forwarded RD2
//     wire [31:0] Src_B;             // Final ALU operand B
//     wire [31:0] alu_r;             // Raw ALU result
//     //wire ZeroE;                    // Zero flag from ALU
//     wire [2:0] flags; // Replaces ZeroE

//     // ==================================================
//     // Forwarding MUXes
//     // ==================================================

//     // Source A forwarding:
//     // 00 → RD1_E
//     // 01 → ResultW (WB stage)
//     // 10 → ALU_ResultM (MEM stage)
//     Mux_3_by_1 srca_mux (
//         .a(RD1_E),
//         .b(ResultW),
//         .c(ALU_ResultM),
//         .s(ForwardA_E),
//         .d(Src_A)
//     );

//     // Source B forwarding (before ALUSrc selection)
//     Mux_3_by_1 srcb_mux (
//         .a(RD2_E),
//         .b(ResultW),
//         .c(ALU_ResultM),
//         .s(ForwardB_E),
//         .d(Src_B_interim)
//     );

//     // ALU second operand selection:
//     // 0 → register value
//     // 1 → immediate
//     Mux2 alu_src_mux (
//         .a(Src_B_interim),
//         .b(Imm_Ext_E),
//         .s(ALUSrcE),
//         .c(Src_B)
//     );

//     // ==================================================
//     // ALU
//     // ==================================================

//     // ALU alu (
//     //     .A(Src_A),
//     //     .B(Src_B),
//     //     .Result(alu_r),
//     //     .ALUControl(ALUControlE),
//     //     .Zero(ZeroE)
//     // );
//     ALU alu (
//         .A(Src_A),
//         .B(Src_B),
//         .Result(alu_r),
//         .ALUControl(ALUControlE),
//         .flags(flags) // Bound to new flags output
//     );

//     // ==================================================
//     // M extension
//     // ==================================================
    
//     reg prev_M;
//     wire [31:0] result_M;
//     //reg busy_M,done_M;

//     always @(posedge clk) begin
//         prev_M <= is_M_instruction;
//     end

//     assign start = is_M_instruction & ~prev_M;
//     wire valid_M;
//     wire [4:0] rd_me;
    
//     rv32m_unit m(
//     .clk(clk),
//     .rst_n(rst),
 
//     // From EX stage decoder
//     .rs1(Src_A),
//     .rs2(Src_B),
//     .funct3(op),       // 3-bit M-ext op code
//     .rd_in(RD_E),
//     .valid_in(start),//is_M_instruction),     // 1 = this is an M-ext instruction
 
//     // To hazard/stall unit
//     .stall(stallM),        // 1 = freeze upstream pipeline stages
 
//     // To WB stage
//     .result(result_M),
//     .rd_out(rd_me),
//     .valid_out(valid_M)
// );
//     wire [4:0] RD_E1=(valid_M)?rd_me:RD_E;
//     wire RegWriteE1=(is_M_instruction)?0:(valid_M)?1:RegWriteE;
//     // ==================================================
//     // Branch Target Calculation (PC + Imm)
//     // ==================================================

//     wire [31:0] PCTarget_jb;

//     PC_Adder branch_adder (
//         .a(PCE),
//         .b(Imm_Ext_E),
//         .c(PCTarget_jb)
//     );
    

//     // ==================================================
//     // Jump / Branch Decision Logic
//     // ==================================================

//     wire yesE;        // Branch or jump taken
//     wire JALRE;       // JALR detected

//     // JB_unit JB(
//     //     .Zero(ZeroE),
//     //     .J(JumpE),
//     //     .B(BranchE),
//     //     .yes(yesE),
//     //     .JALR(JALRE)
//     // );
//     JB_unit JB(
//         .flags(flags), // Bound to new flags
//         .J(JumpE),
//         .B(BranchE),
//         .yes(yesE),
//         .JALR(JALRE)
//     );

//     // ==================================================
//     // LUI / AUIPC Handling
//     // ==================================================

//     // For LUI:
//     //   LUISrcE = 1 → use immediate
//     // For AUIPC:
//     //   LUISrcE = 0 → use PC + immediate
//     wire [31:0] LUI_result_E;
//     assign LUI_result_E = (LUISrcE) ? Imm_Ext_E : PCTarget_jb;

//     // ==================================================
//     // Final PC Target Selection
//     // ==================================================

//     // JALR target uses ALU result
//     // Otherwise use PC + immediate

//     // FIXED: JALR forces LSB to 0 to prevent misaligned traps
//     assign PCTargetE = (JALRE) ? {alu_r[31:1], 1'b0} : PCTarget_jb;
//     // assign PCTargetE = (JALRE) ? alu_r : PCTarget_jb;
    

//     // ==================================================
//     // Final Result Selection
//     // ==================================================

//     // If instruction is LUI/AUIPC, override ALU result
//     wire [31:0] ResultE;
//     assign ResultE = (isLUIE) ? LUI_result_E : ((valid_M)?result_M:alu_r);

//     // ==================================================
//     // EX → MEM Pipeline Registers
//     // ==================================================

//     reg RegWriteE_r, MemWriteE_r;
//     reg [1:0] ResultSrcE_r;
//     reg [4:0] RD_E_r, lsunitE_r;
//     reg [31:0] PCPlus4E_r, RD2_E_r, ResultE_r;

//     always @(posedge clk or negedge rst) begin
//         if(!rst /*== 1'b0*/) begin
//             RegWriteE_r <= 1'b0;
//             MemWriteE_r <= 1'b0;
//             ResultSrcE_r <= 2'b00;
//             RD_E_r <= 5'h00;
//             lsunitE_r <= 5'h00;
//             PCPlus4E_r <= 32'h00000000;
//             RD2_E_r <= 32'h00000000;
//             ResultE_r <= 32'h00000000;
//         end
//         else begin
//             RegWriteE_r <= RegWriteE1;
//             MemWriteE_r <= MemWriteE;
//             ResultSrcE_r <= ResultSrcE;
//             RD_E_r <= RD_E1;
//             lsunitE_r <= lsunitE;
//             PCPlus4E_r <= PCPlus4E;

//             // IMPORTANT:
//             // Store data must use forwarded register value,
//             // not the ALUSrc-selected value
//             RD2_E_r <= Src_B_interim;

//             ResultE_r <= ResultE;
//         end
//     end

//     // ==================================================
//     // Outputs to Memory Stage
//     // ==================================================

//     assign PCSrcE = yesE;
//     assign RegWriteM = RegWriteE_r;
//     assign MemWriteM = MemWriteE_r;
//     assign ResultSrcM = ResultSrcE_r;
//     assign RD_M = RD_E_r;
//     assign PCPlus4M = PCPlus4E_r;
//     assign WriteDataM = RD2_E_r;
//     assign ALU_ResultM = ResultE_r;
//     assign lsunitM = lsunitE_r;

// endmodule
