// ==============================================================================
// File: f3_scenario.svh
// Project: RISCFORGE 1TOPS RISC-V Core Verification
// Module: tb_core_trap_lean Asynchronous Interrupt Fixture
// Description:
//   F3 fixture orchestration and independent retirement-frontier snapshots.
//   Only these task calls own scenario phases.
//   Never use DUT PCE/trap_pc as an oracle.
// ==============================================================================

// ------------------------------------------------------------------------------
// F3 Fixture State & Orchestration Signals
// ------------------------------------------------------------------------------
string            irq_case;
logic [31:0]      f3_pending_mask;
logic [31:0]      f3_ready_pc;
logic [31:0]      f3_enable_pc;
bit               f3_ready_retired  = 0;
bit               f3_enable_retired = 0;
bit               f3_source_started = 0;
int               f3_source_age     = 0;
int               f3_masked_samples = 0;
int               f3_service_start  = -1;
int unsigned      f3_mask_witness;

wire f3_mask_window   = f3_enabled && f3_source_started && f3_source_age >= 2 &&
                        !f3_enable_retired && irq_case != "timer-late";

wire f3_request_ready = f3_enabled && f3_source_started && f3_source_age >= 2 && f3_enable_retired;

// ------------------------------------------------------------------------------
// Retirement Frontier Pre-Interrupt Snapshots
// ------------------------------------------------------------------------------
logic [31:0]      f3_snapshot_pc[0:STEP_LIMIT-1];
logic [31:0]      f3_snapshot_gpr[0:STEP_LIMIT-1][0:31];
logic             f3_snapshot_known[0:STEP_LIMIT-1][0:31];
machine_state_t   f3_snapshot_csr[0:STEP_LIMIT-1];
int               f3_snapshot_gpr_count[0:STEP_LIMIT-1];
int               f3_snapshot_store_count[0:STEP_LIMIT-1];


// ------------------------------------------------------------------------------
// Task: save_f3_snapshot
// Description:
//   Takes an exact architectural snapshot at each instruction boundary
//   before execution, allowing exact rollback of unretired speculative effects
//   when an asynchronous interrupt is acknowledged.
// ------------------------------------------------------------------------------
task automatic save_f3_snapshot(input int slot, input logic [31:0] pc);
  if (slot >= STEP_LIMIT)
    $fatal(1, "F3 snapshot capacity exceeded");

  f3_snapshot_pc[slot]  = pc;
  f3_snapshot_csr[slot] = machine_state;

  for (int reg_index = 0; reg_index < 32; reg_index++) begin
    f3_snapshot_gpr[slot][reg_index]   = model_gpr[reg_index];
    f3_snapshot_known[slot][reg_index] = model_gpr_known[reg_index];
  end

  f3_snapshot_gpr_count[slot]   = scoreboard.gpr_count();
  f3_snapshot_store_count[slot] = scoreboard.store_count();
endtask


// ------------------------------------------------------------------------------
// Task: update_f3_frontier
// Description:
//   Dynamically updates the expected trap PC and CSR states to track the
//   core's real retirement frontier as instructions commit.
// ------------------------------------------------------------------------------
task automatic update_f3_frontier();
  int slot;
  machine_state_t entry_state;

  if (f3_enabled && observed_traps == 0 && !scoreboard.retirement_complete()) begin
    slot = scoreboard.retired_count();
    expected_fault_pc = scoreboard.next_retirement_pc();

    if (expected_fault_pc !== f3_snapshot_pc[slot])
      $fatal(1, "F3 inconsistent model frontier");

    expected_resume_pc  = expected_fault_pc;
    expected_handler_pc = HANDLER_PC;
    expected_tval       = 0;

    entry_state = f3_snapshot_csr[slot];
    entry_state.mstatus[7]     = entry_state.mstatus[3];
    entry_state.mstatus[3]     = 0;
    entry_state.mstatus[12:11] = 3;
    expected_entry_status      = entry_state.mstatus;

    entry_state.mstatus[3]     = entry_state.mstatus[7];
    entry_state.mstatus[7]     = 1;
    expected_return_status     = entry_state.mstatus;
  end
endtask


// ------------------------------------------------------------------------------
// Task: insert_f3_interrupt
// Description:
//   Invoked upon observing the physical trap entry edge.
//   Revises the scoreboard's unconsumed predictions to truncate at the
//   interrupted instruction boundary, enters the reference interrupt state,
//   and simulates the trap handler through MRET.
// ------------------------------------------------------------------------------
task automatic insert_f3_interrupt();
  int slot;
  int steps;
  logic [31:0] pc;
  logic [31:0] next_pc_value;
  logic wr_gpr, wr_mem, sync_fault, returning;
  logic [4:0] rd;
  logic [31:0] result_value, address_value, data_value;

  slot = scoreboard.retired_count();

  if (observed_traps != 0)
    $fatal(1, "F3 unexpected second interrupt");

  // Check all older physical effects BEFORE altering any future expectation.
  scoreboard.revise_unconsumed(slot, f3_snapshot_gpr_count[slot], f3_snapshot_store_count[slot]);

  if (f3_snapshot_store_count[slot] != 0)
    $fatal(1, "F3 interrupt arrived after the supported pre-store window");

  for (int reg_index = 0; reg_index < 32; reg_index++) begin
    model_gpr[reg_index]       = f3_snapshot_gpr[slot][reg_index];
    model_gpr_known[reg_index] = f3_snapshot_known[slot][reg_index];
  end

  machine_state = f3_snapshot_csr[slot];

  enter_interrupt(expected_fault_pc, expected_cause, machine_state);

  reference_memory = new(DBASE, DMEM_WORDS * 4);
  pc = HANDLER_PC;
  steps = 0;

  while (steps < STEP_LIMIT) begin
    if (pc < BASE || pc[1:0] != 0 || (pc - BASE) / 4 >= IMEM_WORDS)
      $fatal(1, "F3 reference fetch outside image");

    step_machine(pc, program_image[(pc - BASE) / 4], model_gpr, model_gpr_known,
                 machine_state, next_pc_value, wr_gpr, rd, result_value,
                 wr_mem, address_value, data_value, sync_fault, returning);

    if (sync_fault)
      $fatal(1, "F3 unexpected synchronous fault in reference image");

    scoreboard.expect_instruction('{pc: pc, instruction: program_image[(pc - BASE) / 4]});

    if (wr_gpr)
      scoreboard.expect_gpr('{pc: pc, rd: rd, value: result_value});

    if (wr_mem) begin
      scoreboard.expect_store('{address: address_value, byte_enable: 4'hf, value: data_value});
      reference_memory.store(address_value, 4'hf, data_value);
    end

    steps++;

    if (next_pc_value == pc)
      break;

    pc = next_pc_value;
  end

  if (next_pc_value != pc)
    $fatal(1, "F3 reference step bound exceeded");

  scoreboard.seal();

  $display("F3_FRONTIER expected_unretired_pc=%08x retired_prefix=%0d expected_cause=%08x",
           expected_fault_pc, slot, {1'b1, expected_cause});
endtask


// ------------------------------------------------------------------------------
// Process: f3_drive_sources
// Description:
//   Drives asynchronous interrupt pins 2ns after the falling clock edge.
//   Ensures stable setup and hold margins relative to the core's rising edge.
// ------------------------------------------------------------------------------
initial begin : f3_drive_sources
  if (f3_enabled) begin
    wait (rst);

    if (irq_case == "timer-late") begin
      wait (f3_enable_retired);
      repeat (3) @(negedge clk);
    end else
      wait (f3_ready_retired);

    @(negedge clk);
    #2;

    timer_irq = f3_pending_mask[7];
    ext_irq   = f3_pending_mask[11];
    sw_irq    = f3_pending_mask[3];
    fast_irq  = f3_pending_mask[31:16];

    f3_source_started = 1;

    $display("F3_SOURCE time=%0t case=%s mask=%08x", $time, irq_case, f3_pending_mask);

    // Timer/event/edge sources get one clock-wide pulse. External/software are
    // level sources and stay asserted until serviced (or the bounded failure).
    #10;
    timer_irq = 0;
    fast_irq  = 0;
  end
end
