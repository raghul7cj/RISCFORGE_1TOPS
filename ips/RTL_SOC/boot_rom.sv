// =============================================================================
// RISCFORGE 1TOPS — Boot ROM
// =============================================================================
// Small read-only memory holding the initial boot code, loaded from a hex
// image at elaboration. The stock image is two instructions:
//
//   0x0000_0000  00028137   lui x2, 0x28     -> sp = 0x0002_8000 (top of DSRAM)
//   0x0000_0004  7FD0F06F   jal x0, +0xFFFC  -> 0x0001_0000      (ISRAM base)
//
// This ROM is directly accessible by the RISC-V core only (not on the
// AXI-Lite crossbar). The core's instruction fetch demux routes fetches
// to this ROM when the address falls in the BootROM range.
//
// Timing:
//   Read: Present addr + cs on cycle N → rdata valid on cycle N+1
//   (Same 1-cycle latency as sram_sp / Instruction_Memory_new)
//
// Reset behaviour — IMPORTANT:
//   imem_controller assumes the instruction memory already presents mem[0] on
//   the FIRST cycle out of reset, so no startup bubble is needed (see its
//   "Startup correctness" note). That only holds if the address register — not
//   the data output — is what gets reset. Registering rdata_o directly would
//   leave it undriven through reset (cs_i is low while the core is held in
//   reset), so the word at 0x0000_0000 would be read as X and skipped, and the
//   stack-pointer init above would never execute.
//
//   Hence: registered address + combinational array read, matching
//   Instruction_Memory_new (Instruction_Memory.v).
// =============================================================================

module boot_rom #(
  parameter int unsigned NUM_WORDS  = 16,
  parameter int unsigned DATA_WIDTH = 32,
  // Hex image loaded into the ROM. Overridable so testbenches can supply
  // their own boot sequence.
  parameter string       HEX_FILE   = "../mem_files/riscforge_bootrom.hex",
  // Derived — do not override
  localparam int unsigned ADDR_WIDTH = $clog2(NUM_WORDS)
)(
  input  logic                    clk_i,
  input  logic                    rst_ni,    // active-low (core reset domain)
  input  logic                    cs_i,      // chip select (active high)
  input  logic [ADDR_WIDTH-1:0]  addr_i,    // word address
  output logic [DATA_WIDTH-1:0]  rdata_o    // read data (1-cycle latency)
);

  // -------------------------------------------------------------------------
  // ROM array
  // -------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] mem [0:NUM_WORDS-1];

  // -------------------------------------------------------------------------
  // NOP-fill first so words beyond the image are defined (not X), then load
  // the boot image over the top. Same pattern as Instruction_Memory.v.
  // -------------------------------------------------------------------------
  initial begin : init_rom
    mem[0] = 32'h0002_8137;  // lui x2, 0x28  (sp = 0x0002_8000 top of DSRAM)
    mem[1] = 32'h7FD0_F06F;  // jal x0, +0xFFFC -> 0x0001_0000 (ISRAM base)
    for (int i = 2; i < NUM_WORDS; i++) begin
      mem[i] = 32'h0000_0013;  // NOP (ADDI x0, x0, 0)
    end
    $readmemh(HEX_FILE, mem);
  end

  // -------------------------------------------------------------------------
  // Registered address + combinational read (1-cycle latency).
  // raddr_q resets to 0, so rdata_o presents mem[0] immediately out of reset.
  // -------------------------------------------------------------------------
  logic [ADDR_WIDTH-1:0] raddr_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)   raddr_q <= '0;
    else if (cs_i) raddr_q <= addr_i;
  end

  assign rdata_o = mem[raddr_q];

endmodule
