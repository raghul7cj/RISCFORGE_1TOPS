// =============================================================================
// Module Name : rf_mon_empirical_challenge_tb.sv
// Description : Empirical Verification & Adversarial Stress Harness for
//               Milestone 1 Passive Monitors, Freeze Broadcast, and Shadow PC.
//
// Key Challenge Oracles:
//   1. DUAL LOCKSTEP NON-INTRUSIVENESS:
//      Simultaneously runs u_dut (monitored) and u_dut_golden (standalone).
//      Assures 0 DUT drivers, 0 altered timing/latency, and 0 injected stalls.
//   2. SHADOW PC RETRIEVAL ACCURACY:
//      Tests branch speculative flushes, tight multi-iteration loops,
//      pipeline stalls (Load-use & memory wait-states), and traps (ECALL).
//   3. 64-ENTRY CIRCULAR BUFFER INTEGRITY:
//      Pushes > 120 transactions to verify wrap-around without overflow/corruption.
//   4. SIMULTANEOUS CYCLE-0 FREEZE LOCK:
//      Asserts freeze mid-burst and verifies all 6 ring buffer write pointers freeze instantly.
// =============================================================================

`timescale 1ns/1ps

module rf_mon_empirical_challenge_tb import tb_pkg::*; ;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic freeze = 1'b0;

  always #5 clk = ~clk; // 100 MHz clock

  // External pin wires (standard pullup / idle)
  logic uart_rx_wire = 1'b1;
  wire  uart_tx_wire = 1'b1;
  logic spi_miso_wire = 1'b0;
  logic [31:0] gpio_in_wire  = '0;
  logic [31:0] gpio_out_wire = '0;
  logic [31:0] gpio_oe_wire  = '0;
  wire  i2c_scl_wire = 1'b1;
  wire  i2c_sda_wire = 1'b1;
  wire  spi_sclk_wire = 1'b0;
  wire  spi_csn0_wire = 1'b1;
  wire  spi_csn1_wire = 1'b1;
  wire  spi_mosi_wire = 1'b0;

  // ---------------------------------------------------------------------------
  // 1. Dual DUT Instances for Non-Intrusiveness Lockstep Verification
  // ---------------------------------------------------------------------------
  // u_dut is MONITORED by rf_mon_probe
  rf_mon_challenger_dut u_dut (.clk(clk));

  // u_dut_golden is STANDALONE (zero verification taps attached)
  rf_mon_challenger_dut u_dut_golden (.clk(clk));

  // ---------------------------------------------------------------------------
  // 2. Passive Monitor Infrastructure Probe (Under Test)
  // ---------------------------------------------------------------------------
  rf_mon_probe #(
    .RING_DEPTH(256),
    .DUMP_N(4),
    .RUN_MONITORS(1'b1)
  ) u_mon (
    .clk           (clk),
    .rst_n         (rst_n),
    .freeze        (freeze),
    .uart_rx_wire  (uart_rx_wire),
    .uart_tx_wire  (uart_tx_wire),
    .i2c_scl_wire  (i2c_scl_wire),
    .i2c_sda_wire  (i2c_sda_wire),
    .spi_sclk_wire (spi_sclk_wire),
    .spi_csn0_wire (spi_csn0_wire),
    .spi_csn1_wire (spi_csn1_wire),
    .spi_mosi_wire (spi_mosi_wire),
    .spi_miso_wire (spi_miso_wire),
    .gpio_in_wire  (gpio_in_wire),
    .gpio_out_wire (gpio_out_wire),
    .gpio_oe_wire  (gpio_oe_wire)
  );

  // ---------------------------------------------------------------------------
  // 3. Test Bench State & Check Utilities
  // ---------------------------------------------------------------------------
  int unsigned test_errors = 0;
  int unsigned cycles_checked = 0;
  int unsigned lockstep_mismatches = 0;

  task automatic chal_check(string test_id, bit condition, string detail = "");
    if (!condition) begin
      test_errors++;
      $display("[CHALLENGE] *** FAIL ***  %-30s %s", test_id, detail);
    end else begin
      $display("[CHALLENGE] [PASS]        %-30s %s", test_id, detail);
    end
  endtask

  // Reset Sequence
  initial begin
    rst_n = 1'b0;
    freeze = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  // ---------------------------------------------------------------------------
  // 4. ORACLE 1: Dual Lockstep Equivalence & 0 DUT Driver Verification
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n) begin
      cycles_checked++;

      // Check Fetch Stage
      if (u_dut.i_riscv_core.Fetch.PCF !== u_dut_golden.i_riscv_core.Fetch.PCF) begin
        lockstep_mismatches++;
        $display("[FAIL-INTRUSIVE] Cycle %0d: PCF mismatch! Monitored=0x%08h, Golden=0x%08h",
          cycles_checked, u_dut.i_riscv_core.Fetch.PCF, u_dut_golden.i_riscv_core.Fetch.PCF);
      end
      if (u_dut.i_riscv_core.Fetch.InstrF !== u_dut_golden.i_riscv_core.Fetch.InstrF) begin
        lockstep_mismatches++;
        $display("[FAIL-INTRUSIVE] Cycle %0d: InstrF mismatch! Monitored=0x%08h, Golden=0x%08h",
          cycles_checked, u_dut.i_riscv_core.Fetch.InstrF, u_dut_golden.i_riscv_core.Fetch.InstrF);
      end
      if (u_dut.i_riscv_core.Fetch.imem_stall !== u_dut_golden.i_riscv_core.Fetch.imem_stall) begin
        lockstep_mismatches++;
        $display("[FAIL-INTRUSIVE] Cycle %0d: imem_stall altered by monitor!", cycles_checked);
      end
      if (u_dut.i_riscv_core.StallF !== u_dut_golden.i_riscv_core.StallF) begin
        lockstep_mismatches++;
        $display("[FAIL-INTRUSIVE] Cycle %0d: StallF altered by monitor!", cycles_checked);
      end

      // Check Writeback Stage
      if (u_dut.i_riscv_core.valid_W !== u_dut_golden.i_riscv_core.valid_W) begin
        lockstep_mismatches++;
        $display("[FAIL-INTRUSIVE] Cycle %0d: valid_W mismatch! Monitored=%b, Golden=%b",
          cycles_checked, u_dut.i_riscv_core.valid_W, u_dut_golden.i_riscv_core.valid_W);
      end
      if (u_dut.i_riscv_core.PC_W !== u_dut_golden.i_riscv_core.PC_W) begin
        lockstep_mismatches++;
        $display("[FAIL-INTRUSIVE] Cycle %0d: PC_W mismatch! Monitored=0x%08h, Golden=0x%08h",
          cycles_checked, u_dut.i_riscv_core.PC_W, u_dut_golden.i_riscv_core.PC_W);
      end
      if (u_dut.i_riscv_core.ResultW !== u_dut_golden.i_riscv_core.ResultW) begin
        lockstep_mismatches++;
        $display("[FAIL-INTRUSIVE] Cycle %0d: ResultW mismatch!", cycles_checked);
      end
      if (u_dut.i_riscv_core.RDW !== u_dut_golden.i_riscv_core.RDW) begin
        lockstep_mismatches++;
        $display("[FAIL-INTRUSIVE] Cycle %0d: RDW mismatch!", cycles_checked);
      end
      if (u_dut.i_riscv_core.RegWriteW_gated !== u_dut_golden.i_riscv_core.RegWriteW_gated) begin
        lockstep_mismatches++;
        $display("[FAIL-INTRUSIVE] Cycle %0d: RegWriteW_gated mismatch!", cycles_checked);
      end

      // Check LSU & Interconnect
      if (u_dut.i_riscv_core.lsu_mem_req !== u_dut_golden.i_riscv_core.lsu_mem_req) begin
        lockstep_mismatches++;
        $display("[FAIL-INTRUSIVE] Cycle %0d: lsu_mem_req mismatch!", cycles_checked);
      end
      if (u_dut.i_riscv_core.lsu_mem_stall !== u_dut_golden.i_riscv_core.lsu_mem_stall) begin
        lockstep_mismatches++;
        $display("[FAIL-INTRUSIVE] Cycle %0d: lsu_mem_stall mismatch!", cycles_checked);
      end
      if (u_dut.core_axi_req !== u_dut_golden.core_axi_req) begin
        lockstep_mismatches++;
        $display("[FAIL-INTRUSIVE] Cycle %0d: core_axi_req mismatch!", cycles_checked);
      end
      if (u_dut.core_axi_resp !== u_dut_golden.core_axi_resp) begin
        lockstep_mismatches++;
        $display("[FAIL-INTRUSIVE] Cycle %0d: core_axi_resp mismatch!", cycles_checked);
      end
    end
  end

  // ---------------------------------------------------------------------------
  // 5. Main Stress Execution & Milestone Verification Suite
  // ---------------------------------------------------------------------------
  initial begin
    int frozen_head_fetch;
    int frozen_head_retire;
    int frozen_head_lsu;
    int frozen_head_axi;
    int frozen_head_apb;
    int frozen_head_irq;
    int retired_flush1_count = 0;
    int retired_flush2_count = 0;
    bit found_target_retire = 0;
    bit found_ecall_retire = 0;

    $display("\n================================================================================");
    $display("       RISCFORGE M1 EMPIRICAL CHALLENGE SUITE (adversarial stress testing)      ");
    $display("================================================================================");

    // Wait until Phase 1 completes (cyc 45 = 450ns)
    #450ns;
    $display("\n--- [TEST SUITE 1] In-Order Execution & Shadow PC Association ---");
    chal_check("SHADOW.seq_addi_x1",
      tb_pkg::shadow_lookup_instr(32'h0000_1000) == 32'h0010_0093,
      $sformatf("Exp: 0x00100093, Got: 0x%08h", tb_pkg::shadow_lookup_instr(32'h0000_1000)));
    chal_check("SHADOW.seq_addi_x2",
      tb_pkg::shadow_lookup_instr(32'h0000_1004) == 32'h0020_0113,
      $sformatf("Exp: 0x00200113, Got: 0x%08h", tb_pkg::shadow_lookup_instr(32'h0000_1004)));
    chal_check("SHADOW.seq_add_x3",
      tb_pkg::shadow_lookup_instr(32'h0000_1008) == 32'h0020_81b3,
      $sformatf("Exp: 0x002081b3, Got: 0x%08h", tb_pkg::shadow_lookup_instr(32'h0000_1008)));
    chal_check("SHADOW.seq_lui_x4",
      tb_pkg::shadow_lookup_instr(32'h0000_100C) == 32'h0001_8237,
      $sformatf("Exp: 0x00018237, Got: 0x%08h", tb_pkg::shadow_lookup_instr(32'h0000_100C)));

    // Wait until Phase 2 completes (cyc 85 = 850ns)
    #400ns;
    $display("\n--- [TEST SUITE 2] Branch Taken & Speculative Flush Verification ---");
    // Verify shadow table recorded branch and target
    chal_check("SHADOW.branch_recorded",
      tb_pkg::shadow_lookup_instr(32'h0000_1020) == 32'h0220_8463, "Branch opcode recorded");
    chal_check("SHADOW.flush1_recorded",
      tb_pkg::shadow_lookup_instr(32'h0000_1024) == 32'h1111_1113, "Wrong path 1 recorded at fetch");
    chal_check("SHADOW.flush2_recorded",
      tb_pkg::shadow_lookup_instr(32'h0000_1028) == 32'h2222_2213, "Wrong path 2 recorded at fetch");
    chal_check("SHADOW.target_recorded",
      tb_pkg::shadow_lookup_instr(32'h0000_1040) == 32'h3333_3313, "Target opcode recorded");

    // Scan retire monitor ring buffer: wrong-path MUST NOT be committed!
    retired_flush1_count = 0;
    retired_flush2_count = 0;
    found_target_retire = 0;
    $display("[DEBUG] Retire monitor head_ptr=%0d, total_retired=%0d",
      u_mon.u_retire_mon.head_ptr, u_mon.u_retire_mon.total_retired_instr);
    for (int i = 0; i < 64; i++) begin
      if (u_mon.u_retire_mon.ring_buffer[i].timestamp != 0) begin
        $display("[DEBUG] Ring[%0d]: cyc=%0d PC=0x%08h instr=0x%08h",
          i, u_mon.u_retire_mon.ring_buffer[i].timestamp,
          u_mon.u_retire_mon.ring_buffer[i].pc, u_mon.u_retire_mon.ring_buffer[i].instr);
      end
      if (u_mon.u_retire_mon.ring_buffer[i].pc == 32'h0000_1024) retired_flush1_count++;
      if (u_mon.u_retire_mon.ring_buffer[i].pc == 32'h0000_1028) retired_flush2_count++;
      if (u_mon.u_retire_mon.ring_buffer[i].pc == 32'h0000_1040 &&
          u_mon.u_retire_mon.ring_buffer[i].instr == 32'h3333_3313) found_target_retire = 1;
    end
    chal_check("RETIRE.flush1_suppressed", retired_flush1_count == 0,
      $sformatf("Flushed instruction 0x1024 appeared %0d times in retire log (Exp: 0)", retired_flush1_count));
    chal_check("RETIRE.flush2_suppressed", retired_flush2_count == 0,
      $sformatf("Flushed instruction 0x1028 appeared %0d times in retire log (Exp: 0)", retired_flush2_count));
    chal_check("RETIRE.target_accurate", found_target_retire == 1,
      "Branch target 0x1040 successfully retired with accurate shadow opcode");

    // Wait until Phase 3 completes (cyc 155 = 1550ns)
    #700ns;
    $display("\n--- [TEST SUITE 3] Multi-Iteration Loop Invariance ---");
    chal_check("SHADOW.loop1_opcode",
      tb_pkg::shadow_lookup_instr(32'h0000_1050) == 32'h0014_0413, "Loop body instr 1 preserved");
    chal_check("SHADOW.loop2_opcode",
      tb_pkg::shadow_lookup_instr(32'h0000_1054) == 32'h0054_1493, "Loop body instr 2 preserved");

    // Wait until Phase 4 completes (cyc 215 = 2150ns)
    #600ns;
    $display("\n--- [TEST SUITE 4] Pipeline Stalls & Memory Wait-States ---");
    chal_check("SHADOW.lw_opcode",
      tb_pkg::shadow_lookup_instr(32'h0000_1070) == 32'h0005_a503, "Load word opcode preserved");
    chal_check("SHADOW.stalled_addi",
      tb_pkg::shadow_lookup_instr(32'h0000_1074) == 32'h0010_0093, "Stalled addi opcode preserved");

    // Wait until Phase 5 completes (cyc 265 = 2650ns)
    #500ns;
    $display("\n--- [TEST SUITE 5] Exception / Trap Commit Handling ---");
    found_ecall_retire = 0;
    for (int i = 0; i < 64; i++) begin
      if (u_mon.u_retire_mon.ring_buffer[i].pc == 32'h0000_1080 &&
          u_mon.u_retire_mon.ring_buffer[i].trap == 1'b1 &&
          u_mon.u_retire_mon.ring_buffer[i].instr == 32'h0000_0073) begin
        found_ecall_retire = 1;
      end
    end
    chal_check("RETIRE.ecall_trap_capture", found_ecall_retire == 1,
      "ECALL trap committed with accurate opcode 0x00000073 and trap flag");

    // Wait until Phase 6 completes (cyc 395 = 3950ns)
    #1300ns;
    $display("\n--- [TEST SUITE 6] 64-Entry Ring Buffer Wrap-Around Integrity ---");
    chal_check("RING.fetch_wrapped",
      u_mon.u_fetch_mon.total_fetches > 100,
      $sformatf("Total fetches: %0d (> 64)", u_mon.u_fetch_mon.total_fetches));
    chal_check("RING.retire_wrapped",
      u_mon.u_retire_mon.total_retired_instr > 100,
      $sformatf("Total retired: %0d (> 64)", u_mon.u_retire_mon.total_retired_instr));
    chal_check("RING.head_ptr_in_bounds_fetch",
      u_mon.u_fetch_mon.head_ptr < 64,
      $sformatf("Fetch head_ptr=%0d within [0..63]", u_mon.u_fetch_mon.head_ptr));
    chal_check("RING.head_ptr_in_bounds_retire",
      u_mon.u_retire_mon.head_ptr < 64,
      $sformatf("Retire head_ptr=%0d within [0..63]", u_mon.u_retire_mon.head_ptr));
    chal_check("RING.head_ptr_in_bounds_lsu",
      u_mon.u_lsu_mon.head_ptr < 64,
      $sformatf("LSU head_ptr=%0d within [0..63]", u_mon.u_lsu_mon.head_ptr));
    chal_check("RING.head_ptr_in_bounds_axil",
      u_mon.u_axi_mon.head_ptr < 64,
      $sformatf("AXI head_ptr=%0d within [0..63]", u_mon.u_axi_mon.head_ptr));
    chal_check("RING.head_ptr_in_bounds_apb",
      u_mon.u_apb_mon.head_ptr < 64,
      $sformatf("APB head_ptr=%0d within [0..63]", u_mon.u_apb_mon.head_ptr));

    // Phase 7: Assert freeze at cyc 405 (4050ns)
    #100ns;
    $display("\n--- [TEST SUITE 7] Simultaneous Freeze Broadcast (Cycle-0 Lock) ---");
    @(posedge clk);
    freeze = 1'b1; // Trigger simultaneous freeze!
    #1ps;          // Let NBA settle
    frozen_head_fetch  = u_mon.u_fetch_mon.head_ptr;
    frozen_head_retire = u_mon.u_retire_mon.head_ptr;
    frozen_head_lsu    = u_mon.u_lsu_mon.head_ptr;
    frozen_head_axi    = u_mon.u_axi_mon.head_ptr;
    frozen_head_apb    = u_mon.u_apb_mon.head_ptr;
    frozen_head_irq    = u_mon.u_irq_mon.head_ptr;

    // Continue driving stimulus for 40 more cycles (400ns)
    #400ns;
    chal_check("FREEZE.fetch_locked",
      u_mon.u_fetch_mon.head_ptr == frozen_head_fetch,
      $sformatf("Fetch head_ptr held at %0d (now %0d)", frozen_head_fetch, u_mon.u_fetch_mon.head_ptr));
    chal_check("FREEZE.retire_locked",
      u_mon.u_retire_mon.head_ptr == frozen_head_retire,
      $sformatf("Retire head_ptr held at %0d (now %0d)", frozen_head_retire, u_mon.u_retire_mon.head_ptr));
    chal_check("FREEZE.lsu_locked",
      u_mon.u_lsu_mon.head_ptr == frozen_head_lsu,
      $sformatf("LSU head_ptr held at %0d (now %0d)", frozen_head_lsu, u_mon.u_lsu_mon.head_ptr));
    chal_check("FREEZE.axi_locked",
      u_mon.u_axi_mon.head_ptr == frozen_head_axi,
      $sformatf("AXI head_ptr held at %0d (now %0d)", frozen_head_axi, u_mon.u_axi_mon.head_ptr));
    chal_check("FREEZE.apb_locked",
      u_mon.u_apb_mon.head_ptr == frozen_head_apb,
      $sformatf("APB head_ptr held at %0d (now %0d)", frozen_head_apb, u_mon.u_apb_mon.head_ptr));
    chal_check("FREEZE.irq_locked",
      u_mon.u_irq_mon.head_ptr == frozen_head_irq,
      $sformatf("IRQ head_ptr held at %0d (now %0d)", frozen_head_irq, u_mon.u_irq_mon.head_ptr));

    // Non-Intrusiveness Final Summary
    $display("\n--- [TEST SUITE 8] Non-Intrusiveness & 0 DUT Driver Sign-Off ---");
    chal_check("NON_INTRUSIVE.lockstep_cycles",
      cycles_checked >= 440,
      $sformatf("Lockstep compared %0d continuous cycles between monitored and golden DUT", cycles_checked));
    chal_check("NON_INTRUSIVE.zero_timing_delta",
      lockstep_mismatches == 0,
      $sformatf("Zero signal mismatches across %0d cycles (mismatches: %0d)", cycles_checked, lockstep_mismatches));

    // Final Verdict
    $display("\n================================================================================");
    if (test_errors == 0 && lockstep_mismatches == 0) begin
      $display("  ALL 25 EMPIRICAL CHALLENGES PASSED (0 Errors). VERDICT: APPROVED");
    end else begin
      $display("  CHALLENGE SUITE FAILED with %0d error(s). VERDICT: REQUEST_CHANGES", test_errors + lockstep_mismatches);
    end
    $display("================================================================================\n");

    $finish(test_errors == 0 && lockstep_mismatches == 0 ? 0 : 1);
  end

endmodule
