// =============================================================================
// RISCFORGE 1TOPS — Single-Port SRAM (Behavioral Model)
// =============================================================================
// Synchronous single-port SRAM for simulation.
// Replace with TSMC / foundry hard macro for tapeout.
//
// Interface uses active-high control signals (cs_i, we_i, wmask_i).
// Invert these when wrapping a TSMC macro (which typically uses
// active-low CSn, WEn, BWEBn).
//
// Timing:
//   Read:  Present addr + cs on cycle N → rdata valid on cycle N+1
//   Write: Present addr + cs + we + wdata + wmask on cycle N → written at posedge
//   Concurrent: Read-first — during a write, rdata_o reflects the pre-write value
// =============================================================================

module sram_sp #(
  parameter int unsigned NUM_WORDS  = 1024,
  parameter int unsigned DATA_WIDTH = 32,
  // Derived — do not override
  localparam int unsigned ADDR_WIDTH = $clog2(NUM_WORDS),
  localparam int unsigned BYTE_WIDTH = DATA_WIDTH / 8
)(
  input  logic                    clk_i,
  input  logic                    cs_i,      // chip select (active high)
  input  logic                    we_i,      // write enable (active high, valid when cs_i=1)
  input  logic [ADDR_WIDTH-1:0]  addr_i,    // word address
  input  logic [DATA_WIDTH-1:0]  wdata_i,   // write data
  input  logic [BYTE_WIDTH-1:0]  wmask_i,   // byte write mask (active high)
  output logic [DATA_WIDTH-1:0]  rdata_o    // read data (1-cycle latency, registered)
);

  // -------------------------------------------------------------------------
  // Memory array
  // -------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] mem [0:NUM_WORDS-1];

  // -------------------------------------------------------------------------
  // Synchronous read / write (read-first)
  // -------------------------------------------------------------------------
  always @(posedge clk_i) begin
    if (cs_i) begin
      // Read: output reflects value BEFORE any write this cycle
      rdata_o <= mem[addr_i];
      // Write: byte-masked
      if (we_i) begin
        for (int unsigned b = 0; b < BYTE_WIDTH; b++) begin
          if (wmask_i[b])
            mem[addr_i][b*8 +: 8] <= wdata_i[b*8 +: 8];
        end
      end
    end
  end

endmodule
