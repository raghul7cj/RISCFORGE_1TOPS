// =============================================================================
// RISCFORGE 1TOPS — Bootloader Stub (Hollow IP)
// =============================================================================
// This is an empty placeholder module for the Boot Controller.
// It exposes the correct AXI-Lite master interface, boot control,
// and SPI flash interface so the SoC subsystem can be elaborated.
//
// In the full design the bootloader:
//   1. Drives the SPI master to fetch instructions from external SPI flash
//   2. Writes them into Instruction SRAM via the AXI-Lite crossbar
//   3. Asserts boot_done_o and releases the RISC-V core
//
// Replace this stub with the actual bootloader FSM later.
// =============================================================================

module bootloader_stub #(
  parameter int unsigned AXI_ADDR_WIDTH = 32,
  parameter int unsigned AXI_DATA_WIDTH = 32
)(
  input  logic                          clk_i,
  input  logic                          rst_ni,

  // =========================================================================
  // AXI-Lite Master Interface (to crossbar slave port)
  // =========================================================================

  // -- Write Address Channel (AW) --
  output logic [AXI_ADDR_WIDTH-1:0]     axi_aw_addr_o,
  output logic [2:0]                    axi_aw_prot_o,
  output logic                          axi_aw_valid_o,
  input  logic                          axi_aw_ready_i,

  // -- Write Data Channel (W) --
  output logic [AXI_DATA_WIDTH-1:0]     axi_w_data_o,
  output logic [AXI_DATA_WIDTH/8-1:0]   axi_w_strb_o,
  output logic                          axi_w_valid_o,
  input  logic                          axi_w_ready_i,

  // -- Write Response Channel (B) --
  input  logic [1:0]                    axi_b_resp_i,
  input  logic                          axi_b_valid_i,
  output logic                          axi_b_ready_o,

  // -- Read Address Channel (AR) --
  output logic [AXI_ADDR_WIDTH-1:0]     axi_ar_addr_o,
  output logic [2:0]                    axi_ar_prot_o,
  output logic                          axi_ar_valid_o,
  input  logic                          axi_ar_ready_i,

  // -- Read Data Channel (R) --
  input  logic [AXI_DATA_WIDTH-1:0]     axi_r_data_i,
  input  logic [1:0]                    axi_r_resp_i,
  input  logic                          axi_r_valid_i,
  output logic                          axi_r_ready_o,

  // =========================================================================
  // Boot Control
  // =========================================================================
  output logic                          boot_done_o,

  // =========================================================================
  // SPI Flash Interface (direct external connection for boot-time fetch)
  // =========================================================================
  output logic                          spi_clk_o,
  output logic                          spi_csn_o,
  output logic [3:0]                    spi_sdo_o,
  input  logic [3:0]                    spi_sdi_i,
  output logic [1:0]                    spi_mode_o
);

  // ===========================================================================
  // Stub — tie off all outputs to safe defaults
  // ===========================================================================

  // AXI-Lite master: no transactions
  assign axi_aw_addr_o  = '0;
  assign axi_aw_prot_o  = '0;
  assign axi_aw_valid_o = 1'b0;

  assign axi_w_data_o   = '0;
  assign axi_w_strb_o   = '0;
  assign axi_w_valid_o  = 1'b0;

  assign axi_b_ready_o  = 1'b0;

  assign axi_ar_addr_o  = '0;
  assign axi_ar_prot_o  = '0;
  assign axi_ar_valid_o = 1'b0;

  assign axi_r_ready_o  = 1'b0;

  // Boot control: not done
  assign boot_done_o    = 1'b0;

  // SPI: idle
  assign spi_clk_o      = 1'b0;
  assign spi_csn_o      = 1'b1;  // chip-select deasserted (active low)
  assign spi_sdo_o      = '0;
  assign spi_mode_o     = '0;

endmodule
