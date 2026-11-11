// =============================================================================
// lsu_transaction.sv — Sequence Item for RV32I Load/Store Unit
// Models memory transactions (LB, LH, LW, LBU, LHU, SB, SH, SW, NOP)
// =============================================================================

import lsu_pkg::*;

class lsu_transaction extends uvm_sequence_item;
  import lsu_pkg::*;

  // ── Randomised Generation Fields ───────────────────────────────────────────
  rand lsu_instr_e            instr;
  rand logic [ADDR_WIDTH-1:0] addr;
  rand logic [DATA_WIDTH-1:0] wdata;
  rand logic [DATA_WIDTH-1:0] rdata;        // Simulated memory read content
  rand int unsigned           stall_cycles; // Memory bridge stall duration
  rand lsu_resp_e             resp;         // Memory access status (OKAY/ERROR)

  // ── Observed Fields (Populated by Monitor) ─────────────────────────────────
  logic [ADDR_WIDTH-1:0]      core_addr_obs;
  logic [DATA_WIDTH-1:0]      core_wdata_obs;
  logic [4:0]                 lsunit_obs;
  logic                       mem_req_obs;
  logic                       mem_we_obs;
  logic [ADDR_WIDTH-1:0]      mem_addr_obs;
  logic [DATA_WIDTH-1:0]      mem_wdata_obs;
  logic [3:0]                 mem_be_obs;
  logic [DATA_WIDTH-1:0]      core_rdata_obs;
  logic                       core_stall_obs;
  logic                       core_err_obs;

  `uvm_object_utils_begin(lsu_transaction)
    `uvm_field_enum(lsu_pkg::lsu_instr_e, instr,        UVM_ALL_ON)
    `uvm_field_int (addr,                               UVM_ALL_ON)
    `uvm_field_int (wdata,                              UVM_ALL_ON)
    `uvm_field_int (rdata,                              UVM_ALL_ON)
    `uvm_field_int (stall_cycles,                       UVM_ALL_ON)
    `uvm_field_enum(lsu_pkg::lsu_resp_e,  resp,         UVM_ALL_ON)
    `uvm_field_int (mem_req_obs,                        UVM_ALL_ON)
    `uvm_field_int (mem_we_obs,                         UVM_ALL_ON)
    `uvm_field_int (mem_addr_obs,                       UVM_ALL_ON)
    `uvm_field_int (mem_wdata_obs,                      UVM_ALL_ON)
    `uvm_field_int (mem_be_obs,                         UVM_ALL_ON)
    `uvm_field_int (core_rdata_obs,                     UVM_ALL_ON)
    `uvm_field_int (core_stall_obs,                     UVM_ALL_ON)
    `uvm_field_int (core_err_obs,                       UVM_ALL_ON)
  `uvm_object_utils_end

  // ── Constraints ───────────────────────────────────────────────────────────

  // Default address range within standard 64KB region
  constraint c_addr_range {
    addr inside { [32'h0000_0000 : 32'h0000_FFFC] };
  }

  // Natural alignment constraints
  constraint c_alignment {
    if (instr == INSTR_LW || instr == INSTR_SW) {
      addr[1:0] == 2'b00;
    } else if (instr == INSTR_LH || instr == INSTR_LHU || instr == INSTR_SH) {
      addr[0] == 1'b0;
    }
  }

  // Realistic memory bridge stall distribution
  constraint c_stall_delay {
    stall_cycles dist { 0 := 70, [1:3] := 20, [4:8] := 10 };
  }

  // Response distribution: primarily OKAY, occasional bus error
  constraint c_resp {
    resp dist { RESP_OKAY := 95, RESP_ERROR := 5 };
  }

  function new(string name = "lsu_transaction");
    super.new(name);
  endfunction

  // ── Helper inspection methods ──────────────────────────────────────────────
  function bit is_enabled();
    return (instr != INSTR_NOP);
  endfunction

  function bit is_store();
    return (instr inside {INSTR_SB, INSTR_SH, INSTR_SW});
  endfunction

  function bit is_load();
    return (instr inside {INSTR_LB, INSTR_LH, INSTR_LW, INSTR_LBU, INSTR_LHU});
  endfunction

  // ── Map instruction to 5-bit lsunit control bus: [4]=en, [3]=st, [2:0]=funct3
  function logic [4:0] get_lsunit();
    case (instr)
      INSTR_LB:  return 5'b1_0_000;
      INSTR_LH:  return 5'b1_0_001;
      INSTR_LW:  return 5'b1_0_010;
      INSTR_LBU: return 5'b1_0_100;
      INSTR_LHU: return 5'b1_0_101;
      INSTR_SB:  return 5'b1_1_000;
      INSTR_SH:  return 5'b1_1_001;
      INSTR_SW:  return 5'b1_1_010;
      default:   return 5'b0_0_000; // NOP
    endcase
  endfunction

  // ── Golden Model: Expected Byte Enables (mem_be[3:0]) ──────────────────────
  function logic [3:0] get_expected_be();
    logic [1:0] byte_offset;
    byte_offset = addr[1:0];

    if (!is_store()) return 4'b0000;

    case (instr)
      INSTR_SB: begin
        case (byte_offset)
          2'b00:   return 4'b0001;
          2'b01:   return 4'b0010;
          2'b10:   return 4'b0100;
          default: return 4'b1000;
        endcase
      end
      INSTR_SH: begin
        if (byte_offset[1] == 1'b0)
          return 4'b0011;
        else
          return 4'b1100;
      end
      INSTR_SW: return 4'b1111;
      default:  return 4'b0000;
    endcase
  endfunction

  // ── Golden Model: Expected Aligned Write Data (mem_wdata[31:0]) ───────────
  function logic [31:0] get_expected_wdata();
    logic [1:0] byte_offset;
    byte_offset = addr[1:0];

    if (!is_store()) return wdata; // ls_unit default passthrough

    case (instr)
      INSTR_SB: begin
        case (byte_offset)
          2'b00:   return wdata;
          2'b01:   return wdata << 8;
          2'b10:   return wdata << 16;
          default: return wdata << 24;
        endcase
      end
      INSTR_SH: begin
        if (byte_offset[1] == 1'b0)
          return wdata;
        else
          return wdata << 16;
      end
      INSTR_SW: return wdata;
      default:  return 32'd0;
    endcase
  endfunction

  // ── Golden Model: Expected Formatted Load Data (core_rdata[31:0]) ──────────
  function logic [31:0] get_expected_rdata();
    logic [1:0] byte_offset;
    byte_offset = addr[1:0];

    if (!is_load()) return 32'd0;

    case (instr)
      INSTR_LB: begin // Sign-Extended Byte
        case (byte_offset)
          2'b00:   return {{24{rdata[7]}},  rdata[7:0]};
          2'b01:   return {{24{rdata[15]}}, rdata[15:8]};
          2'b10:   return {{24{rdata[23]}}, rdata[23:16]};
          default: return {{24{rdata[31]}}, rdata[31:24]};
        endcase
      end

      INSTR_LH: begin // Sign-Extended Halfword
        if (byte_offset[1] == 1'b0)
          return {{16{rdata[15]}}, rdata[15:0]};
        else
          return {{16{rdata[31]}}, rdata[31:16]};
      end

      INSTR_LW: return rdata;

      INSTR_LBU: begin // Zero-Extended Byte
        case (byte_offset)
          2'b00:   return {24'b0, rdata[7:0]};
          2'b01:   return {24'b0, rdata[15:8]};
          2'b10:   return {24'b0, rdata[23:16]};
          default: return {24'b0, rdata[31:24]};
        endcase
      end

      INSTR_LHU: begin // Zero-Extended Halfword
        if (byte_offset[1] == 1'b0)
          return {16'b0, rdata[15:0]};
        else
          return {16'b0, rdata[31:16]};
      end

      default: return 32'd0;
    endcase
  endfunction

endclass
