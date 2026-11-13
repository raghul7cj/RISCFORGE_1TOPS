// ==============================================================================
// File: core_trap_programs.svh
// Project: RISCFORGE 1TOPS RISC-V Core Verification
// Module: tb_core_trap_lean Program Builders
// Description:
//   Fixture-owned software image builders.
//   Constructs self-contained machine-mode trap handlers, stimulus sequences,
//   and CSR setup routines directly into the IMEM image buffer.
//   No DUT internal state or expected effects are read by these tasks.
// ==============================================================================

// ------------------------------------------------------------------------------
// Task: build_shared_handler
// Description:
//   Constructs the common machine-mode trap handler at HANDLER_PC.
//   Saves critical diagnostic CSRs (mepc, mcause, mstatus, mtval) into DMEM,
//   increments mepc by 4 for synchronous exceptions (if skipping), and executes MRET.
// ------------------------------------------------------------------------------
task automatic build_shared_handler(input int image_start, output int image_words);
  int cursor;

  cursor = image_start + HANDLER_OFFSET_WORDS;

  // Read architectural trap diagnostic registers into temporary registers
  program_image[cursor++] = enc_csr(3'b010, 5, CSR_MEPC,    0);
  program_image[cursor++] = enc_csr(3'b010, 6, CSR_MCAUSE,  0);
  program_image[cursor++] = enc_csr(3'b010, 7, CSR_MSTATUS, 0);

  if (f2_enabled)
    program_image[cursor++] = enc_csr(3'b010, 8, CSR_MTVAL, 0);

  // Store captured trap registers into DMEM scratchpad for observation
  program_image[cursor++] = enc_sw(5, 1, 8);
  program_image[cursor++] = enc_sw(6, 1, 12);
  program_image[cursor++] = enc_sw(7, 1, 16);

  if (f2_enabled)
    program_image[cursor++] = enc_sw(8, 1, 24);

  // Synchronous faults: skip faulting instruction (mepc += 4).
  // Asynchronous interrupts: replay interrupted instruction (mepc untouched).
  if (!f3_enabled) begin
    program_image[cursor++] = enc_addi(5, 5, 4);
    program_image[cursor++] = enc_csr(3'b001, 0, CSR_MEPC, 5);
  end

  // Mark handler completion signature and execute privileged return
  program_image[cursor++] = enc_addi(13, 0, 51);
  program_image[cursor++] = INSN_MRET;

  // Epilogue post-return trap signature (should never execute if return succeeds)
  program_image[cursor++] = enc_addi(20, 0, 99);
  program_image[cursor++] = enc_sw(10, 1, 20);
  program_image[cursor++] = enc_jal(0, 0);

  image_words = cursor - image_start;
endtask


// ------------------------------------------------------------------------------
// Task: build_f3_program
// Description:
//   Configures the F3 asynchronous interrupt stimulus sequence.
//   Sets up mtvec, enables specific interrupt lines via mie, enables global
//   interrupts via mstatus.MIE, and executes a verifiable background loop.
// ------------------------------------------------------------------------------
task automatic build_f3_program(input int image_start, output int image_words);
  int cursor;

  if (!$value$plusargs("F3_CASE=%s", irq_case))
    $fatal(1, "F3 missing case");

  case (irq_case)
    "timer", "timer-late": begin
      f3_pending_mask = 32'h80;
      expected_cause   = 7;
    end

    "external": begin
      f3_pending_mask = 32'h800;
      expected_cause   = 11;
    end

    "software": begin
      f3_pending_mask = 32'h8;
      expected_cause   = 3;
    end

    "fast0": begin
      f3_pending_mask = 32'h00010000;
      expected_cause   = 16;
    end

    "fast6": begin
      f3_pending_mask = 32'h00400000;
      expected_cause   = 22;
    end

    // Retained requested policy: MEIP > MTIP > MSIP (standard RISC-V priority).
    "priority": begin
      f3_pending_mask = 32'h888;
      expected_cause   = 11;
    end

    default:
      $fatal(1, "F3 unsupported case %s", irq_case);
  endcase

  if (DMEM_WAIT_CYCLES != 0)
    $fatal(1, "F3 fixture requires zero-wait memory");

  cursor = image_start;

  // Initialize data base pointer in x1
  program_image[cursor++] = enc_lui(1, DBASE[31:12]);

  // Configure mtvec register with trap handler entry point
  program_image[cursor++] = enc_lui(4, (HANDLER_PC + 32'h800) >> 12);
  program_image[cursor++] = enc_addi(4, 4, $signed(HANDLER_PC[11:0]));
  program_image[cursor++] = enc_csr(3'b001, 0, CSR_MTVEC, 4);

  // Configure mie register with selected interrupt pending mask
  program_image[cursor++] = enc_lui(9, (f3_pending_mask + 32'h800) >> 12);
  program_image[cursor++] = enc_addi(9, 9, $signed(f3_pending_mask[11:0]));
  program_image[cursor++] = enc_csr(3'b001, 0, CSR_MIE, 9);

  f3_ready_pc = RESET_PC + 4 * (cursor - image_start);

  program_image[cursor++] = enc_addi(11, 0, 0);

  // Real executable mask window; no coverage is sampled from these loop indices.
  repeat (8)
    program_image[cursor++] = enc_addi(0, 0, 0);

  // Enable global interrupts by setting mstatus.MIE
  program_image[cursor++] = enc_addi(2, 0, 8);

  f3_enable_pc = RESET_PC + 4 * (cursor - image_start);

  program_image[cursor++] = enc_csr(3'b001, 0, CSR_MSTATUS, 2);

  // Varying, dependent architectural effects distinguish skip/replay errors.
  repeat (24)
    program_image[cursor++] = enc_addi(11, 11, 1);

  program_image[cursor++] = enc_addi(12, 11, 1);
  program_image[cursor++] = enc_sw(11, 1, 0);
  program_image[cursor++] = enc_sw(12, 1, 4);
  program_image[cursor++] = enc_csr(3'b010, 14, CSR_MSTATUS, 0);
  program_image[cursor++] = enc_jal(0, 0);

  build_shared_handler(image_start, image_words);
endtask
