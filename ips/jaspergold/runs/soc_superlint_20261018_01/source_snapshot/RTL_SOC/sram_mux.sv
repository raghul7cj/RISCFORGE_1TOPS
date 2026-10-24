// =============================================================================
// RISCFORGE 1TOPS — SRAM 2:1 Priority Mux / Demux
// =============================================================================
// Multiplexes two requester ports onto a single-port SRAM.
//
// Port 0 (core) has fixed priority over Port 1 (AXI bridge).
// On contention:
//   - Port 0 is granted, SRAM serves Port 0 this cycle
//   - Port 1 is stalled (gnt = 0), retries on the next cycle
//
// Read-data demux:
//   SRAM rdata is broadcast to both ports, but rvalid is asserted only
//   to the port that was granted in the previous cycle (matching the
//   SRAM's 1-cycle read latency).
//
// Contention note:
//   Port 1 (AXI bridge) is only ever active while port 0 is idle. The ISRAM
//   instance relies on the core being held in reset during boot, and on the
//   ISRAM AXI bridge rejecting transactions once boot completes; the DSRAM
//   instance relies on core data requests being intermittent. Neither port
//   therefore needs anti-starvation logic.
// =============================================================================

module sram_mux #(
  parameter int unsigned ADDR_WIDTH = 10,
  parameter int unsigned DATA_WIDTH = 32,
  // Derived — do not override
  localparam int unsigned BYTE_WIDTH = DATA_WIDTH / 8
)(
  input  logic clk_i,
  input  logic rst_ni,

  // -------------------------------------------------------------------------
  // Port 0 — Core (high priority)
  // -------------------------------------------------------------------------
  input  logic                    port0_req_i,
  output logic                    port0_gnt_o,
  input  logic                    port0_we_i,
  input  logic [ADDR_WIDTH-1:0]  port0_addr_i,
  input  logic [DATA_WIDTH-1:0]  port0_wdata_i,
  input  logic [BYTE_WIDTH-1:0]  port0_be_i,
  output logic [DATA_WIDTH-1:0]  port0_rdata_o,
  output logic                    port0_rvalid_o,

  // -------------------------------------------------------------------------
  // Port 1 — AXI bridge (low priority)
  // -------------------------------------------------------------------------
  input  logic                    port1_req_i,
  output logic                    port1_gnt_o,
  input  logic                    port1_we_i,
  input  logic [ADDR_WIDTH-1:0]  port1_addr_i,
  input  logic [DATA_WIDTH-1:0]  port1_wdata_i,
  input  logic [BYTE_WIDTH-1:0]  port1_be_i,
  output logic [DATA_WIDTH-1:0]  port1_rdata_o,
  output logic                    port1_rvalid_o,

  // -------------------------------------------------------------------------
  // SRAM interface (active-high chip select)
  // -------------------------------------------------------------------------
  output logic                    sram_cs_o,
  output logic                    sram_we_o,
  output logic [ADDR_WIDTH-1:0]  sram_addr_o,
  output logic [DATA_WIDTH-1:0]  sram_wdata_o,
  output logic [BYTE_WIDTH-1:0]  sram_wmask_o,
  input  logic [DATA_WIDTH-1:0]  sram_rdata_i
);

  // -------------------------------------------------------------------------
  // Grant history — 1-cycle delayed for rdata / rvalid routing
  // -------------------------------------------------------------------------
  logic port0_granted_q, port1_granted_q;

  // -------------------------------------------------------------------------
  // Input Mux (combinational) — priority: port 0 > port 1
  // -------------------------------------------------------------------------
  always_comb begin
    // Defaults — SRAM idle
    port0_gnt_o  = 1'b0;
    port1_gnt_o  = 1'b0;
    sram_cs_o    = 1'b0;
    sram_we_o    = 1'b0;
    sram_addr_o  = '0;
    sram_wdata_o = '0;
    sram_wmask_o = '0;

    if (port0_req_i) begin
      // Core has priority — always granted when requesting
      port0_gnt_o  = 1'b1;
      sram_cs_o    = 1'b1;
      sram_we_o    = port0_we_i;
      sram_addr_o  = port0_addr_i;
      sram_wdata_o = port0_wdata_i;
      sram_wmask_o = port0_be_i;
    end else if (port1_req_i) begin
      // AXI bridge — granted only when core is idle
      port1_gnt_o  = 1'b1;
      sram_cs_o    = 1'b1;
      sram_we_o    = port1_we_i;
      sram_addr_o  = port1_addr_i;
      sram_wdata_o = port1_wdata_i;
      sram_wmask_o = port1_be_i;
    end
  end

  // -------------------------------------------------------------------------
  // Grant pipeline register (tracks who was granted for rdata routing)
  // -------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      port0_granted_q <= 1'b0;
      port1_granted_q <= 1'b0;
    end else begin
      port0_granted_q <= port0_gnt_o;
      port1_granted_q <= port1_gnt_o;
    end
  end

  // -------------------------------------------------------------------------
  // Output Demux — route rdata to the previously-granted port
  // rdata is broadcast; only rvalid is port-specific.
  // -------------------------------------------------------------------------
  assign port0_rdata_o  = sram_rdata_i;
  assign port0_rvalid_o = port0_granted_q;

  assign port1_rdata_o  = sram_rdata_i;
  assign port1_rvalid_o = port1_granted_q;

endmodule
