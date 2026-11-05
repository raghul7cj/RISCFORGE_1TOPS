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

module top #(
    // First instruction address fetched out of reset. The RISCFORGE SoC boots
    // from the BootROM, so it overrides this to 32'h0000_0000.
    parameter [31:0] RESET_PC = 32'h80000000,
    parameter [31:0] FETCH_BASE0 = 32'h00000000,
    parameter [31:0] FETCH_END0  = 32'hFFFFFFFF,
    parameter [31:0] FETCH_BASE1 = 32'h00000000,
    parameter [31:0] FETCH_END1  = 32'h00000000
)(

    input clk,
    input rst,

    // Debug output
    output PCSrcE1,

    // ==================================================
    // Instruction Memory (SRAM) Interface
    // ==================================================
    output        imem_sram_en,
    output        imem_sram_we,
    output [3:0]  imem_sram_wmask,
    output [29:0] imem_sram_addr,
    output [31:0] imem_sram_wdata,
    input  [31:0] imem_sram_rdata,

    // ==================================================
    // LSU Data Memory Interface
    // ==================================================
    output        lsu_mem_req,
    output        lsu_mem_we,
    output [31:0] lsu_mem_addr,
    output [31:0] lsu_mem_wdata,
    output [3:0]  lsu_mem_be,
    input  [31:0] lsu_mem_rdata,
    input         lsu_mem_stall,
    input         lsu_mem_err,

    // ==================================================
    // Interrupt Inputs (from SoC peripherals & CLINT)
    // ==================================================
    input  [15:0] fast_irq_i,  // Fast local interrupts for mip[31:16] (FLI: UART=3, SPI=2, I2C=1, GPIO=0)
    input         timer_irq_i, // Timer interrupt for mip[7] (MTIP)
    input         ext_irq_i,   // Platform external interrupt for mip[11] (MEIP)
    input         sw_irq_i     // Software interrupt for mip[3] (MSIP)
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
    wire [31:0] PC_M;
    wire [31:0] PCPlus4E;
    wire [31:0] PCPlus4M;
    wire [31:0] WriteDataM;
    wire [31:0] ALU_ResultM;

    wire [31:0] PC_W;
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

    // CSR control signals (ID -> EX)
    wire csr_valid_E;
    wire csr_imm_mode_E;
    wire [1:0] csr_op_E;
    wire [11:0] csr_raddr_E;
    wire [4:0] rd_index_E;

    // CSR file sideband (EX -> external CSR file)
    wire [11:0] csr_raddr;
    wire [31:0] csr_rdata;

    // CSR decode stage signals for hazard detection
    wire csr_valid_D;
    wire [11:0] csr_raddr_D;
    wire is_mret_E;

    wire pipe_busy;

    // CSR Port B write signals (from Execute stage EX/MEM register)
    wire csr_write_en_M;
    wire [11:0] csr_addr_M;
    wire [31:0] new_csr_M;
    wire [31:0] old_csr_M;  // ✅ OLD_CSR read value from EX/MEM register

    // CSR Port B write signals (after MEM/WB pipeline register)
    wire csr_write_en_W;
    wire [11:0] csr_addr_W;
    wire [31:0] new_csr_W;
    wire [31:0] old_csr_W;  // ✅ OLD_CSR read value from MEM/WB register

    wire StallF;
    wire StallD;
    wire StallE;
    wire StallM;
    wire FlushE;
    wire FlushD;
    wire [3:0] flush_pipeline_onehot;
    wire FlushM;
    wire FlushW;

    wire valid_D;
    wire valid_E;
    wire valid_M;
    wire valid_W;

    wire exc_valid_D;
    wire [5:0] exc_cause_D;
    wire [31:0] exc_tval_D;
    wire [31:0] exc_pc_D;

    wire exc_valid_E;
    wire [5:0] exc_cause_E;
    wire [31:0] exc_tval_E;
    wire [31:0] exc_pc_E;

    wire exc_valid_M;
    wire [5:0] exc_cause_M;
    wire [31:0] exc_tval_M;
    wire [31:0] exc_pc_M;

    wire exc_valid_W;
    wire [5:0] exc_cause_W;
    wire [31:0] exc_tval_W;
    wire [31:0] exc_pc_W;

    wire is_mret_M;
    wire is_mret_W;

    wire wb_trap_redirect;
    wire [31:0] trap_target;

    wire [31:0] csr_mtvec_sb;
    wire [31:0] csr_mepc_sb;
    wire [31:0] csr_mstatus_sb;  // ✅ MRET: expose mstatus for wb_trap_mret_commit_controller
    wire [31:0] csr_mie_sb;
    wire [31:0] csr_mip_sb;
    wire        csr_mstatus_mie_sb;

    // =========================================================================
    // IRQ Qualification & 16-wide Priority Encoder
    // =========================================================================
    // Computes active interrupts: active_irqs = mip & mie
    // Global Machine Interrupt Enable: mstatus.MIE
    wire [31:0] active_irqs;
    wire        irq_valid;
    wire        irq_pending;
    wire [30:0] irq_id;

    assign active_irqs = csr_mip_sb & csr_mie_sb;
    assign irq_valid   = |active_irqs;
    assign irq_pending = csr_mstatus_mie_sb & irq_valid;

    // Priority Hierarchy (16-wide Fast Local Interrupts + standard interrupts):
    // mcause ID  Natural Priority Rank
    // Bit 19:    UART                  (mcause 19, Rank 1 - Highest Peripheral)
    // Bit 18:    SPI                   (mcause 18, Rank 2)
    // Bit 17:    I2C                   (mcause 17, Rank 3)
    // Bit 16:    GPIO                  (mcause 16, Rank 4 - Lowest Peripheral)
    // Bit 11:    MEIP (Platform Ext)   (mcause 11)
    // Bit 7:     MTIP (CLINT Timer)    (mcause 7,  Rank 5)
    // Bit 3:     MSIP (CLINT Software) (mcause 3,  Rank 6 - Lowest Overall)
    // NOTE: For future extension, custom local interrupts in bits [31:20] can be
    // prioritized here once additional SoC peripherals are finalized.
    reg [4:0] irq_cause_enc;
    always @(*) begin
        // Reserved/Future expansion for FLI bits [31:20]:
        if      (active_irqs[31]) irq_cause_enc = 5'd31;
        else if (active_irqs[30]) irq_cause_enc = 5'd30;
        else if (active_irqs[29]) irq_cause_enc = 5'd29;
        else if (active_irqs[28]) irq_cause_enc = 5'd28;
        else if (active_irqs[27]) irq_cause_enc = 5'd27;
        else if (active_irqs[26]) irq_cause_enc = 5'd26;
        else if (active_irqs[25]) irq_cause_enc = 5'd25;
        else if (active_irqs[24]) irq_cause_enc = 5'd24;
        else if (active_irqs[23]) irq_cause_enc = 5'd23;
        else if (active_irqs[22]) irq_cause_enc = 5'd22;
        else if (active_irqs[21]) irq_cause_enc = 5'd21;
        else if (active_irqs[20]) irq_cause_enc = 5'd20;
        // Current SoC peripherals (UART > SPI > I2C > GPIO):
        else if (active_irqs[19]) irq_cause_enc = 5'd19; // Rank 1: UART
        else if (active_irqs[18]) irq_cause_enc = 5'd18; // Rank 2: SPI
        else if (active_irqs[17]) irq_cause_enc = 5'd17; // Rank 3: I2C
        else if (active_irqs[16]) irq_cause_enc = 5'd16; // Rank 4: GPIO
        // Standard Machine-mode interrupts:
        else if (active_irqs[11]) irq_cause_enc = 5'd11; // MEIP (Platform External)
        else if (active_irqs[7])  irq_cause_enc = 5'd7;  // Rank 5: MTIP (CLINT Timer)
        else if (active_irqs[3])  irq_cause_enc = 5'd3;  // Rank 6: MSIP (CLINT Software)
        else                      irq_cause_enc = 5'd0;
    end

    assign irq_id = {26'b0, irq_cause_enc};

    wire irq_flush_frontend;

    wire trap_commit_valid;
    wire [30:0] trap_commit_cause;
    wire [31:0] trap_commit_pc;
    wire [31:0] trap_commit_addr;
    wire trap_commit_addr_valid;
    wire trap_commit_is_interrupt;

    reg  [15:0] fast_irq_q;
    reg         timer_irq_q;
    wire        irq_taken = trap_commit_valid & trap_commit_is_interrupt;
    wire [15:0] fast_irq_take;
    genvar      gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : g_fast_take
            assign fast_irq_take[gi] = irq_taken & (trap_commit_cause == (16 + gi));
        end
    endgenerate
    wire        timer_irq_take = irq_taken & (trap_commit_cause == 7);
    reg  [15:0] fast_irq_prev;
    reg         timer_irq_prev;
    wire [15:0] fast_irq_edge  = fast_irq_i & ~fast_irq_prev & csr_mie_sb[31:16];
    wire        timer_irq_edge = timer_irq_i & ~timer_irq_prev & csr_mie_sb[7];
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            fast_irq_q     <= 16'h0000;
            timer_irq_q    <= 1'b0;
            fast_irq_prev  <= 16'h0000;
            timer_irq_prev <= 1'b0;
        end else begin
            fast_irq_prev  <= fast_irq_i;
            timer_irq_prev <= timer_irq_i;
            fast_irq_q     <= (fast_irq_q | fast_irq_edge) & ~fast_irq_take & csr_mie_sb[31:16];
            timer_irq_q    <= (timer_irq_q | timer_irq_edge) & ~timer_irq_take & csr_mie_sb[7];
        end
    end
    wire [15:0] fast_irq_pend  = fast_irq_q | fast_irq_i;
    wire        timer_irq_pend = timer_irq_q | timer_irq_i;
    wire mret_commit;

    // ✅ PORT C: MRET write signals (from wb_trap_mret_commit_controller)
    wire csr_write_en_mret;
    wire [11:0] csr_waddr_mret;
    wire [31:0] csr_wdata_mret;

    wire is_M_instruction_E;
    wire [2:0] op_E;
    wire stallMUL;        // M-extension (multiply/divide) multi-cycle stall
    wire mem_stall_out;   // LSU / memory-bridge stall (AXI multi-cycle, SRAM wait-state)

    wire RegWriteW_gated;
    wire csr_write_en_W_gated;

    wire LUISrcE;
    wire isLUIE;
    wire illegal_instr;  // ✅ Explicit wire declaration

    // CSR decode-side set signal (in ID stage)
    assign csr_valid_D = (InstrD[6:0] == 7'b1110011);
    assign csr_raddr_D = InstrD[31:20];

    // Detect instructions ahead of the Decode stage
    assign pipe_busy =  RegWriteE | MemWriteE | // Indicators for EX
                        RegWriteM | MemWriteM | // Indicators for MEM
                        RegWriteW;              // Indicator for WB

    // Gate architectural retirement side-effects
    assign RegWriteW_gated = RegWriteW & valid_W & ~exc_valid_W & ~mret_commit;
    assign csr_write_en_W_gated = csr_write_en_W & valid_W & ~exc_valid_W & ~mret_commit;

    assign PCSrcE1 = PCSrcE;

    // ==================================================
    // Stage Instantiations
    // ==================================================

    // ---------------- IF ----------------
    fetch_cycle #(
        .RESET_PC(RESET_PC),
        .FETCH_BASE0(FETCH_BASE0),
        .FETCH_END0(FETCH_END0),
        .FETCH_BASE1(FETCH_BASE1),
        .FETCH_END1(FETCH_END1)
    ) Fetch (
        .clk(clk),
        .rst(rst),
        .PCSrcE(PCSrcE),
        .wb_trap_redirect(wb_trap_redirect),
        .PCTargetE(PCTargetE),
        .trap_target(trap_target),
        .InstrD(InstrD),
        .PCD(PCD),
        .PCPlus4D(PCPlus4D),
        .StallF(StallF),
        .StallD(StallD),
        .FlushD(FlushD | irq_flush_frontend),
        .valid_D(valid_D),
        .exc_valid_D(exc_valid_D),
        .exc_cause_D(exc_cause_D),
        .exc_tval_D(exc_tval_D),
        .exc_pc_D(exc_pc_D),
        .imem_stall(),
        .imem_sram_en(imem_sram_en),
        .imem_sram_we(imem_sram_we),
        .imem_sram_wmask(imem_sram_wmask),
        .imem_sram_addr(imem_sram_addr),
        .imem_sram_wdata(imem_sram_wdata),
        .imem_sram_rdata(imem_sram_rdata)
    );

    // ---------------- ID ----------------
    decode_cycle Decode (
        .clk(clk),
        .rst(rst),
        .InstrD(InstrD),
        .PCD(PCD),
        .PCPlus4D(PCPlus4D),
        .valid_D(valid_D),
        .exc_valid_D(exc_valid_D),
        .exc_cause_D(exc_cause_D),
        .exc_tval_D(exc_tval_D),
        .exc_pc_D(exc_pc_D),
        .RegWriteW(RegWriteW_gated),
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
        .StallE(StallE),
        .LUISrcE(LUISrcE),
        .isLUIE(isLUIE),
        .illegal_instr(illegal_instr),
        .csr_valid_E(csr_valid_E),
        .csr_imm_mode_E(csr_imm_mode_E),
        .csr_op_E(csr_op_E),
        .csr_raddr_E(csr_raddr_E),
        .rd_index_E(rd_index_E),
        .is_mret_E(is_mret_E),
        .valid_E(valid_E),
        .exc_valid_E(exc_valid_E),
        .exc_cause_E(exc_cause_E),
        .exc_tval_E(exc_tval_E),
        .exc_pc_E(exc_pc_E),
        .is_M_instruction_E(is_M_instruction_E),
        .op_E(op_E)
    );

    // ---------------- EX ----------------
    execute_cycle Execute (
        .clk(clk),
        .rst_n(rst),
        .FlushM(FlushM),
        .FlushE(FlushE),
        .StallM(StallM),
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
        .valid_E(valid_E),
        .exc_valid_E(exc_valid_E),
        .exc_cause_E(exc_cause_E),
        .exc_tval_E(exc_tval_E),
        .exc_pc_E(exc_pc_E),
        .is_mret_E(is_mret_E),
        .irq_pending_i(irq_pending),
        .irq_id_i(irq_id),
        .irq_flush_frontend_o(irq_flush_frontend),
        .PCSrcE(PCSrcE),
        .PCTargetE(PCTargetE),
        .RegWriteM(RegWriteM),
        .MemWriteM(MemWriteM),
        .ResultSrcM(ResultSrcM),
        .RD_M(RD_M),
        .PC_M(PC_M),
        .PCPlus4M(PCPlus4M),
        .WriteDataM(WriteDataM),
        .ALU_ResultM(ALU_ResultM),
        .ResultW(ResultW),
        .ForwardA_E(ForwardAE),
        .ForwardB_E(ForwardBE),
        .lsunitE(lsunitE),
        .JumpE(JumpE),
        .lsunitM(lsunitM),
        .valid_M(valid_M),
        .exc_valid_M(exc_valid_M),
        .exc_cause_M(exc_cause_M),
        .exc_tval_M(exc_tval_M),
        .exc_pc_M(exc_pc_M),
        .is_mret_M(is_mret_M),
        .LUISrcE(LUISrcE),
        .isLUIE(isLUIE),
        .csr_valid_E(csr_valid_E),
        .csr_imm_mode_E(csr_imm_mode_E),
        .csr_op_E(csr_op_E),
        .csr_rs1_uimm_E(RS1_E[4:0]),
        .csr_addr_E(csr_raddr_E),
        .csr_raddr_o(csr_raddr),
        .csr_rdata_i(csr_rdata),
        .csr_write_en_M(csr_write_en_M),
        .csr_addr_M(csr_addr_M),
        .new_csr_M(new_csr_M),
        .old_csr_M(old_csr_M),
        .is_M_instruction_E(is_M_instruction_E),
        .op_E(op_E),
        .stallMUL(stallMUL)
    );

    // ---------------- MEM ----------------
    memory_cycle Memory (
        .clk(clk),
        .rst(rst),
        .FlushW(FlushW),
        .RegWriteM(RegWriteM),
        .MemWriteM(MemWriteM),
        .ResultSrcM(ResultSrcM),
        .RD_M(RD_M),
        .lsunitM(lsunitM),
        .PC_M(PC_M),
        .PCPlus4M(PCPlus4M),
        .valid_M(valid_M),
        .exc_valid_M(exc_valid_M),
        .exc_cause_M(exc_cause_M),
        .exc_tval_M(exc_tval_M),
        .exc_pc_M(exc_pc_M),
        .is_mret_M(is_mret_M),
        .WriteDataM(WriteDataM),
        .ALU_ResultM(ALU_ResultM),
        .csr_write_en_M(csr_write_en_M),
        .csr_addr_M(csr_addr_M),
        .new_csr_M(new_csr_M),
        .old_csr_M(old_csr_M),
        // LSU stall — routed to hazard unit to freeze IF/ID/EX and MEM→WB register
        .mem_stall_out(mem_stall_out),
        // LSU Memory Interface
        .lsu_mem_req(lsu_mem_req),
        .lsu_mem_we(lsu_mem_we),
        .lsu_mem_addr(lsu_mem_addr),
        .lsu_mem_wdata(lsu_mem_wdata),
        .lsu_mem_be(lsu_mem_be),
        .lsu_mem_rdata(lsu_mem_rdata),
        .lsu_mem_stall(lsu_mem_stall),
        .lsu_mem_err(lsu_mem_err),
        // WB outputs
        .RegWriteW(RegWriteW),
        .ResultSrcW(ResultSrcW),
        .RD_W(RDW),
        .PC_W(PC_W),
        .PCPlus4W(PCPlus4W),
        .ALU_ResultW(ALU_ResultW),
        .ReadDataW(ReadDataW),
        .valid_W(valid_W),
        .exc_valid_W(exc_valid_W),
        .exc_cause_W(exc_cause_W),
        .exc_tval_W(exc_tval_W),
        .exc_pc_W(exc_pc_W),
        .is_mret_W(is_mret_W),
        .csr_write_en_W(csr_write_en_W),
        .csr_addr_W(csr_addr_W),
        .new_csr_W(new_csr_W),
        .old_csr_W(old_csr_W)
    );

    // ---------------- WB ----------------
    writeback_cycle WriteBack (
        .ResultSrcW(ResultSrcW),
        .PCPlus4W(PCPlus4W),
        .ALU_ResultW(ALU_ResultW),
        .ReadDataW(ReadDataW),
        .old_csr_W(old_csr_W),
        .ResultW(ResultW)
    );

    // ====================================
    // WB Trap + MRET Commit Controller
    // ====================================
    wb_trap_mret_commit_controller wb_commit (
        .valid_W(valid_W),
        .exc_valid_W(exc_valid_W),
        .exc_cause_W(exc_cause_W),
        .exc_tval_W(exc_tval_W),
        .exc_pc_W(exc_pc_W),
        .is_mret_W(is_mret_W),
        
        .mtvec_i(csr_mtvec_sb),
        .mepc_i(csr_mepc_sb),
        .mstatus_i(csr_mstatus_sb),
        .wb_trap_redirect_o(wb_trap_redirect),
        .trap_target_o(trap_target),
        .flush_pipeline_onehot_o(flush_pipeline_onehot),
        .trap_valid_o(trap_commit_valid),
        .trap_cause_o(trap_commit_cause),
        .trap_pc_o(trap_commit_pc),
        .trap_addr_o(trap_commit_addr),
        .trap_addr_valid_o(trap_commit_addr_valid),
        .trap_is_interrupt_o(trap_commit_is_interrupt),
        .csr_write_en_mret_o(csr_write_en_mret),
        .csr_waddr_mret_o(csr_waddr_mret),
        .csr_wdata_mret_o(csr_wdata_mret),
        .mret_commit_o(mret_commit)
    );

    // ====================================
    // CSR Regfile (Performance Counters + Interrupts)
    // ====================================
    csr_regfile #(.XLEN(32)) csr_file (
        .clk_i(clk),
        .rst_n_i(rst),
        .csr_raddr_i(csr_raddr),
        .csr_rdata_o(csr_rdata),
        .csr_waddr_normal_i(csr_addr_W),
        .csr_wdata_normal_i(new_csr_W),
        .csr_write_en_normal_i(csr_write_en_W_gated),
        .csr_waddr_mret_i(csr_waddr_mret),
        .csr_wdata_mret_i(csr_wdata_mret),
        .csr_write_en_mret_i(csr_write_en_mret),
        .trap_valid_i(trap_commit_valid),
        .trap_cause_i(trap_commit_cause),
        .trap_pc_i(trap_commit_pc),
        .trap_addr_i(trap_commit_addr),
        .trap_addr_valid_i(trap_commit_addr_valid),
        .trap_is_interrupt_i(trap_commit_is_interrupt),
        
        .instr_retired_i(valid_W & ~exc_valid_W), // Increment minstret on retirement
        
        .timer_intr_i(timer_irq_pend),
        .ext_intr_i(ext_irq_i),
        .msft_intr_i(sw_irq_i),
        .fast_intr_i(fast_irq_pend),
        .mtvec_out_o(csr_mtvec_sb),
        .mie_out_o(csr_mie_sb),
        .mip_out_o(csr_mip_sb),
        .mstatus_mie_out_o(csr_mstatus_mie_sb),
        .mepc_out_o(csr_mepc_sb),
        .mstatus_out_o(csr_mstatus_sb)
    );

    // ---------------- Hazard ----------------
    hazard_unit Forwarding_block (
        .rst(rst),
        .RegWriteM(RegWriteM),
        .RegWriteW(RegWriteW_gated),
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
        .StallE(StallE),
        .StallM(StallM),
        .FlushE(FlushE),
        .FlushD(FlushD),
        .FlushM(FlushM),
        .FlushW(FlushW),
        .illegal_instr(illegal_instr),
        .csr_valid_D(csr_valid_D),
        .csr_raddr_D(csr_raddr_D),
        .csr_raddr_E(csr_raddr_E),
        .csr_raddr_W(csr_addr_W),
        .csr_addr_E(csr_raddr_E),
        .csr_addr_M(csr_addr_M),
        .csr_addr_W(csr_addr_W),
        .csr_write_en_W(csr_write_en_W_gated),
        .csr_write_en_M(csr_write_en_M),
        .csr_write_en_E(csr_valid_E),
        .flush_pipeline_onehot(flush_pipeline_onehot),
        .valid_E(valid_E),
        .exc_valid_E(exc_valid_E),
        .valid_M(valid_M),
        .exc_valid_M(exc_valid_M),
        .wb_redirect(wb_trap_redirect),
        .stallMUL(stallMUL),
        .mem_stall_i(mem_stall_out)
    );

endmodule
