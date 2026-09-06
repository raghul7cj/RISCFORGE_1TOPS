// =============================================================================
// RISCFORGE 1TOPS — Instruction Memory SRAM Wrapper
// =============================================================================
// Thin adapter that converts the sram_sp-compatible interface (as output by
// sram_mux) into the Instruction_Memory_new native interface.
//
// The sram_mux provides a local word address (SRAM_ADDR_WIDTH bits).
// Instruction_Memory_new expects a 30-bit absolute word address and does
// its own base-address subtraction internally. This wrapper reconstructs
// the absolute address by adding IMEM_BASE_WORD to the local address.
//
// Interface mapping:
//   sram_mux output     →  this wrapper  →  Instruction_Memory_new
//   ────────────────────────────────────────────────────────────────
//   sram_cs_o   → cs_i    → sram_en
//   sram_we_o   → we_i    → sram_we
//   sram_wmask_o→ wmask_i → sram_wmask
//   sram_addr_o → addr_i  → sram_addr  (local → 30-bit absolute)
//   sram_wdata_o→ wdata_i → sram_wdata
//   sram_rdata_i← rdata_o ← sram_rdata
// =============================================================================

module imem_sram_wrapper #(
  parameter int unsigned NUM_WORDS      = 1024,
  parameter int unsigned DATA_WIDTH     = 32,
  parameter [31:0]       IMEM_BASE_BYTE = 32'h0000_0000,
  // Derived — do not override
  localparam int unsigned ADDR_WIDTH    = $clog2(NUM_WORDS),
  localparam int unsigned BYTE_WIDTH    = DATA_WIDTH / 8
)(
  input  logic                    clk_i,
  input  logic                    rst_ni,

  // sram_sp-compatible interface (from sram_mux)
  input  logic                    cs_i,
  input  logic                    we_i,
  input  logic [ADDR_WIDTH-1:0]  addr_i,
  input  logic [DATA_WIDTH-1:0]  wdata_i,
  input  logic [BYTE_WIDTH-1:0]  wmask_i,
  output logic [DATA_WIDTH-1:0]  rdata_o
);

  // -------------------------------------------------------------------------
  // Address reconstruction
  // -------------------------------------------------------------------------
  // Instruction_Memory_new expects a 30-bit word address (byte_addr[31:2]).
  // The sram_mux provides a local word offset (ADDR_WIDTH bits).
  // Reconstruct the absolute 30-bit word address:
  //   absolute_word_addr = IMEM_BASE_WORD + local_word_addr

  localparam [29:0] IMEM_BASE_WORD = IMEM_BASE_BYTE[31:2];

  wire [29:0] absolute_word_addr = IMEM_BASE_WORD + {{(30-ADDR_WIDTH){1'b0}}, addr_i};

  // -------------------------------------------------------------------------
  // Instruction_Memory_new instantiation
  // -------------------------------------------------------------------------
  Instruction_Memory_new #(
    .MEM_DEPTH      ( NUM_WORDS      ),
    .IMEM_BASE_BYTE ( IMEM_BASE_BYTE )
  ) u_imem (
    .clk       ( clk_i              ),
    .rst_n     ( rst_ni             ),
    .sram_en   ( cs_i               ),
    .sram_we   ( we_i               ),
    .sram_wmask( wmask_i[3:0]       ),
    .sram_addr ( absolute_word_addr ),
    .sram_wdata( wdata_i            ),
    .sram_rdata( rdata_o            )
  );

endmodule
