// =============================================================================
// lsu_if.sv — SystemVerilog Interface for RV32I Load/Store Unit (ls_unit)
// Encapsulates core pipeline interface and memory bridge interface.
// =============================================================================
interface lsu_if (input logic clk, input logic rst_n);
  import lsu_pkg::*;

  // ── 1. CORE PIPELINE INTERFACE ─────────────────────────────────────────────
  logic [31:0] core_addr;   // Effective address from ALU
  logic [31:0] core_wdata;  // Store data from RS2
  logic [4:0]  lsunit;      // Control bus: [4]=en, [3]=is_store, [2:0]=funct3
  logic [31:0] core_rdata;  // Formatted load result to WB stage
  logic        core_stall;  // Pipeline freeze signal
  logic        core_err;    // Access fault signal to trap logic

  // ── 2. MEMORY BRIDGE INTERFACE ─────────────────────────────────────────────
  logic        mem_req;     // Valid request this cycle
  logic        mem_we;      // Write enable
  logic [31:0] mem_addr;    // Byte address to memory
  logic [31:0] mem_wdata;   // Aligned write data
  logic [3:0]  mem_be;      // Active-high byte enables
  logic [31:0] mem_rdata;   // Read data returning from memory
  logic        mem_stall;   // Pipeline stall request from memory
  logic        mem_err;     // Access fault from memory

  // ── Driver Clocking Block ──────────────────────────────────────────────────
  clocking driver_cb @(posedge clk);
    default input #1step output #1ns;
    // Core pipeline drivers
    output core_addr;
    output core_wdata;
    output lsunit;

    // Memory bridge response drivers
    output mem_rdata;
    output mem_stall;
    output mem_err;

    // Observable DUT outputs
    input  mem_req;
    input  mem_we;
    input  mem_addr;
    input  mem_wdata;
    input  mem_be;
    input  core_rdata;
    input  core_stall;
    input  core_err;
  endclocking

  // ── Monitor Clocking Block ─────────────────────────────────────────────────
  clocking monitor_cb @(posedge clk);
    default input #1step;
    input core_addr;
    input core_wdata;
    input lsunit;
    input core_rdata;
    input core_stall;
    input core_err;
    input mem_req;
    input mem_we;
    input mem_addr;
    input mem_wdata;
    input mem_be;
    input mem_rdata;
    input mem_stall;
    input mem_err;
  endclocking

  modport driver_mp  (clocking driver_cb,  input clk, input rst_n);
  modport monitor_mp (clocking monitor_cb, input clk, input rst_n);

endinterface
