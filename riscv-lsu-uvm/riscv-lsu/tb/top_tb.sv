// =============================================================================
// top_tb.sv — Top-level testbench for RV32I Load/Store Unit (ls_unit)
// Instantiates DUT (ls_unit.v), interface, assertions, and kicks off UVM.
// =============================================================================
`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

// ── Package first (all TB files are `include`d here; run_xrun.sh compiles
//    only this file plus the DUT) ─────────────────────────────────────────────
`include "lsu_pkg.sv"

// ── Testbench components (order matters — dependencies first) ─────────────────
`include "lsu_if.sv"
`include "lsu_transaction.sv"
`include "lsu_driver.sv"
`include "lsu_monitor.sv"
`include "lsu_scoreboard.sv"
`include "lsu_coverage.sv"
`include "lsu_sequences.sv"
`include "lsu_agent.sv"
`include "lsu_env.sv"
`include "lsu_tests.sv"
`include "lsu_assertions.sv"

module top_tb;

  // ── Clock and Reset Generation ─────────────────────────────────────────────
  logic clk;
  logic rst_n;

  initial clk = 1'b0;
  always #5 clk = ~clk; // 100 MHz

  initial begin
    rst_n = 1'b0;
    repeat (8) @(posedge clk);
    rst_n = 1'b1;
  end

  // ── SystemVerilog Interface Instance ───────────────────────────────────────
  lsu_if dut_if (.clk(clk), .rst_n(rst_n));

  // ── User's RV32I ls_unit DUT Instance ──────────────────────────────────────
  ls_unit u_lsu (
    // 1. Core Pipeline Interface
    .core_addr   (dut_if.core_addr),
    .core_wdata  (dut_if.core_wdata),
    .lsunit      (dut_if.lsunit),
    .core_rdata  (dut_if.core_rdata),
    .core_stall  (dut_if.core_stall),
    .core_err    (dut_if.core_err),

    // 2. Memory Bridge Interface
    .mem_req     (dut_if.mem_req),
    .mem_we      (dut_if.mem_we),
    .mem_addr    (dut_if.mem_addr),
    .mem_wdata   (dut_if.mem_wdata),
    .mem_be      (dut_if.mem_be),
    .mem_rdata   (dut_if.mem_rdata),
    .mem_stall   (dut_if.mem_stall),
    .mem_err     (dut_if.mem_err)
  );

  // ── SVA Protocol & Invariant Assertions ────────────────────────────────────
  lsu_assertions u_assert (
    .clk         (clk),
    .rst_n       (rst_n),
    .core_addr   (dut_if.core_addr),
    .core_wdata  (dut_if.core_wdata),
    .lsunit      (dut_if.lsunit),
    .core_rdata  (dut_if.core_rdata),
    .core_stall  (dut_if.core_stall),
    .core_err    (dut_if.core_err),
    .mem_req     (dut_if.mem_req),
    .mem_we      (dut_if.mem_we),
    .mem_addr    (dut_if.mem_addr),
    .mem_wdata   (dut_if.mem_wdata),
    .mem_be      (dut_if.mem_be),
    .mem_rdata   (dut_if.mem_rdata),
    .mem_stall   (dut_if.mem_stall),
    .mem_err     (dut_if.mem_err)
  );

  // ── UVM Kickoff ────────────────────────────────────────────────────────────
  initial begin
    uvm_config_db #(virtual lsu_if)::set(
      null, "uvm_test_top.*", "vif", dut_if);
    run_test(); // Test selected via +UVM_TESTNAME=<name>
  end

  // ── Simulation Watchdog Guard ──────────────────────────────────────────────
  initial begin
    #2_000_000;
    `uvm_fatal("TOP", "Simulation watchdog timeout — check for deadlock")
  end

endmodule
