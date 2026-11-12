`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: RISC_top
// Description: Top-Level SoC Integration Module with LED and 7-Segment Output
//////////////////////////////////////////////////////////////////////////////////

module RISC_top(
    input         rst,
    input         clk,
    output [15:0] leds,       // 16 On-board LEDs (lower 16-bits of a0)
    output [7:0]  anode,      // 7-segment display digit enables (AN0-AN7)
    output [6:0]  cathode     // 7-segment display segment lines (CA-CG)
);

    // =========================================================
    // MEMORY INTERCONNECT WIRES
    // =========================================================

    // Instruction Memory Bus
    wire [31:0] imem_addr;      // Full 32-bit instruction address
    wire [31:0] imem_rdata;     // Instruction read data

    // Data Memory Bus
    wire [31:0] dmem_addr;      // Full 32-bit data address
    wire [31:0] dmem_wdata;     // Aligned write data
    wire [31:0] dmem_rdata;     // Data read from memory
    wire        dmem_we;        // Data memory write enable
    wire [3:0]  dmem_strobe;    // Byte enable strobe

    // Register File a0 (x10) Output Wire
    wire [31:0] a0_val;

    // Connect lower 16 bits of a0 to the 16 LEDs
    assign leds = a0_val[15:0];

    // Clock divider for single-cycle CPU core (25 MHz = 40ns period)
    reg [1:0] clk_div = 2'b0;
    always @(posedge clk or posedge rst) begin
        if (rst) clk_div <= 2'b0;
        else     clk_div <= clk_div + 1'b1;
    end
    wire cpu_clk = clk_div[1];

    // =========================================================
    // CPU CORE INSTANTIATION
    // =========================================================

    rv32_core core (
        .clk         (cpu_clk),
        .rst         (rst),
        .imem_addr   (imem_addr),
        .imem_rdata  (imem_rdata),
        .dmem_addr   (dmem_addr),
        .dmem_wdata  (dmem_wdata),
        .dmem_rdata  (dmem_rdata),
        .dmem_we     (dmem_we),
        .dmem_strobe (dmem_strobe),
        .WE1         (WE1),
        .a0_val      (a0_val)
    );

    // =========================================================
    // INSTRUCTION MEMORY INSTANTIATION
    // =========================================================

    instruction_memory instruction_memory (
        .rst (rst),
        .A   (imem_addr[31:2]),
        .RD  (imem_rdata)
    );

    // =========================================================
    // DATA MEMORY INSTANTIATION
    // =========================================================

    data_memory data_memory (
        .clk   (cpu_clk),
        .rst   (rst),
        .WE    (dmem_we),
        .WD    (dmem_wdata),
        .A     (dmem_addr[31:2]),
        .RD    (dmem_rdata),
        .WSTRB (dmem_strobe)
    );

    // =========================================================
    // 7-SEGMENT DISPLAY CONTROLLER INSTANTIATION
    // =========================================================

    seven_seg_controller display_controller (
        .clk     (clk),
        .rst     (rst),
        .data_in (a0_val),
        .anode   (anode),
        .cathode (cathode)
    );

endmodule
