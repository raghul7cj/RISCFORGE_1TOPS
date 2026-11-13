// ==============================================================================
// File: tb_core_trap_lean.sv
// Project: RISCFORGE 1TOPS RISC-V Core Verification
// Module: tb_core_trap_lean
// Description:
//   F0/F0.1 bounded architectural stream test. Clock drives all components;
//   stimulus/preload occurs on falling edges; event comparison samples posedges.
//   Supports F0/F0.1 baseline execution, F0.2 pipeline temporal checks,
//   F1 machine privileged architecture (ECALL/MRET), F2 synchronous exceptions,
//   and F3 asynchronous interrupt orchestration.
// ==============================================================================

`timescale 1ns/1ps

module tb_core_trap_lean;

  // ============================================================================
  // Package Imports
  // ============================================================================
  import core_events_pkg::*;
  import rv32_reference_pkg::*;
  import core_scoreboard_pkg::*;
  import rv32_machine_reference_pkg::*;


  // ============================================================================
  // Configuration Parameters and Timing Constants
  // ============================================================================
  parameter logic [31:0] BASE = 32'h8000_0000;

`ifdef F0_OFFSET
  parameter logic [31:0] RESET_PC = BASE + 32'h40;
`else
  parameter logic [31:0] RESET_PC = BASE;
`endif

  parameter logic [31:0] DBASE            = 32'h8000_1000;
  parameter integer      IMEM_WORDS       = 256;
  parameter integer      DMEM_WORDS       = 64;
  parameter integer      WATCHDOG         = 400;

`ifdef F02_WAIT
  parameter int unsigned DMEM_WAIT_CYCLES = 3;
`else
  parameter int unsigned DMEM_WAIT_CYCLES = 0;
`endif

  parameter int          MISALIGN_OFFSET  = 2;

  localparam integer      STEP_LIMIT          = 64;
  localparam logic [31:0] HANDLER_PC          = RESET_PC + 32'h100;
  localparam int          HANDLER_OFFSET_WORDS = 64;


  // ============================================================================
  // Primary Clock and Reset Generation
  // ============================================================================
  logic clk = 1'b0;
  logic rst = 1'b0;

  always #5 clk = ~clk;


  // ============================================================================
  // Physical Memory and Interrupt Interface Signals
  // ============================================================================
  logic [31:0] imem_rdata;
  logic [31:0] dmem_rdata;
  logic        imem_en;
  logic        imem_we;
  logic [3:0]  imem_mask;
  logic [29:0] imem_addr;
  logic [31:0] imem_wdata;

  logic        mem_req;
  logic        mem_we;
  logic        mem_stall;
  logic        mem_err;
  logic [31:0] mem_addr;
  logic [31:0] mem_wdata;
  logic [3:0]  mem_be;

  logic        accepted;
  logic        accepted_we;
  logic [31:0] accepted_addr;
  logic [31:0] accepted_wdata;
  logic [3:0]  accepted_be;

  logic [15:0] fast_irq  = '0;
  logic        timer_irq = 1'b0;
  logic        ext_irq   = 1'b0;
  logic        sw_irq    = 1'b0;
  wire         unused_debug;


  // ============================================================================
  // Read-Only DUT Observation Signals
  // ============================================================================
  logic        obs_valid_d;
  logic        obs_rf_we;
  logic        obs_valid_w;
  logic        obs_retired_w;
  logic [31:0] obs_pc_d;
  logic [31:0] obs_instr_d;
  logic [31:0] obs_wdata;
  logic [31:0] obs_pc_w;
  logic [4:0]  obs_rd;
  logic        obs_stall_d;
  logic        obs_flush_d;


  // ============================================================================
  // Independent Reference Model & Scoreboard State
  // ============================================================================
  logic [31:0]           program_image[0:IMEM_WORDS-1];
  logic [31:0]           model_gpr[0:31];
  logic                  model_gpr_known[0:31];
  integer                cycles             = 0;
  integer                request_wait_edges = 0;
  integer                total_wait_edges   = 0;
  integer                fetch_cover_hits   = 0;
  integer                store_cover_hits   = 0;
  integer                program_words;
  bit                    store_hook_used    = 0;

  core_scoreboard        scoreboard;
  rv32_reference_memory  reference_memory;
  machine_state_t        machine_state;

  bit                    f3_enabled           = $test$plusargs("F3_CASE");
  bit                    f2_enabled           = $test$plusargs("F2_CASE");
  bit                    machine_test_enabled = $test$plusargs("F1_ECALL") || f2_enabled || f3_enabled;

  string                 exception_case = "ecall";
  logic [31:0]           fault_instruction;
  logic [30:0]           expected_cause;
  logic [31:0]           expected_tval;
  logic [31:0]           expected_fault_pc;
  logic [31:0]           expected_handler_pc;
  logic [31:0]           expected_resume_pc;
  logic [31:0]           expected_entry_status;
  logic [31:0]           expected_return_status;

  int unsigned           predicted_traps = 0;
  int unsigned           predicted_returns = 0;
  int unsigned           observed_traps = 0;
  int unsigned           observed_returns = 0;
  int unsigned           trap_entry_witness;
  int unsigned           trap_return_witness;
  int unsigned           alignment_witness;


  // ============================================================================
  // Reusable Temporal Checkers (SVA Protocol Checking)
  // ============================================================================
  core_pipeline_if pipeline(clk, rst);

  int unsigned stage_reset_checks[0:3];
  int unsigned stage_flush_checks[0:3];
  int unsigned stage_hold_checks[0:3];
  int unsigned pc_hold_checks;
  int unsigned branch_checks;
  int unsigned wb_checks;
  int unsigned wait_checks;
  int unsigned release_checks;

  core_pipeline_sva protocol_checks (
    .pipe           (pipeline),
    .reset_checks   (stage_reset_checks),
    .flush_checks   (stage_flush_checks),
    .hold_checks    (stage_hold_checks),
    .pc_hold_checks (pc_hold_checks),
    .branch_checks  (branch_checks),
    .wb_checks      (wb_checks),
    .wait_checks    (wait_checks),
    .release_checks (release_checks)
  );

  // Negative self-test changes only the oracle input to the shared checker.
  wire [31:0] checked_trap_pc = expected_fault_pc +
    ((f3_enabled && $test$plusargs("F3_NEGATIVE_MEPC")) ? 32'd4 : 32'd0);

  core_sync_trap_sva trap_checks (
    .pipe                   (pipeline),
    .enable                 (machine_test_enabled),
    .expected_interrupt     (f3_enabled),
    .expected_cause         (expected_cause),
    .expected_tval          (expected_tval),
    .expected_fault_pc      (checked_trap_pc),
    .expected_handler_pc    (expected_handler_pc),
    .expected_resume_pc     (expected_resume_pc),
    .expected_entry_status  (expected_entry_status),
    .expected_return_status (expected_return_status),
    .entry_witness          (trap_entry_witness),
    .return_witness         (trap_return_witness),
    .alignment_witness      (alignment_witness)
  );


  // ============================================================================
  // Hardware Functional Coverage Monitor
  // ============================================================================
  int unsigned covered_trap_samples;
  int unsigned covered_causes[0:31];
  int unsigned covered_irq_causes[0:31];
  int unsigned covered_irq_entries;
  int unsigned covered_returns;
  int unsigned covered_modes[0:1];

  trap_functional_cov functional_coverage (
    .pipe                  (pipeline),
    .trap_samples          (covered_trap_samples),
    .cause_hits            (covered_causes),
    .irq_hits              (covered_irq_causes),
    .irq_entry_transitions (covered_irq_entries),
    .return_transitions    (covered_returns),
    .mode_hits             (covered_modes)
  );


  // ============================================================================
  // DUT and Canonical Synchronous Memory Models
  // ============================================================================
  sync_imem_sram #(
    .DEPTH_WORDS (IMEM_WORDS),
    .BASE_BYTE   (BASE),
    .RESET_PC    (RESET_PC)
  ) imem (
    .clk       (clk),
    .rst_n     (rst),
    .en        (imem_en),
    .word_addr (imem_addr),
    .rdata     (imem_rdata)
  );

  lsu_dmem_responder #(
    .DEPTH_WORDS (DMEM_WORDS),
    .BASE_BYTE   (DBASE),
    .WAIT_CYCLES (DMEM_WAIT_CYCLES)
  ) dmem (
    .clk            (clk),
    .rst_n          (rst),
    .req            (mem_req),
    .we             (mem_we),
    .addr           (mem_addr),
    .wdata          (mem_wdata),
    .be             (mem_be),
    .rdata          (dmem_rdata),
    .stall          (mem_stall),
    .err            (mem_err),
    .accepted       (accepted),
    .accepted_we    (accepted_we),
    .accepted_addr  (accepted_addr),
    .accepted_wdata (accepted_wdata),
    .accepted_be    (accepted_be)
  );

  top #(
    .RESET_PC (RESET_PC)
  ) dut (
    .clk             (clk),
    .rst             (rst),
    .PCSrcE1         (unused_debug),
    .imem_sram_en    (imem_en),
    .imem_sram_we    (imem_we),
    .imem_sram_wmask (imem_mask),
    .imem_sram_addr  (imem_addr),
    .imem_sram_wdata (imem_wdata),
    .imem_sram_rdata (imem_rdata),
    .lsu_mem_req     (mem_req),
    .lsu_mem_we      (mem_we),
    .lsu_mem_addr    (mem_addr),
    .lsu_mem_wdata   (mem_wdata),
    .lsu_mem_be      (mem_be),
    .lsu_mem_rdata   (dmem_rdata),
    .lsu_mem_stall   (mem_stall),
    .lsu_mem_err     (mem_err),
    .fast_irq_i      (fast_irq),
    .timer_irq_i     (timer_irq),
    .ext_irq_i       (ext_irq),
    .sw_irq_i        (sw_irq)
  );

  core_trap_observe observe_core (
    .clk       (clk),
    .valid_d   (obs_valid_d),
    .pc_d      (obs_pc_d),
    .instr_d   (obs_instr_d),
    .rf_we     (obs_rf_we),
    .rf_rd     (obs_rd),
    .rf_wdata  (obs_wdata),
    .pc_w      (obs_pc_w),
    .valid_w   (obs_valid_w),
    .retired_w (obs_retired_w),
    .stall_d   (obs_stall_d),
    .flush_d   (obs_flush_d),
    .pipeline  (pipeline)
  );


  // ============================================================================
  // Scenario Orchestration & Program Subroutines
  // ============================================================================
  `include "f3_scenario.svh"
  `include "programs/core_trap_programs.svh"

  core_irq_mask_sva irq_mask_checks (
    .pipe             (pipeline),
    .enable           (f3_enabled),
    .masked_window    (f3_mask_window),
    .request_ready    (f3_request_ready),
    .required_pending (f3_pending_mask),
    .masked_witness   (f3_mask_witness)
  );


  // ============================================================================
  // Scenario Program Setup and Run-Ahead Golden Reference Interpretation
  // ============================================================================
  // Sequence configuration is a program image; prediction below decodes only these bytes.
  initial begin : configure_and_predict
    integer      index;
    integer      image_start;
    logic [31:0] image_pc;
    logic [31:0] image_next;
    logic        image_writes_gpr;
    logic        image_writes_mem;
    logic [4:0]  image_rd;
    logic [31:0] image_result;
    logic [31:0] image_store_address;
    logic [31:0] image_store_value;
    logic        image_exception;
    logic        image_return;

    if ($isunknown({RESET_PC, BASE, DBASE}) || RESET_PC[1:0] != 0 ||
        RESET_PC < BASE || (({1'b0, RESET_PC} - BASE) >> 2) >= IMEM_WORDS)
      $fatal(1, "F0 invalid image start");

    fault_instruction = INSN_ECALL;

    if (f2_enabled) begin
      if (!$value$plusargs("F2_CASE=%s", exception_case))
        $fatal(1, "F2 missing exception case");
      if (MISALIGN_OFFSET <= 0 || MISALIGN_OFFSET >= 4)
        $fatal(1, "F2 invalid misalignment offset");
      case (exception_case)
        "illegal": fault_instruction = INSN_ILLEGAL;
        "ebreak":  fault_instruction = INSN_EBREAK;
        "load":    fault_instruction = enc_lw(15, 1, MISALIGN_OFFSET);
        "store":   fault_instruction = enc_sw(10, 1, MISALIGN_OFFSET);
        default:   $fatal(1, "F2 unsupported case %s", exception_case);
      endcase
    end

    image_start = (RESET_PC - BASE) >> 2;
    scoreboard  = new(STEP_LIMIT);

    for (index = 0; index < IMEM_WORDS; index = index + 1)
      program_image[index] = 32'h0000_0013;

    if (f3_enabled) begin
      build_f3_program(image_start, program_words);
    end else if (machine_test_enabled) begin
      if (DMEM_WAIT_CYCLES != 0 || image_start + HANDLER_OFFSET_WORDS + 15 > IMEM_WORDS)
        $fatal(1, "F1 invalid smoke memory configuration");

      // ---- Application: software setup, one fault, then observable resumption ----
      program_image[image_start + 0] = enc_lui(1, DBASE[31:12]);
      program_image[image_start + 1] = enc_lui(4, (HANDLER_PC + 32'h800) >> 12);
      program_image[image_start + 2] = enc_addi(4, 4, $signed(HANDLER_PC[11:0]));
      program_image[image_start + 3] = enc_csr(3'b001, 0, CSR_MTVEC, 4);
      program_image[image_start + 4] = enc_addi(2, 0, 8);
      program_image[image_start + 5] = enc_csr(3'b001, 0, CSR_MSTATUS, 2);
      program_image[image_start + 6] = enc_addi(10, 0, 90);
      program_image[image_start + 7] = fault_instruction;

      // Complementary layouts retain identical effects. Dense mode specifically
      // exercises a MEM-stage store on the ECALL commitment edge. Smoke mode
      // isolates handler/return with a younger RF instruction followed by a store.
      if ($test$plusargs("F1_ADJACENT_STORE")) begin
        program_image[image_start + 8] = enc_sw(10, 1, 0);
        program_image[image_start + 9] = enc_addi(11, 0, 1);
      end else begin
        program_image[image_start + 8] = enc_addi(11, 0, 1);
        program_image[image_start + 9] = enc_sw(10, 1, 0);
      end

      program_image[image_start + 10] = enc_addi(12, 11, 1);
      program_image[image_start + 11] = enc_sw(12, 1, 4);
      program_image[image_start + 12] = enc_csr(3'b010, 14, CSR_MSTATUS, 0);
      program_image[image_start + 13] = enc_jal(0, 0);

      build_shared_handler(image_start, program_words);
    end else if ($test$plusargs("F02_ISOLATE_WAIT")) begin
      // Deliberate NOP in WB isolates register-hold checks from the separate
      // physical GPR-write-during-wait experiment on the unmodified F0 stream.
      program_image[image_start + 0] = enc_lui(1, DBASE[31:12]);
      program_image[image_start + 1] = enc_addi(2, 0, 11);
      program_image[image_start + 2] = enc_addi(0, 0, 0);
      program_image[image_start + 3] = enc_sw(2, 1, 0);
      program_image[image_start + 4] = enc_jal(0, 12);
      program_image[image_start + 5] = enc_addi(7, 0, 99);
      program_image[image_start + 6] = enc_sw(7, 1, 4);
      program_image[image_start + 7] = enc_addi(6, 0, 6);
      program_image[image_start + 8] = enc_jal(0, 0);
      program_words = 9;
    end else if ($test$plusargs("F0_JAL_PROGRAM")) begin
      program_image[image_start + 0] = enc_lui(1, DBASE[31:12]);
      program_image[image_start + 1] = enc_addi(2, 0, 11);
      program_image[image_start + 2] = enc_sw(2, 1, 0);
      program_image[image_start + 3] = enc_addi(2, 0, 22);
      program_image[image_start + 4] = enc_sw(2, 1, 0);
      program_image[image_start + 5] = enc_jal(0, 12);
      program_image[image_start + 6] = enc_addi(7, 0, 99);
      program_image[image_start + 7] = enc_sw(7, 1, 4);
      program_image[image_start + 8] = enc_addi(6, 0, 6);
      program_image[image_start + 9] = enc_jal(0, 0);
      program_words = 10;
    end else if ($test$plusargs("F0_SECOND_PROGRAM")) begin
      program_image[image_start + 0] = enc_lui(1, DBASE[31:12]);
      program_image[image_start + 1] = enc_addi(2, 0, -5);
      program_image[image_start + 2] = enc_addi(4, 2, 2);
      program_image[image_start + 3] = enc_sw(4, 1, 0);
      program_image[image_start + 4] = enc_addi(5, 0, 7);
      program_image[image_start + 5] = enc_sw(5, 1, 4);
      program_image[image_start + 6] = enc_jal(0, 0);
      program_words = 7;
    end else begin
      program_image[image_start + 0] = enc_lui(1, DBASE[31:12]);
      program_image[image_start + 1] = enc_addi(2, 0, 90);
      program_image[image_start + 2] = enc_sw(2, 1, 0);
      program_image[image_start + 3] = enc_addi(3, 0, 1);
      program_image[image_start + 4] = enc_addi(3, 3, 1);
      program_image[image_start + 5] = enc_jal(0, 0);
      program_words = 6;
    end

    if (RESET_PC[1:0] != 0 || RESET_PC < BASE ||
        ({1'b0, RESET_PC} - BASE) + program_words * 4 > IMEM_WORDS * 4 || DBASE[11:0] != 0)
      $fatal(1, "F0 invalid program or memory placement");

    for (index = 0; index < 32; index = index + 1) begin
      model_gpr[index]       = 'x;
      model_gpr_known[index] = 1'b0;
    end

    model_gpr[0]       = '0;
    model_gpr_known[0] = 1'b1;

    reference_memory = new(DBASE, DMEM_WORDS * 4);
    machine_state    = '0;
    image_pc         = RESET_PC;
    index            = 0;

    while (index < STEP_LIMIT) begin
      integer image_word_index;

      if (image_pc < BASE || image_pc[1:0] != 0 ||
          (({1'b0, image_pc} - BASE) >> 2) >= IMEM_WORDS)
        $fatal(1, "F0 model fetch outside aligned IMEM image pc=%08x", image_pc);

      image_word_index = (image_pc - BASE) >> 2;

      if (f3_enabled)
        save_f3_snapshot(scoreboard.instruction_count(), image_pc);

      image_exception = 0;
      image_return    = 0;

      if (machine_test_enabled) begin
        step_machine(image_pc, program_image[image_word_index], model_gpr, model_gpr_known,
                     machine_state, image_next, image_writes_gpr, image_rd, image_result,
                     image_writes_mem, image_store_address, image_store_value,
                     image_exception, image_return);
      end else begin
        execute(image_pc, program_image[image_word_index], model_gpr, model_gpr_known,
                image_next, image_writes_gpr, image_rd, image_result,
                image_writes_mem, image_store_address, image_store_value);
      end

      // A faulting ECALL commits a trap, not an ordinary retired instruction.
      if (!image_exception)
        scoreboard.expect_instruction('{pc: image_pc, instruction: program_image[image_word_index]});

      if (image_exception) begin
        predicted_traps++;
        expected_cause        = machine_state.mcause[30:0];
        expected_tval         = machine_state.mtval;
        expected_fault_pc     = image_pc;
        expected_handler_pc   = image_next;
        expected_entry_status = machine_state.mstatus;
      end

      if (image_return) begin
        predicted_returns++;
        expected_resume_pc    = image_next;
        expected_return_status = machine_state.mstatus;
      end

      if (image_writes_gpr) begin
        scoreboard.expect_gpr('{pc: image_pc, rd: image_rd, value: image_result});
      end

      if (image_writes_mem) begin
        scoreboard.expect_store('{address: image_store_address, byte_enable: 4'hf, value: image_store_value});
        reference_memory.store(image_store_address, 4'hf, image_store_value);
      end

      index = index + 1;

      if (image_next == image_pc)
        break;

      image_pc = image_next;
    end

    if (image_next != image_pc)
      $fatal(1, "F0 reference step limit reached without terminal self-loop");

    // Opt-in checker self-test corrupts the predicted copy only, after execution.
    if ($test$plusargs("F0_NEGATIVE_BAD_GPR"))
      scoreboard.inject_bad_gpr_expectation();

    scoreboard.seal();

    if (machine_test_enabled && !f3_enabled && (predicted_traps != 1 || predicted_returns != 1))
      $fatal(1, "F1 predictor did not execute exactly one ECALL/MRET");

    if (f3_enabled) begin
      predicted_traps   = 1;
      predicted_returns = 1;
      update_f3_frontier();
    end

    if ($test$plusargs("F1_NEGATIVE_MEPC"))
      expected_fault_pc = expected_fault_pc + 4;

    if ($test$plusargs("F2_NEGATIVE_MTVAL"))
      expected_tval = expected_tval ^ 32'b1;

    if ($test$plusargs("F1_NEGATIVE_RETURN"))
      expected_resume_pc = expected_resume_pc + 4;

    @(negedge clk);
    for (index = 0; index < program_words; index = index + 1)
      imem.mem[image_start + index] =
        program_image[image_start + index];

    repeat (4) @(negedge clk);
    rst = 1'b1;
  end


  // ============================================================================
  // Sampling and Scoreboard Event Delivery
  // ============================================================================
  // Compare independent event streams. Retirement and physical write attempts
  // are separate channels; memory acceptance can precede the matching WB.
  always @(posedge clk) begin : compare_observed_events
    if (rst) begin
      cycles = cycles + 1;

      if ($test$plusargs("F02_TRACE"))
        $display("F02_TRACE cycle=%0d pcW=%08x validW=%b retire=%b rfwe=%b rd=%0d data=%08x req=%b wait=%b",
                 cycles, obs_pc_w, obs_valid_w, obs_retired_w, obs_rf_we, obs_rd,
                 obs_wdata, mem_req, mem_stall);

      if (mem_req && mem_stall) begin
        request_wait_edges++;
        total_wait_edges++;
      end

      if (mem_req && !mem_stall) begin
        if (request_wait_edges != DMEM_WAIT_CYCLES)
          $fatal(1, "F02 responder wait mismatch expected=%0d observed=%0d",
                 DMEM_WAIT_CYCLES, request_wait_edges);
        request_wait_edges = 0;
      end

      if ($isunknown({obs_valid_d, obs_rf_we, obs_retired_w, mem_req, accepted}))
        $fatal(1, "F0 unknown control event");

      // Decode may contain speculative wrong-path instructions. Validate each
      // observed pair against the independently supplied padded image instead.
      if (obs_valid_d && !obs_flush_d && !obs_stall_d) begin
        integer decode_index;

        if ($isunknown({obs_pc_d, obs_instr_d}) || obs_pc_d < BASE || obs_pc_d[1:0] != 0)
          $fatal(1, "F0 unknown or invalid decode event");

        decode_index = (obs_pc_d - BASE) >> 2;

        if (decode_index >= IMEM_WORDS)
          $fatal(1, "F0 decode outside padded image pc=%08x", obs_pc_d);

        if (obs_instr_d !== program_image[decode_index])
          $fatal(1, "F0 decode image mismatch pc=%08x expected=%08x actual=%08x",
                 obs_pc_d, program_image[decode_index], obs_instr_d);

        if (obs_pc_d == RESET_PC)
          fetch_cover_hits = fetch_cover_hits + 1;
      end

      if (machine_test_enabled && mem_req)
        $display("F1_BUS time=%0t we=%b addr=%08x data=%08x stall=%b error=%b trap=%b mret=%b",
                 $time, mem_we, mem_addr, mem_wdata, mem_stall, mem_err,
                 pipeline.trap_valid, pipeline.mret_commit);

      if (f3_enabled) begin
        if (f3_source_started)
          f3_source_age++;

        if (f3_mask_window) begin
          f3_masked_samples++;
          if (f3_masked_samples == 1)
            $display("F3_MASK time=%0t mip=%08x mie=%08x mstatus=%08x required=%08x",
                     $time, pipeline.csr_mip, pipeline.csr_mie, pipeline.csr_mstatus, f3_pending_mask);
        end

        if (f3_request_ready && f3_service_start < 0)
          f3_service_start = cycles;

        if (f3_service_start >= 0 && observed_traps == 0 && cycles > f3_service_start + 7)
          $fatal(1, "F3 enabled pending IRQ missing: case=%s mip=%08x mie=%08x", irq_case, pipeline.csr_mip, pipeline.csr_mie);
      end

      if (machine_test_enabled && pipeline.trap_valid) begin
        if (f3_enabled)
          insert_f3_interrupt();

        observed_traps++;
        $display("TRAP_EVENT time=%0t pc=%08x cause=%0d tval=%08x target=%08x pre_status=%08x",
                 $time, pipeline.trap_pc, pipeline.trap_cause, pipeline.trap_tval, pipeline.wb_target, pipeline.csr_mstatus);

        if (observed_traps > predicted_traps)
          $fatal(1, "F1 extra trap");
      end

      if (machine_test_enabled && pipeline.mret_commit) begin
        observed_returns++;
        $display("F1_MRET time=%0t pc=%08x mepc=%08x target=%08x pre_status=%08x",
                 $time, obs_pc_w, pipeline.csr_mepc, pipeline.wb_target, pipeline.csr_mstatus);

        if (observed_returns > predicted_returns)
          $fatal(1, "F1 extra MRET");
      end

      if (obs_retired_w) begin
        scoreboard.observe_retirement(obs_pc_w);

        if (f3_enabled) begin
          if (obs_pc_w == f3_ready_pc)
            f3_ready_retired = 1;

          if (obs_pc_w == f3_enable_pc) begin
            f3_enable_retired = 1;
            $display("F3_ENABLE time=%0t pc=%08x", $time, obs_pc_w);
          end

          update_f3_frontier();
        end
      end

      if (obs_rf_we)
        scoreboard.observe_gpr('{pc: obs_pc_w, rd: obs_rd, value: obs_wdata});

      if (accepted && $isunknown(accepted_we))
        $fatal(1, "F0 unknown accepted_we");

      if (accepted && !accepted_we)
        $fatal(1, "F0 unexpected accepted read");

      if (accepted && accepted_we) begin
        store_event_t observed_store;
        observed_store = '{address: accepted_addr, byte_enable: accepted_be, value: accepted_wdata};

        if ($test$plusargs("F0_NEGATIVE_BAD_STORE") && !store_hook_used)
          observed_store.value = observed_store.value ^ 32'b1;

        // Opt-in negative hooks alter only the event copy sent to the checker.
        // SRAM and DUT behavior remain untouched, so the run cannot mask a bug.
        if (!($test$plusargs("F0_NEGATIVE_MISSING_STORE") && !store_hook_used))
          scoreboard.observe_store(observed_store);

        if ($test$plusargs("F0_NEGATIVE_EXTRA_STORE") && !store_hook_used)
          scoreboard.observe_store(observed_store);

        store_hook_used = 1;
        store_cover_hits++;
      end

      if (cycles > WATCHDOG)
        $fatal(1, "F0 watchdog");

      if (obs_retired_w && scoreboard.retirement_complete()) begin
        scoreboard.check_drained();

        if (fetch_cover_hits == 0 || (scoreboard.store_count() != 0 && store_cover_hits == 0))
          $fatal(1, "F0 required hardware cover not observed");

        // Compare the complete configured SRAM to final reference state. This
        // handles overwrites and also catches unintended mutations elsewhere.
        for (integer word_index = 0; word_index < DMEM_WORDS; word_index++) begin
          if (dmem.mem[word_index] !== reference_memory.read_word(DBASE + 4 * word_index))
            $fatal(1, "F0 reference memory mismatch address=%08x", DBASE + 4 * word_index);
        end

        // No report may turn an unexercised temporal property into a pass claim.
        for (integer stage = 0; stage < 4; stage++) begin
          $display("F02_STAGE stage=%0d reset=%0d hold=%0d flush=%0d",
                   stage, stage_reset_checks[stage], stage_hold_checks[stage], stage_flush_checks[stage]);

          if (stage_reset_checks[stage] == 0)
            $fatal(1, "F02 missing stage reset obligation");

          if (DMEM_WAIT_CYCLES != 0 && stage_hold_checks[stage] == 0)
            $fatal(1, "F02 missing stage hold obligation");
        end

        if ($test$plusargs("F02_ISOLATE_WAIT") &&
            (stage_flush_checks[0] == 0 || stage_flush_checks[1] == 0 ||
             branch_checks == 0 || wait_checks == 0 || release_checks == 0 || pc_hold_checks == 0))
          $fatal(1, "F02 missing required wait/redirect/flush obligation");

        $display("F02_WAIT_EDGES total=%0d configured_per_request=%0d", total_wait_edges, DMEM_WAIT_CYCLES);
        $display("F02_PROTOCOL pc_hold=%0d branch=%0d wb=%0d wait=%0d release=%0d",
                 pc_hold_checks, branch_checks, wb_checks, wait_checks, release_checks);

        if (machine_test_enabled) begin
          if (observed_traps != 1 || observed_returns != 1 ||
              trap_entry_witness == 0 || trap_return_witness == 0 || wb_checks == 0 ||
              stage_flush_checks[2] == 0 || stage_flush_checks[3] == 0)
            $fatal(1, "F1 missing trap/return/flush witness");

          if (covered_trap_samples != 1 || (f3_enabled ? covered_irq_causes[expected_cause] : covered_causes[expected_cause]) != 1 || covered_modes[0] != 1)
            $fatal(1, "F2 missing hardware functional coverage sample");

          if ((expected_cause == 4 || expected_cause == 6) && alignment_witness == 0)
            $fatal(1, "F2 missing misaligned-request suppression witness");

          $display("TRAP_WITNESSES entry=%0d return=%0d wb=%0d flushM=%0d flushW=%0d misaligned_no_request=%0d",
                   trap_entry_witness, trap_return_witness, wb_checks,
                   stage_flush_checks[2], stage_flush_checks[3], alignment_witness);

          if (f2_enabled)
            $display("F2_PASS case=%s cause=%0d mtval=%08x fault_pc=%08x resume=%08x traps=%0d mret=%0d instructions=%0d gpr=%0d stores=%0d",
                     exception_case, expected_cause, expected_tval, expected_fault_pc, expected_resume_pc,
                     observed_traps, observed_returns, scoreboard.instruction_count(), scoreboard.gpr_count(), scoreboard.store_count());

          if (f3_enabled) begin
            if (covered_irq_entries == 0 || covered_returns == 0 ||
                (irq_case != "timer-late" && (f3_mask_witness == 0 || f3_masked_samples < 3)))
              $fatal(1, "F3 missing masking/transition witness");

            $display("F3_PASS case=%s cause=%08x mepc=%08x mask_samples=%0d instructions=%0d gpr=%0d stores=%0d",
                     irq_case, {1'b1, expected_cause}, expected_fault_pc, f3_masked_samples,
                     scoreboard.instruction_count(), scoreboard.gpr_count(), scoreboard.store_count());
          end

          if (!f2_enabled && !f3_enabled)
            $display("F1_PASS traps=%0d mret=%0d fault_pc=%08x handler=%08x resume=%08x instructions=%0d gpr=%0d stores=%0d",
                     observed_traps, observed_returns, expected_fault_pc, expected_handler_pc,
                     expected_resume_pc, scoreboard.instruction_count(), scoreboard.gpr_count(), scoreboard.store_count());
        end

        if (!machine_test_enabled)
          $display("F0_PASS instructions=%0d gpr=%0d stores=%0d",
                   scoreboard.instruction_count(), scoreboard.gpr_count(), scoreboard.store_count());

        $finish;
      end
    end
  end


  // ============================================================================
  // Post-Simulation Diagnostic Printout (Executed on Pass AND Fail)
  // ============================================================================
  // Final diagnostic state is printed on pass AND failure; never used as a pass
  // condition. It preserves post-edge CSR/SRAM evidence when an assertion stops.
  final begin
    if (f3_enabled)
      $display("F3_FINAL case=%s mip=%08x mie=%08x mstatus=%08x masked_samples=%0d traps=%0d returns=%0d expected_pc=%08x actual_mepc=%08x",
               irq_case, pipeline.csr_mip, pipeline.csr_mie, pipeline.csr_mstatus, f3_masked_samples,
               observed_traps, observed_returns, expected_fault_pc, pipeline.csr_mepc);

    if (machine_test_enabled)
      $display("MACHINE_FINAL traps=%0d mret=%0d mepc=%08x cause=%08x status=%08x app0=%08x app1=%08x saved_pc=%08x saved_cause=%08x saved_status=%08x poison=%08x mtval=%08x saved_mtval=%08x",
               observed_traps, observed_returns, pipeline.csr_mepc, pipeline.csr_mcause,
               pipeline.csr_mstatus, dmem.mem[0], dmem.mem[1], dmem.mem[2],
               dmem.mem[3], dmem.mem[4], dmem.mem[5], pipeline.csr_mtval, dmem.mem[6]);
  end


  // ============================================================================
  // Scoped Functional Cover Properties
  // ============================================================================
  c_valid_fetch: cover property (@(posedge clk) disable iff (!rst)
    obs_valid_d && obs_pc_d == RESET_PC);

  c_store_accept: cover property (@(posedge clk) disable iff (!rst)
    accepted && accepted_we);

endmodule
