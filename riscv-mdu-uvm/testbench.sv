// =============================================================================
// File: testbench.sv
// Description: Top-Level UVM Testbench for RV32M Coprocessor Unit
// =============================================================================
`timescale 1ns / 1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

// ── Testbench Class & Interface Definitions ──────────────────────────────────
`include "interface.sv"
`include "seq_item.sv"
`include "sequence.sv"
`include "sequencer.sv"
`include "driver.sv"
`include "monitor.sv"
`include "scoreboard.sv"
`include "coverage.sv"
`include "agent.sv"
`include "env.sv"
`include "rand_test.sv"
`include "rv32m_assertions.sv"

module tb;

    // ── Clock & Reset Signals ────────────────────────────────────────────────
    logic clk;
    logic rst_n;

    // 100 MHz Clock Generator (10ns period)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Asynchronous Active-Low Reset Initialization
    initial begin
        rst_n = 1'b0;
        #25;
        @(negedge clk);
        rst_n = 1'b1;
    end

    // ── Interface Instance ───────────────────────────────────────────────────
    rv32m_if vif (.clk(clk), .rst_n(rst_n));

    // ── Device Under Test (DUT: rv32m_unit) ──────────────────────────────────
    rv32m_unit dut (
        .clk       (vif.clk),
        .rst_n     (vif.rst_n),
        .rs1       (vif.rs1),
        .rs2       (vif.rs2),
        .funct3    (vif.funct3),
        .rd_in     (vif.rd_in),
        .valid_in  (vif.valid_in),
        .stall     (vif.stall),
        .result    (vif.result),
        .rd_out    (vif.rd_out),
        .valid_out (vif.valid_out)
    );

    // ── UVM Setup & Test Launch ──────────────────────────────────────────────
    initial begin
        // Set virtual interface in config_db for both generic and specific paths
        uvm_config_db#(virtual rv32m_if)::set(null, "*", "vif", vif);

        // Command-line override (+UVM_TESTNAME=...) or default to rv32m_rand_test
        run_test("rv32m_rand_test");
    end

    // ── Waveform Dump ────────────────────────────────────────────────────────
    initial begin
        if ($test$plusargs("DUMP_VCD")) begin
            $dumpfile("rv32m_uvm.vcd");
            $dumpvars(0, tb);
        end
    end

endmodule : tb
