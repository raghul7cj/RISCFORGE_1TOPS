// =============================================================================
// lsu_coverage.sv — Functional Coverage Collector for RV32I Load/Store Unit
// Measures instruction space, byte offset alignment, sign extension, and strobes.
// =============================================================================

import lsu_pkg::*;

class lsu_coverage extends uvm_subscriber #(lsu_transaction);
  `uvm_component_utils(lsu_coverage)

  import lsu_pkg::*;

  lsu_transaction tr;

  // ── CG1: Instruction Coverage ──────────────────────────────────────────────
  covergroup instr_cg;
    cp_instr: coverpoint tr.instr {
      bins LOAD_BYTE      = {INSTR_LB};
      bins LOAD_HALF      = {INSTR_LH};
      bins LOAD_WORD      = {INSTR_LW};
      bins LOAD_BYTE_U    = {INSTR_LBU};
      bins LOAD_HALF_U    = {INSTR_LHU};
      bins STORE_BYTE     = {INSTR_SB};
      bins STORE_HALF     = {INSTR_SH};
      bins STORE_WORD     = {INSTR_SW};
    }
  endgroup

  // ── CG2: Instruction × Byte Offset Alignment ──────────────────────────────
  covergroup offset_cg;
    cp_instr: coverpoint tr.instr {
      bins LOAD_BYTE      = {INSTR_LB, INSTR_LBU};
      bins LOAD_HALF      = {INSTR_LH, INSTR_LHU};
      bins LOAD_WORD      = {INSTR_LW};
      bins STORE_BYTE     = {INSTR_SB};
      bins STORE_HALF     = {INSTR_SH};
      bins STORE_WORD     = {INSTR_SW};
    }

    cp_offset: coverpoint tr.addr[1:0] {
      bins off_0 = {2'b00};
      bins off_1 = {2'b01};
      bins off_2 = {2'b10};
      bins off_3 = {2'b11};
    }

    cx_instr_offset: cross cp_instr, cp_offset {
      // Ignore unaligned natural combinations if strictly aligned
      ignore_bins unaligned_word = binsof(cp_instr) intersect {INSTR_LW, INSTR_SW} &&
                                   binsof(cp_offset) intersect {2'b01, 2'b10, 2'b11};
      ignore_bins unaligned_half = binsof(cp_instr) intersect {INSTR_LH, INSTR_SH} &&
                                   binsof(cp_offset) intersect {2'b01, 2'b11};
    }
  endgroup

  // ── CG3: Byte Enable Patterns (mem_be[3:0]) ────────────────────────────────
  covergroup strobe_cg;
    cp_be: coverpoint tr.mem_be_obs {
      bins BE_SB_0  = {4'b0001};
      bins BE_SB_1  = {4'b0010};
      bins BE_SB_2  = {4'b0100};
      bins BE_SB_3  = {4'b1000};
      bins BE_SH_LO = {4'b0011};
      bins BE_SH_HI = {4'b1100};
      bins BE_SW    = {4'b1111};
      bins BE_NONE  = {4'b0000};
    }
  endgroup

  // ── CG4: Sign Extension Coverage (Positive vs Negative Sign Bit) ───────────
  covergroup sign_ext_cg;
    cp_lb_sign: coverpoint tr.core_rdata_obs[31] iff (tr.instr == INSTR_LB) {
      bins pos_sign = {1'b0};
      bins neg_sign = {1'b1};
    }
    cp_lh_sign: coverpoint tr.core_rdata_obs[31] iff (tr.instr == INSTR_LH) {
      bins pos_sign = {1'b0};
      bins neg_sign = {1'b1};
    }
  endgroup

  // ── CG5: Memory Bridge Handshake & Exception Coverage ─────────────────────
  covergroup handshake_cg;
    cp_stall: coverpoint tr.stall_cycles {
      bins no_stall    = {0};
      bins short_stall = {[1:3]};
      bins long_stall  = {[4:8]};
    }
    cp_resp: coverpoint tr.resp {
      bins RESP_OK   = {RESP_OKAY};
      bins RESP_ERR  = {RESP_ERROR};
    }
    cx_stall_resp: cross cp_stall, cp_resp;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    instr_cg     = new();
    offset_cg    = new();
    strobe_cg    = new();
    sign_ext_cg  = new();
    handshake_cg = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
  endfunction

  function void write(lsu_transaction t);
    tr = t;
    instr_cg.sample();
    offset_cg.sample();
    strobe_cg.sample();
    sign_ext_cg.sample();
    handshake_cg.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", "==================== COVERAGE REPORT ====================", UVM_NONE)
    `uvm_info("COV", $sformatf("Instruction Space : %.1f%%", instr_cg.get_inst_coverage()),     UVM_NONE)
    `uvm_info("COV", $sformatf("Byte Offsets      : %.1f%%", offset_cg.get_inst_coverage()),    UVM_NONE)
    `uvm_info("COV", $sformatf("Byte Strobe Mask  : %.1f%%", strobe_cg.get_inst_coverage()),    UVM_NONE)
    `uvm_info("COV", $sformatf("Sign Extension    : %.1f%%", sign_ext_cg.get_inst_coverage()),  UVM_NONE)
    `uvm_info("COV", $sformatf("Bridge Handshake  : %.1f%%", handshake_cg.get_inst_coverage()), UVM_NONE)
    `uvm_info("COV", $sformatf("  hs.cp_stall      : %.1f%%", handshake_cg.cp_stall.get_inst_coverage()), UVM_NONE)
    `uvm_info("COV", $sformatf("  hs.cp_resp       : %.1f%%", handshake_cg.cp_resp.get_inst_coverage()), UVM_NONE)
    `uvm_info("COV", $sformatf("  hs.cx_stall_resp : %.1f%%", handshake_cg.cx_stall_resp.get_inst_coverage()), UVM_NONE)
    `uvm_info("COV", $sformatf("  last stall_cycles=%0d resp=%s", tr.stall_cycles, tr.resp.name()), UVM_NONE)
    `uvm_info("COV", "=========================================================", UVM_NONE)
  endfunction

endclass
