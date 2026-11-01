// =============================================================================
// RISCFORGE 1TOPS — End-to-End MMIO Path Scoreboard (mmio_path_scoreboard.sv)
// =============================================================================

`timescale 1ns/1ps

module mmio_path_scoreboard import tb_pkg::*; #(
  parameter int unsigned NUM_SLOTS = 6
)(
  input logic                 clk,
  input logic                 rst_n,

  // Core LSU Access Port
  input logic                 lsu_req,
  input logic                 lsu_we,
  input logic [31:0]          lsu_addr,
  input logic [31:0]          lsu_wdata,
  input logic [3:0]           lsu_be,
  input logic                 lsu_stall,

  // APB Peripheral Port
  input logic [31:0]          paddr,
  input logic [NUM_SLOTS-1:0] psel,
  input logic                 penable,
  input logic                 pwrite,
  input logic [31:0]          pwdata,
  input logic [NUM_SLOTS-1:0] pready
);

  // Address map decoder helper function
  function automatic int get_expected_apb_slot(logic [31:0] addr);
    if ((addr >= 32'h4000_0000) && (addr < 32'h4000_1000)) return 0; // I2C
    if ((addr >= 32'h4000_1000) && (addr < 32'h4000_2000)) return 1; // Timer 0
    if ((addr >= 32'h4000_2000) && (addr < 32'h4000_3000)) return 2; // UART
    if ((addr >= 32'h4000_3000) && (addr < 32'h4000_4000)) return 3; // GPIO
    if ((addr >= 32'h4000_4000) && (addr < 32'h4000_5000)) return 4; // SPI
    if ((addr >= 32'h4000_5000) && (addr < 32'h4000_6000)) return 5; // Timer 1
    return -1; // Out of range
  endfunction

  // Check path on completed APB transaction
  always @(posedge clk) begin
    if (rst_n) begin
      for (int s = 0; s < NUM_SLOTS; s++) begin
        if (psel[s] && penable && pready[s]) begin
          int exp_slot;
          exp_slot = get_expected_apb_slot(paddr);
          if (exp_slot != s) begin
            $error("[SCOREBOARD-PATH-01] MMIO Address 0x%08X decoded to slot %0d, expected slot %0d",
                   paddr, s, exp_slot);
          end
        end
      end
    end
  end

endmodule
