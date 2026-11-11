// =============================================================================
// File: interface.sv
// Description: SystemVerilog interface for RV32M Coprocessor Unit (rv32m_unit)
// =============================================================================
`ifndef RV32M_IF_SV
`define RV32M_IF_SV

interface rv32m_if (input logic clk, input logic rst_n);

    // ── Core -> M-Extension Coprocessor (Issue Interface) ───────────────────
    logic [31:0] rs1;
    logic [31:0] rs2;
    logic [2:0]  funct3;
    logic [4:0]  rd_in;
    logic        valid_in;

    // ── M-Extension Coprocessor -> Pipeline Control ─────────────────────────
    logic        stall;

    // ── M-Extension Coprocessor -> Core (Writeback Interface) ───────────────
    logic [31:0] result;
    logic [4:0]  rd_out;
    logic        valid_out;

    // ── Driver Clocking Block (skew-controlled synchronous driving) ─────────
    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        output rs1;
        output rs2;
        output funct3;
        output rd_in;
        output valid_in;
        input  stall;
        input  valid_out;
        input  result;
        input  rd_out;
    endclocking

    // ── Monitor Clocking Block (skew-controlled synchronous sampling) ───────
    clocking mon_cb @(posedge clk);
        default input #1step;
        input rs1;
        input rs2;
        input funct3;
        input rd_in;
        input valid_in;
        input stall;
        input valid_out;
        input result;
        input rd_out;
    endclocking

    // ── Modports ────────────────────────────────────────────────────────────
    modport drv_mp (clocking drv_cb, input clk, input rst_n);
    modport mon_mp (clocking mon_cb, input clk, input rst_n);

endinterface : rv32m_if

// Backward-compatible alias for template consistency
`define intf rv32m_if

`endif // RV32M_IF_SV
