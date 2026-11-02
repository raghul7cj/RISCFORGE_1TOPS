// =============================================================================
// RISCFORGE 1TOPS — Instruction Fetch Address Demux
// =============================================================================
// Routes the RISC-V core's instruction fetch requests to either:
//   - BootROM (when address is in BootROM range)
//   - ISRAM   (when address is in ISRAM range, via sram_mux port 0)
//
// BootROM accesses are always granted immediately (no contention — core
// is the sole accessor). ISRAM accesses are subject to sram_mux
// arbitration (core vs. AXI bridge).
//
// Address decoding uses a simple range check:
//   BootROM range:  BOOTROM_BASE to BOOTROM_BASE + (BOOTROM_NUM_WORDS × 4) - 1
//   ISRAM range:    ISRAM_BASE   to ISRAM_BASE   + (ISRAM_NUM_WORDS × 4) - 1
//   Addresses outside both ranges: gnt deasserted, no rvalid.
//
// Read-data mux:
//   Uses a 1-cycle pipeline register to track which target was accessed,
//   then routes the correct rdata and rvalid back to the core on the
//   following cycle (matching SRAM/ROM 1-cycle read latency).
// =============================================================================

module instr_fetch_demux #(
  parameter int unsigned BOOTROM_NUM_WORDS = 16,
  parameter int unsigned ISRAM_NUM_WORDS   = 8192,
  parameter [31:0]       BOOTROM_BASE      = 32'h0000_0000,
  parameter [31:0]       ISRAM_BASE        = 32'h0001_0000,
  // Core reset vector. Must match the core's RESET_PC. Used only to pick the
  // reset state of the read-data mux — see rom_accessed_q below.
  parameter [31:0]       RESET_PC          = 32'h0000_0000,
  // Derived — do not override
  localparam int unsigned BOOTROM_ADDR_WIDTH = $clog2(BOOTROM_NUM_WORDS),
  localparam int unsigned ISRAM_ADDR_WIDTH   = $clog2(ISRAM_NUM_WORDS),
  localparam int unsigned BYTE_OFFSET        = 2  // log2(32/8)
)(
  input  logic        clk_i,
  input  logic        rst_ni,

  // -------------------------------------------------------------------------
  // Core fetch port (upstream — from RISC-V core)
  // -------------------------------------------------------------------------
  input  logic        core_req_i,
  output logic        core_gnt_o,
  input  logic [31:0] core_addr_i,
  output logic [31:0] core_rdata_o,
  output logic        core_rvalid_o,

  // -------------------------------------------------------------------------
  // BootROM port (downstream — directly to boot_rom)
  // -------------------------------------------------------------------------
  output logic                           rom_cs_o,
  output logic [BOOTROM_ADDR_WIDTH-1:0]  rom_addr_o,
  input  logic [31:0]                    rom_rdata_i,

  // -------------------------------------------------------------------------
  // ISRAM mux port 0 (downstream — to sram_mux)
  // -------------------------------------------------------------------------
  output logic        isram_req_o,
  input  logic        isram_gnt_i,
  output logic [31:0] isram_addr_o,
  input  logic [31:0] isram_rdata_i,
  input  logic        isram_rvalid_i
);

  // -------------------------------------------------------------------------
  // Address decode — range comparison
  // -------------------------------------------------------------------------
  localparam [31:0] BOOTROM_END = BOOTROM_BASE + (BOOTROM_NUM_WORDS * 4);
  localparam [31:0] ISRAM_END   = ISRAM_BASE   + (ISRAM_NUM_WORDS * 4);

  logic sel_rom, sel_isram;

  assign sel_rom   = (core_addr_i >= BOOTROM_BASE) && (core_addr_i < BOOTROM_END);
  assign sel_isram = (core_addr_i >= ISRAM_BASE)   && (core_addr_i < ISRAM_END);

  // -------------------------------------------------------------------------
  // Request routing (combinational)
  // -------------------------------------------------------------------------
  // BootROM: always granted when selected (no contention, core-only access)
  // ISRAM:   grant depends on sram_mux arbitration

  assign rom_cs_o   = core_req_i & sel_rom;
  assign rom_addr_o = core_addr_i[BYTE_OFFSET +: BOOTROM_ADDR_WIDTH];

  assign isram_req_o  = core_req_i & sel_isram;
  assign isram_addr_o = core_addr_i;  // pass full address; SoC extracts word bits

  // Grant: ROM always grants, ISRAM depends on mux
  assign core_gnt_o = (core_req_i & sel_rom)         |
                      (isram_req_o & isram_gnt_i);

  // -------------------------------------------------------------------------
  // Response routing — 1-cycle pipeline (tracks which target was accessed)
  // -------------------------------------------------------------------------
  logic rom_accessed_q;

  // Reset value must name whichever memory the reset-vector fetch targets.
  //
  // Both memories reset their internal address register to 0 and therefore
  // present word 0 combinationally out of reset — imem_controller depends on
  // that ("no startup bubble needed", imem_controller.v:25-30). But this mux
  // decides WHICH of the two the core actually sees, and it is a register: on
  // the first cycle after reset it still holds its reset value, not a decode
  // of the current address.
  //
  // Resetting it to 0 therefore routed ISRAM data on the very first fetch even
  // though RESET_PC points into the BootROM — silently discarding the word at
  // the reset vector. That cost the first ROM instruction (the `lui` that sets
  // sp), while the second (`jal`) ran normally, which is exactly the "jumped to
  // ISRAM but sp never initialised" symptom.
  localparam bit RESET_TARGETS_ROM =
      (RESET_PC >= BOOTROM_BASE) && (RESET_PC < BOOTROM_END);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rom_accessed_q <= RESET_TARGETS_ROM;
    end else begin
      rom_accessed_q <= core_req_i & sel_rom;
    end
  end

  // Mux rdata: BootROM if ROM was accessed, else ISRAM
  assign core_rdata_o = rom_accessed_q ? rom_rdata_i : isram_rdata_i;

  // Mux rvalid: ROM has guaranteed 1-cycle latency after cs,
  //             ISRAM rvalid comes from sram_mux (1-cycle after gnt)
  assign core_rvalid_o = rom_accessed_q | isram_rvalid_i;

endmodule
