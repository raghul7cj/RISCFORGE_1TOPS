// =============================================================================
// lsu_pkg.sv — Global types, enums and parameters for RV32I Load/Store Unit
// Tailored for the G0 core ls_unit (checklist/G0/rtl/ls_unit.v)
// =============================================================================
package lsu_pkg;

  // ── Operation Type (Load vs Store) ─────────────────────────────────────────
  typedef enum logic {
    LSU_LOAD  = 1'b0,
    LSU_STORE = 1'b1
  } lsu_op_e;

  // ── RV32I funct3 encodings for memory operations ───────────────────────────
  // (shared between loads and stores, so plain constants, not an enum —
  //  enum constants must be unique per type)
  localparam logic [2:0] F3_LB  = 3'b000,
                         F3_LH  = 3'b001,
                         F3_LW  = 3'b010,
                         F3_LBU = 3'b100,
                         F3_LHU = 3'b101,
                         F3_SB  = 3'b000,
                         F3_SH  = 3'b001,
                         F3_SW  = 3'b010;

  // ── Unified memory instruction enumeration ─────────────────────────────────
  typedef enum logic [3:0] {
    INSTR_LB  = 4'd0,  // Load Byte (Sign-Extended)
    INSTR_LH  = 4'd1,  // Load Halfword (Sign-Extended)
    INSTR_LW  = 4'd2,  // Load Word
    INSTR_LBU = 4'd3,  // Load Byte Unsigned (Zero-Extended)
    INSTR_LHU = 4'd4,  // Load Halfword Unsigned (Zero-Extended)
    INSTR_SB  = 4'd5,  // Store Byte
    INSTR_SH  = 4'd6,  // Store Halfword
    INSTR_SW  = 4'd7,  // Store Word
    INSTR_NOP = 4'd8   // Disabled / Idle
  } lsu_instr_e;

  // ── Memory response status ─────────────────────────────────────────────────
  typedef enum logic {
    RESP_OKAY  = 1'b0,
    RESP_ERROR = 1'b1
  } lsu_resp_e;

  // ── Global parameters ──────────────────────────────────────────────────────
  parameter int DATA_WIDTH = 32;
  parameter int ADDR_WIDTH = 32;

endpackage
