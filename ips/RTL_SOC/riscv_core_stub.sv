// =============================================================================
// RISCFORGE 1TOPS — RISC-V Core Stub (Hollow IP)
// =============================================================================
// Empty placeholder for the RISC-V core (RV32IM).
// Exposes:
//   - Instruction fetch port (OBI-like, read-only) → direct to ISRAM
//   - Data memory port (OBI-like, read/write) → direct to DSRAM
//   - AXI-Lite master interface → crossbar (for peripheral access)
//   - CLIC interrupt interface
//
// Replace this stub with the actual core implementation later.
// =============================================================================

module riscv_core_stub #(
  parameter int unsigned AXI_ADDR_WIDTH = 32,
  parameter int unsigned AXI_DATA_WIDTH = 32
)(
  input  logic                          clk_i,
  input  logic                          rst_ni,

  // =========================================================================
  // Instruction Fetch Port (OBI-like, read-only → ISRAM)
  // =========================================================================
  output logic                          instr_req_o,
  input  logic                          instr_gnt_i,
  output logic [31:0]                   instr_addr_o,
  input  logic [31:0]                   instr_rdata_i,
  input  logic                          instr_rvalid_i,

  // =========================================================================
  // Data Memory Port (OBI-like, read/write → DSRAM)
  // =========================================================================
  output logic                          data_req_o,
  input  logic                          data_gnt_i,
  output logic                          data_we_o,
  output logic [3:0]                    data_be_o,
  output logic [31:0]                   data_addr_o,
  output logic [31:0]                   data_wdata_o,
  input  logic [31:0]                   data_rdata_i,
  input  logic                          data_rvalid_i,

  // =========================================================================
  // AXI-Lite Master Interface (to crossbar — for peripheral access)
  // =========================================================================
  output logic [AXI_ADDR_WIDTH-1:0]     axi_aw_addr_o,
  output logic [2:0]                    axi_aw_prot_o,
  output logic                          axi_aw_valid_o,
  input  logic                          axi_aw_ready_i,
  output logic [AXI_DATA_WIDTH-1:0]     axi_w_data_o,
  output logic [AXI_DATA_WIDTH/8-1:0]   axi_w_strb_o,
  output logic                          axi_w_valid_o,
  input  logic                          axi_w_ready_i,
  input  logic [1:0]                    axi_b_resp_i,
  input  logic                          axi_b_valid_i,
  output logic                          axi_b_ready_o,
  output logic [AXI_ADDR_WIDTH-1:0]     axi_ar_addr_o,
  output logic [2:0]                    axi_ar_prot_o,
  output logic                          axi_ar_valid_o,
  input  logic                          axi_ar_ready_i,
  input  logic [AXI_DATA_WIDTH-1:0]     axi_r_data_i,
  input  logic [1:0]                    axi_r_resp_i,
  input  logic                          axi_r_valid_i,
  output logic                          axi_r_ready_o,

  // =========================================================================
  // Core Control
  // =========================================================================
  input  logic                          fetch_enable_i,
  input  logic [31:0]                   boot_addr_i,

  // =========================================================================
  // Interrupt Interface (from CLIC)
  // =========================================================================
  input  logic                          irq_valid_i,
  output logic                          irq_ready_o,
  input  logic [7:0]                    irq_id_i,
  input  logic [7:0]                    irq_level_i,
  input  logic                          irq_shv_i,
  input  logic [1:0]                    irq_priv_i,
  input  logic                          irq_kill_req_i,
  output logic                          irq_kill_ack_o
);

  // ===========================================================================
  // Stub — tie off all outputs to safe defaults
  // ===========================================================================

  // Instruction fetch: no requests
  assign instr_req_o    = 1'b0;
  assign instr_addr_o   = '0;

  // Data memory: no requests
  assign data_req_o     = 1'b0;
  assign data_we_o      = 1'b0;
  assign data_be_o      = '0;
  assign data_addr_o    = '0;
  assign data_wdata_o   = '0;

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

  // Interrupt: not acknowledging
  assign irq_ready_o    = 1'b0;
  assign irq_kill_ack_o = 1'b0;

endmodule
