// ==============================================================================
// File: core_trap_observe.sv
// Project: RISCFORGE 1TOPS RISC-V Core Verification
// Module: core_trap_observe
// Description:
//   The sole owner of read-only hierarchical observation paths into top.
//   Read-only taps into top. This adapter owns all DUT hierarchy references.
//   No observed DUT value feeds an expected value.
// ==============================================================================

module core_trap_observe (
  input  logic        clk,
  output logic        valid_d,
  output logic [31:0] pc_d,
  output logic [31:0] instr_d,
  output logic        rf_we,
  output logic [4:0]  rf_rd,
  output logic [31:0] rf_wdata,
  output logic [31:0] pc_w,
  output logic        valid_w,
  output logic        retired_w,
  output logic        stall_d,
  output logic        flush_d,
  core_pipeline_if    pipeline
);

  bit inject_hold_failure  = 0;
  bit inject_flush_failure = 0;


  // ============================================================================
  // Direct Read-Only Implementation Observations
  // ============================================================================
  assign stall_d   = tb_core_trap_lean.dut.StallD | tb_core_trap_lean.dut.Fetch.imem_stall_raw;
  assign flush_d   = tb_core_trap_lean.dut.FlushD | tb_core_trap_lean.dut.irq_flush_frontend;

  // These are taps only; no observed DUT value feeds an expected value.
  assign valid_d   = tb_core_trap_lean.dut.valid_D;
  assign pc_d      = tb_core_trap_lean.dut.PCD;
  assign instr_d   = tb_core_trap_lean.dut.InstrD;
  assign rf_we     = tb_core_trap_lean.dut.RegWriteW_gated;
  assign rf_rd     = tb_core_trap_lean.dut.RDW;
  assign rf_wdata  = tb_core_trap_lean.dut.ResultW;
  assign pc_w      = tb_core_trap_lean.dut.PC_W;
  assign valid_w   = tb_core_trap_lean.dut.valid_W;
  assign retired_w = tb_core_trap_lean.dut.instr_retired_W;


  // ============================================================================
  // Common Observation Interface: Registered State & Pipeline Stage Control
  // ============================================================================
  // D/E/M/W bundle widths are padded to the interface width. Combinational
  // forwarded operands are deliberately excluded from stage hold checks.
  assign pipeline.valid = {
    tb_core_trap_lean.dut.valid_W,
    tb_core_trap_lean.dut.valid_M,
    tb_core_trap_lean.dut.valid_E,
    tb_core_trap_lean.dut.valid_D | inject_flush_failure
  };

  assign pipeline.hold_stage = {
    tb_core_trap_lean.dut.mem_stall_out,
    tb_core_trap_lean.dut.StallM,
    tb_core_trap_lean.dut.StallE,
    stall_d
  };

  assign pipeline.flush_stage = {
    tb_core_trap_lean.dut.FlushW,
    tb_core_trap_lean.dut.FlushM,
    tb_core_trap_lean.dut.FlushE | tb_core_trap_lean.dut.irq_flush_frontend,
    flush_d
  };


  // ============================================================================
  // Pipeline Stage Payloads (Registered Instruction & Execution State)
  // ============================================================================
  assign pipeline.payload[0] = {
    tb_core_trap_lean.dut.PCD,
    tb_core_trap_lean.dut.InstrD,
    tb_core_trap_lean.dut.PCPlus4D,
    tb_core_trap_lean.dut.exc_valid_D,
    tb_core_trap_lean.dut.exc_cause_D,
    tb_core_trap_lean.dut.exc_pc_D,
    tb_core_trap_lean.dut.exc_tval_D
  };

  assign pipeline.payload[1] = {
    tb_core_trap_lean.dut.PCE,
    tb_core_trap_lean.dut.PCPlus4E,
    tb_core_trap_lean.dut.RD1_E,
    tb_core_trap_lean.dut.RD2_E,
    tb_core_trap_lean.dut.Imm_Ext_E,
    tb_core_trap_lean.dut.RD_E,
    tb_core_trap_lean.dut.RS1_E,
    tb_core_trap_lean.dut.RS2_E,
    tb_core_trap_lean.dut.RegWriteE,
    tb_core_trap_lean.dut.MemWriteE,
    tb_core_trap_lean.dut.ResultSrcE,
    tb_core_trap_lean.dut.lsunitE,
    tb_core_trap_lean.dut.JumpE,
    tb_core_trap_lean.dut.BranchE,
    tb_core_trap_lean.dut.ALUSrcE,
    tb_core_trap_lean.dut.ALUControlE,
    tb_core_trap_lean.dut.csr_valid_E,
    tb_core_trap_lean.dut.csr_raddr_E,
    tb_core_trap_lean.dut.csr_op_E,
    tb_core_trap_lean.dut.csr_imm_mode_E,
    tb_core_trap_lean.dut.is_mret_E,
    tb_core_trap_lean.dut.is_M_instruction_E,
    tb_core_trap_lean.dut.op_E,
    tb_core_trap_lean.dut.LUISrcE,
    tb_core_trap_lean.dut.isLUIE,
    tb_core_trap_lean.dut.exc_valid_E,
    tb_core_trap_lean.dut.exc_cause_E,
    tb_core_trap_lean.dut.exc_pc_E,
    tb_core_trap_lean.dut.exc_tval_E
  };

  assign pipeline.payload[2] = {
    tb_core_trap_lean.dut.PC_M,
    tb_core_trap_lean.dut.PCPlus4M,
    tb_core_trap_lean.dut.ALU_ResultM,
    tb_core_trap_lean.dut.WriteDataM,
    tb_core_trap_lean.dut.RD_M,
    tb_core_trap_lean.dut.RegWriteM,
    tb_core_trap_lean.dut.MemWriteM,
    tb_core_trap_lean.dut.ResultSrcM,
    tb_core_trap_lean.dut.lsunitM,
    tb_core_trap_lean.dut.csr_write_en_M,
    tb_core_trap_lean.dut.csr_addr_M,
    tb_core_trap_lean.dut.new_csr_M,
    tb_core_trap_lean.dut.old_csr_M,
    tb_core_trap_lean.dut.is_mret_M,
    tb_core_trap_lean.dut.exc_valid_M,
    tb_core_trap_lean.dut.exc_cause_M,
    tb_core_trap_lean.dut.exc_class_M,
    tb_core_trap_lean.dut.exc_pc_M,
    tb_core_trap_lean.dut.exc_tval_M
  } ^ inject_hold_failure;

  assign pipeline.payload[3] = {
    tb_core_trap_lean.dut.PC_W,
    tb_core_trap_lean.dut.PCPlus4W,
    tb_core_trap_lean.dut.ALU_ResultW,
    tb_core_trap_lean.dut.ReadDataW,
    tb_core_trap_lean.dut.RDW,
    tb_core_trap_lean.dut.RegWriteW,
    tb_core_trap_lean.dut.ResultSrcW,
    tb_core_trap_lean.dut.csr_write_en_W,
    tb_core_trap_lean.dut.csr_addr_W,
    tb_core_trap_lean.dut.new_csr_W,
    tb_core_trap_lean.dut.old_csr_W,
    tb_core_trap_lean.dut.is_mret_W,
    tb_core_trap_lean.dut.exc_valid_W,
    tb_core_trap_lean.dut.exc_cause_W,
    tb_core_trap_lean.dut.exc_class_W,
    tb_core_trap_lean.dut.exc_pc_W,
    tb_core_trap_lean.dut.exc_tval_W
  };


  // ============================================================================
  // Fetch & Branch / Memory Protocol Signals
  // ============================================================================
  assign pipeline.fetch_pc        = tb_core_trap_lean.dut.Fetch.PCF;
  assign pipeline.fetch_hold      = tb_core_trap_lean.dut.StallF | tb_core_trap_lean.dut.Fetch.imem_stall_raw;
  assign pipeline.branch_redirect = tb_core_trap_lean.dut.PCSrcE;
  assign pipeline.branch_target   = tb_core_trap_lean.dut.PCTargetE;
  assign pipeline.wb_redirect     = tb_core_trap_lean.dut.wb_trap_redirect;
  assign pipeline.wb_target       = tb_core_trap_lean.dut.trap_target;
  assign pipeline.mem_req         = tb_core_trap_lean.dut.lsu_mem_req;
  assign pipeline.mem_we          = tb_core_trap_lean.dut.lsu_mem_we;
  assign pipeline.mem_pc          = tb_core_trap_lean.dut.PC_M;
  assign pipeline.mem_address     = tb_core_trap_lean.dut.lsu_mem_addr;
  assign pipeline.mem_wdata       = tb_core_trap_lean.dut.lsu_mem_wdata;
  assign pipeline.mem_be          = tb_core_trap_lean.dut.lsu_mem_be;
  assign pipeline.mem_stall       = tb_core_trap_lean.dut.lsu_mem_stall;
  assign pipeline.mem_error       = tb_core_trap_lean.dut.lsu_mem_err;

  assign pipeline.exception_valid = {
    tb_core_trap_lean.dut.exc_valid_W,
    tb_core_trap_lean.dut.exc_valid_M,
    tb_core_trap_lean.dut.exc_valid_E,
    tb_core_trap_lean.dut.exc_valid_D
  };

  assign pipeline.rf_write        = rf_we;
  assign pipeline.csr_write       = tb_core_trap_lean.dut.csr_write_en_W_gated;
  assign pipeline.retire          = retired_w;
  assign pipeline.mret_commit     = tb_core_trap_lean.dut.mret_commit;


  // ============================================================================
  // Trap Commit & CSR Observability Interface
  // ============================================================================
  assign pipeline.trap_valid       = tb_core_trap_lean.dut.trap_commit_valid;
  assign pipeline.trap_interrupt   = tb_core_trap_lean.dut.trap_commit_is_interrupt;
  assign pipeline.trap_cause       = tb_core_trap_lean.dut.trap_commit_cause;
  assign pipeline.trap_pc          = tb_core_trap_lean.dut.trap_commit_pc;
  assign pipeline.trap_tval        = tb_core_trap_lean.dut.trap_commit_addr;
  assign pipeline.trap_tval_valid  = tb_core_trap_lean.dut.trap_commit_addr_valid;

  assign pipeline.csr_mtval        = tb_core_trap_lean.dut.csr_file.mtval_r;
  assign pipeline.csr_mepc         = tb_core_trap_lean.dut.csr_mepc_sb;
  assign pipeline.csr_mcause       = tb_core_trap_lean.dut.csr_file.mcause_out_o;
  assign pipeline.csr_mtvec        = tb_core_trap_lean.dut.csr_mtvec_sb;
  assign pipeline.csr_mstatus      = tb_core_trap_lean.dut.csr_mstatus_sb;
  assign pipeline.csr_mie          = tb_core_trap_lean.dut.csr_mie_sb;
  assign pipeline.csr_mip          = tb_core_trap_lean.dut.csr_mip_sb;

  assign pipeline.irq_accept       = tb_core_trap_lean.dut.Execute.irq_accept_E;
  assign pipeline.irq_pending      = tb_core_trap_lean.dut.irq_pending;
  assign pipeline.irq_winner       = tb_core_trap_lean.dut.irq_winner_id;


  // ============================================================================
  // Opt-in SVA Self-Tests: Mutate Monitor Copies, Never DUT State
  // ============================================================================
  always @(posedge clk) begin
    inject_hold_failure  <= $test$plusargs("F02_NEGATIVE_HOLD") && !inject_hold_failure;
    inject_flush_failure <= $test$plusargs("F02_NEGATIVE_FLUSH") && flush_d;
  end

endmodule
