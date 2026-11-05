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
//   - Handle LUI/AUIPC and CSR result path
//   - Pass results into EX/MEM pipeline registers
//
// Reset:
//   Active-low synchronous reset clears EX/MEM pipeline registers
//////////////////////////////////////////////////////////////////////////////////

module execute_cycle (
    clk,
    rst_n,
    FlushM,
    RegWriteE,
    ALUSrcE,
    MemWriteE,
    LUISrcE,
    isLUIE,
    ResultSrcE,
    BranchE,
    ALUControlE,
    lsunitE,
    JumpE,
    RD1_E,
    RD2_E,
    Imm_Ext_E,
    RD_E,
    PCE,
    PCPlus4E,
    valid_E,
    exc_valid_E,
    exc_cause_E,
    exc_tval_E,
    exc_pc_E,
    is_mret_E,
    irq_pending_i,
    irq_id_i,
    irq_flush_frontend_o,
    ResultW,
    ForwardA_E,
    ForwardB_E,
    csr_valid_E,
    csr_imm_mode_E,
    csr_op_E,
    csr_rs1_uimm_E,
    csr_addr_E,

    csr_raddr_o,
    csr_rdata_i,

    PCSrcE,
    PCTargetE,
    RegWriteM,
    MemWriteM,
    ResultSrcM,
    RD_M,
    PC_M,
    PCPlus4M,
    WriteDataM,
    ALU_ResultM,
    lsunitM,
    valid_M,
    exc_valid_M,
    exc_cause_M,
    exc_tval_M,
    exc_pc_M,

    is_mret_M,

    csr_write_en_M,
    csr_addr_M,
    new_csr_M,
    old_csr_M,

    // M-extension ports
    is_M_instruction_E,
    op_E,
    stallMUL,
    StallM,
    FlushE
);

    input clk;
    input rst_n;
    input FlushM;
    input FlushE;
    input StallM;

    input RegWriteE;
    input ALUSrcE;
    input MemWriteE;
    input LUISrcE;
    input isLUIE;
    input [1:0] ResultSrcE;
    input [3:0] BranchE;
    input [3:0] ALUControlE;
    input [4:0] lsunitE;
    input [1:0] JumpE;

    input [31:0] RD1_E;
    input [31:0] RD2_E;
    input [31:0] Imm_Ext_E;
    input [4:0] RD_E;
    input [31:0] PCE;
    input [31:0] PCPlus4E;
    input valid_E;
    input exc_valid_E;
    input [5:0] exc_cause_E;
    input [31:0] exc_tval_E;
    input [31:0] exc_pc_E;
    input is_mret_E;
    input irq_pending_i;
    input [30:0] irq_id_i;
    output irq_flush_frontend_o;

    input [31:0] ResultW;
    input [1:0] ForwardA_E;
    input [1:0] ForwardB_E;

    //csr instrucction inputs from decode stage
    input csr_valid_E;
    input csr_imm_mode_E;
    input [1:0] csr_op_E;
    input [4:0] csr_rs1_uimm_E;
    input [11:0] csr_addr_E;

    // M-extension inputs/outputs
    input is_M_instruction_E;
    input [2:0] op_E;
    output stallMUL; // M-extension multiply/divide stall output

    //csr read interface
    output [11:0] csr_raddr_o;
    input [31:0] csr_rdata_i;

    output PCSrcE;
    output [31:0] PCTargetE;

    output RegWriteM;
    output MemWriteM;
    output [1:0] ResultSrcM;
    output [4:0] RD_M;
    output [31:0] PC_M;
    output [31:0] PCPlus4M;
    output [31:0] WriteDataM;
    output [31:0] ALU_ResultM;
    output [4:0] lsunitM;
    output valid_M;
    output exc_valid_M;
    output [5:0] exc_cause_M;
    output [31:0] exc_tval_M;
    output [31:0] exc_pc_M;

    output is_mret_M;

    //csr write back propagation to execute after Wb stage
    output csr_write_en_M;
    output [11:0] csr_addr_M;
    output [31:0] new_csr_M;
    output [31:0] old_csr_M;

    // Internal nets
    wire [31:0] Src_A;
    wire [31:0] Src_B_interim;
    wire [31:0] Src_B;
    wire [31:0] alu_r;
    wire ZeroE;
    wire [31:0] PCTarget_jb;
    wire yesE;
    wire JALRE;
    wire [31:0] LUI_result_E;
    wire [31:0] ResultE;
    wire [31:0] csr_new_val_E;
    wire csr_write_en_E;

    // M-extension internal nets
    wire [31:0] result_M;
    wire [4:0] rd_me;
    wire m_valid_out;
    wire stallM_internal;
    reg m_started;

    // Exception internal nets
    wire next_exc_valid_E;
    wire new_exc_valid_E;
    wire [5:0] next_exc_cause_E;
    wire [5:0] new_exc_cause_E;
    wire [31:0] next_exc_tval_E;
    wire [31:0] new_exc_tval_E;
    wire [31:0] next_exc_pc_E;
    wire [31:0] new_exc_pc_E;
    wire irq_accept_E;

    // Pipeline registers
    reg RegWriteE_r;
    reg MemWriteE_r;
    reg [1:0] ResultSrcE_r;
    reg [4:0] RD_E_r;
    reg [4:0] lsunitE_r;
    reg [31:0] PCE_r;
    reg [31:0] PCPlus4E_r;
    reg [31:0] RD2_E_r;
    reg [31:0] ResultE_r;
    reg csr_write_en_E_r;
    reg [11:0] csr_addr_E_r;
    reg [31:0] new_csr_E_r;
    reg [31:0] old_csr_E_r;
    reg valid_M_r;
    reg exc_valid_r;
    reg [5:0] exc_cause_r;
    reg [31:0] exc_tval_r;
    reg [31:0] exc_pc_r;
    reg is_mret_r;
    assign csr_raddr_o = csr_addr_E;

    Mux_3_by_1 srca_mux (
        .a(RD1_E),
        .b(ResultW),
        .c(ALU_ResultM),
        .s(ForwardA_E),
        .d(Src_A)
    );

    Mux_3_by_1 srcb_mux (
        .a(RD2_E),
        .b(ResultW),
        .c(ALU_ResultM),
        .s(ForwardB_E),
        .d(Src_B_interim)
    );

    Mux2 alu_src_mux (
        .a(Src_B_interim),
        .b(Imm_Ext_E),
        .s(ALUSrcE),
        .c(Src_B)
    );

    wire [2:0] flags_E;

    ALU alu_inst (
        .A(Src_A),
        .B(Src_B),
        .Result(alu_r),
        .ALUControl(ALUControlE),
        .flags(flags_E)
    );

    PC_Adder branch_adder (
        .a(PCE),
        .b(Imm_Ext_E),
        .c(PCTarget_jb)
    );

    JB_unit jb_unit (
        .flags(flags_E),
        .J(JumpE),
        .B(BranchE),
        .yes(yesE),
        .JALR(JALRE)
    );

    // Detect misaligned target BEFORE gating PCSrcE — on RV32I without C extension
    // all targets must be 4-byte aligned. A misaligned branch/jump must NOT redirect
    // the PC; instead it raises cause-0 (instruction-address-misaligned).
    wire branch_taken_raw = yesE & valid_E & ~exc_valid_E;
    wire [31:0] PCTarget_tentative = (JALRE) ? alu_r : PCTarget_jb;
    wire target_misaligned_E = (PCTarget_tentative[1:0] != 2'b00);

    assign PCTargetE = PCTarget_tentative;
    // PCSrcE suppressed when target is misaligned (exception takes over) or MEM is stalled
    assign PCSrcE = branch_taken_raw & ~target_misaligned_E & ~StallM;

    assign LUI_result_E = (LUISrcE) ? Imm_Ext_E : PCTarget_jb;



    // M-extension transaction tracker and module instantiation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_started <= 1'b0;
        end else if (m_valid_out) begin
            m_started <= 1'b0;
        end else if (is_M_instruction_E && !m_started) begin
            m_started <= 1'b1;
        end
    end
    wire start_M = is_M_instruction_E && !m_started;

    reg [31:0] pc_me;
    reg [31:0] pcplus4_me;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_me      <= 32'h00000000;
            pcplus4_me <= 32'h00000000;
        end else if (start_M) begin
            pc_me      <= PCE;
            pcplus4_me <= PCPlus4E;
        end
    end
    reg        m_hold;
    reg [31:0] m_hold_res;
    reg [4:0]  m_hold_rd;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_hold     <= 1'b0;
            m_hold_res <= 32'h00000000;
            m_hold_rd  <= 5'h00;
        end else if (FlushM) begin
            m_hold     <= 1'b0;
        end else if (m_valid_out && StallM) begin
            m_hold     <= 1'b1;
            m_hold_res <= result_M;
            m_hold_rd  <= rd_me;
        end else if (!StallM) begin
            m_hold     <= 1'b0;
        end
    end
    wire        m_out      = m_valid_out | m_hold;
    wire [31:0] m_res      = m_hold ? m_hold_res : result_M;
    wire [4:0]  m_rd       = m_hold ? m_hold_rd  : rd_me;
    assign ResultE = (m_out) ? m_res : ((isLUIE) ? LUI_result_E : alu_r);

    wire        valid_E1   = m_out ? 1'b1       : valid_E;
    wire [31:0] PCE1       = m_out ? pc_me      : PCE;
    wire [31:0] PCPlus4E1  = m_out ? pcplus4_me : PCPlus4E;

    rv32m_unit m_unit (
        .clk(clk),
        .rst_n(rst_n),
        .rs1(Src_A),
        .rs2(Src_B_interim),
        .funct3(op_E),
        .rd_in(RD_E),
        .valid_in(start_M),
        .stall(stallM_internal),
        .result(result_M),
        .rd_out(rd_me),
        .valid_out(m_valid_out)
    );

    assign stallMUL = stallM_internal;

    wire [4:0]  RD_E1        = (m_out) ? m_rd : RD_E;
    wire        RegWriteE1   = (is_M_instruction_E && !m_out) ? 1'b0 :
                               (m_out) ? 1'b1 : RegWriteE;

    wire [31:0] csr_op_val = csr_imm_mode_E ? {27'b0, csr_rs1_uimm_E} : Src_A;
    assign csr_new_val_E = (csr_op_E == 2'b01) ? csr_op_val :
                           (csr_op_E == 2'b10) ? (csr_rdata_i | csr_op_val) :
                           (csr_op_E == 2'b11) ? (csr_rdata_i & ~csr_op_val) :
                           csr_rdata_i;
    assign csr_write_en_E = csr_valid_E && (
                            (csr_op_E == 2'b01) || // CSRRW/CSRRWI always writes
                            ((csr_op_E == 2'b10 || csr_op_E == 2'b11) && (csr_rs1_uimm_E != 5'b0)) // CSRRS/CSRRC/CSRRSI/CSRRCI only writes if rs1/uimm != 0
                          );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            RegWriteE_r <= 1'b0;
            MemWriteE_r <= 1'b0;
            ResultSrcE_r <= 2'b00;
            RD_E_r <= 5'h00;
            lsunitE_r <= 5'h00;
            PCE_r <= 32'h00000000;
            PCPlus4E_r <= 32'h00000000;
            RD2_E_r <= 32'h00000000;
            ResultE_r <= 32'h00000000;
            csr_write_en_E_r <= 1'b0;
            csr_addr_E_r <= 12'h000;
            new_csr_E_r <= 32'h00000000;
            old_csr_E_r <= 32'h00000000;
            valid_M_r <= 1'b0;
            exc_valid_r <= 1'b0;
            exc_cause_r <= 6'd0;
            exc_tval_r <= 32'h00000000;
            exc_pc_r <= 32'h00000000;
            is_mret_r <= 1'b0;
        end else if (FlushM) begin
            RegWriteE_r <= 1'b0;
            MemWriteE_r <= 1'b0;
            ResultSrcE_r <= 2'b00;
            RD_E_r <= 5'h00;
            lsunitE_r <= 5'h00;
            PCE_r <= 32'h00000000;
            PCPlus4E_r <= 32'h00000000;
            RD2_E_r <= 32'h00000000;
            ResultE_r <= 32'h00000000;
            csr_write_en_E_r <= 1'b0;
            csr_addr_E_r <= 12'h000;
            new_csr_E_r <= 32'h00000000;
            old_csr_E_r <= 32'h00000000;
            valid_M_r <= 1'b0;
            exc_valid_r <= 1'b0;
            exc_cause_r <= 6'd0;
            exc_tval_r <= 32'h00000000;
            exc_pc_r <= 32'h00000000;
            is_mret_r <= 1'b0;
        end else if (StallM) begin
            RegWriteE_r <= RegWriteE_r;
            MemWriteE_r <= MemWriteE_r;
            ResultSrcE_r <= ResultSrcE_r;
            RD_E_r <= RD_E_r;
            lsunitE_r <= lsunitE_r;
            PCE_r <= PCE_r;
            PCPlus4E_r <= PCPlus4E_r;
            RD2_E_r <= RD2_E_r;
            ResultE_r <= ResultE_r;
            csr_write_en_E_r <= csr_write_en_E_r;
            csr_addr_E_r <= csr_addr_E_r;
            new_csr_E_r <= new_csr_E_r;
            old_csr_E_r <= old_csr_E_r;
            valid_M_r <= valid_M_r;
            exc_valid_r <= exc_valid_r;
            exc_cause_r <= exc_cause_r;
            exc_tval_r <= exc_tval_r;
            exc_pc_r <= exc_pc_r;
            is_mret_r <= is_mret_r;
        end else begin
            RegWriteE_r <= next_exc_valid_E ? 1'b0 : RegWriteE1;
            MemWriteE_r <= next_exc_valid_E ? 1'b0 : MemWriteE;
            ResultSrcE_r <= ResultSrcE;
            RD_E_r <= RD_E1;
            lsunitE_r <= lsunitE;
            PCE_r <= PCE1;
            PCPlus4E_r <= PCPlus4E1;
            RD2_E_r <= Src_B_interim;
            ResultE_r <= ResultE;
            csr_write_en_E_r <= next_exc_valid_E ? 1'b0 : csr_write_en_E;
            csr_addr_E_r <= csr_addr_E;
            new_csr_E_r <= csr_new_val_E;
            old_csr_E_r <= csr_rdata_i;
            valid_M_r <= valid_E1;
            exc_valid_r <= next_exc_valid_E;
            exc_cause_r <= next_exc_cause_E;
            exc_tval_r <= next_exc_tval_E;
            exc_pc_r <= next_exc_pc_E;
            is_mret_r <= is_mret_E;
        end
    end

    assign RegWriteM = RegWriteE_r;
    assign MemWriteM = MemWriteE_r;
    assign ResultSrcM = ResultSrcE_r;
    assign RD_M = RD_E_r;
    assign PC_M = PCE_r;
    assign PCPlus4M = PCPlus4E_r;
    assign WriteDataM = RD2_E_r;
    assign ALU_ResultM = ResultE_r;
    assign lsunitM = lsunitE_r;
    assign valid_M = valid_M_r;
    assign exc_valid_M = exc_valid_r;
    assign exc_cause_M = exc_cause_r;
    assign exc_tval_M = exc_tval_r;
    assign exc_pc_M = exc_pc_r;

    assign is_mret_M = is_mret_r;

    assign csr_write_en_M = csr_write_en_E_r;
    assign csr_addr_M = csr_addr_E_r;
    assign new_csr_M = new_csr_E_r;
    assign old_csr_M = old_csr_E_r;


    // IRQ acceptance: accept IRQ only on a valid, un-excepted instruction when not stalled by multi-cycle M-unit
    assign irq_accept_E = valid_E & irq_pending_i & ~new_exc_valid_E & ~exc_valid_E & ~stallMUL;
    assign irq_flush_frontend_o = irq_accept_E;

    // Three-way priority chain:
    // 1. Local exception in EX (misaligned branch/jump target)
    // 2. Synchronous exception from ID/IF (illegal instruction, fetch fault)
    // 3. Accepted IRQ (converts instruction in EX to an interrupt trap packet)
    assign next_exc_valid_E = new_exc_valid_E | exc_valid_E | irq_accept_E;
    assign next_exc_cause_E = new_exc_valid_E ? new_exc_cause_E :
                              exc_valid_E     ? exc_cause_E :
                              irq_accept_E    ? {1'b1, irq_id_i[4:0]} :
                                                6'd0;
    assign next_exc_tval_E  = new_exc_valid_E ? new_exc_tval_E :
                              exc_valid_E     ? exc_tval_E :
                              irq_accept_E    ? 32'h0 :
                                                32'h0;
    assign next_exc_pc_E    = new_exc_valid_E ? new_exc_pc_E :
                              exc_valid_E     ? exc_pc_E :
                              irq_accept_E    ? PCE :
                                                PCE;

    assign new_exc_valid_E = branch_taken_raw & target_misaligned_E;
    assign new_exc_cause_E = 6'b000000;  // cause 0: instruction-address-misaligned (bit[5]=0 exception)
    assign new_exc_tval_E  = PCTargetE;
    assign new_exc_pc_E    = PCE;

endmodule
