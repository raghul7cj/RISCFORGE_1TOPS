// =============================================================================
// lsu_sequences.sv — Stimulus Sequences for RV32I Load/Store Unit
// Covers all instructions (LB, LH, LW, LBU, LHU, SB, SH, SW), offsets, stalls, errors
// =============================================================================

import lsu_pkg::*;

// ── Base Sequence ─────────────────────────────────────────────────────────────
class lsu_base_seq extends uvm_sequence #(lsu_transaction);
  `uvm_object_utils(lsu_base_seq)
  import lsu_pkg::*;

  function new(string name = "lsu_base_seq");
    super.new(name);
  endfunction
endclass

// ── 1. Smoke: Word Read and Write ─────────────────────────────────────────────
class lsu_word_rw_seq extends lsu_base_seq;
  `uvm_object_utils(lsu_word_rw_seq)
  int unsigned num_ops = 20;

  function new(string name = "lsu_word_rw_seq");
    super.new(name);
  endfunction

  task body();
    lsu_transaction tr;
    repeat (num_ops) begin
      tr = lsu_transaction::type_id::create("tr");
      start_item(tr);
      if (!tr.randomize() with {
            instr inside {INSTR_LW, INSTR_SW};
            stall_cycles == 0;
            resp == RESP_OKAY;
          })
        `uvm_fatal("SEQ", "Randomization failed for lsu_word_rw_seq")
      finish_item(tr);
    end
  endtask
endclass

// ── 2. All Instructions: LB, LH, LW, LBU, LHU, SB, SH, SW ─────────────────────
class lsu_all_instructions_seq extends lsu_base_seq;
  `uvm_object_utils(lsu_all_instructions_seq)

  function new(string name = "lsu_all_instructions_seq");
    super.new(name);
  endfunction

  task body();
    lsu_transaction tr;
    lsu_instr_e all_ops[8] = '{
      INSTR_LB, INSTR_LH, INSTR_LW, INSTR_LBU, INSTR_LHU,
      INSTR_SB, INSTR_SH, INSTR_SW
    };

    foreach (all_ops[i]) begin
      repeat (5) begin
        tr = lsu_transaction::type_id::create("tr");
        start_item(tr);
        if (!tr.randomize() with {
              instr == all_ops[i];
              stall_cycles == 0;
              resp == RESP_OKAY;
            })
          `uvm_fatal("SEQ", "Randomization failed for lsu_all_instructions_seq")
        finish_item(tr);
      end
    end
  endtask
endclass

// ── 3. Byte Offset Alignment Exploration ─────────────────────────────────────
class lsu_byte_offset_seq extends lsu_base_seq;
  `uvm_object_utils(lsu_byte_offset_seq)

  function new(string name = "lsu_byte_offset_seq");
    super.new(name);
  endfunction

  task body();
    lsu_transaction tr;
    bit is_st[2] = '{1'b0, 1'b1};

    // Test byte accesses across all 4 offsets (0, 1, 2, 3)
    for (int off = 0; off < 4; off++) begin
      foreach (is_st[i]) begin
        tr = lsu_transaction::type_id::create("tr");
        start_item(tr);
        if (!tr.randomize() with {
              instr == (is_st[i] ? INSTR_SB : INSTR_LB);
              addr[1:0] == off[1:0];
            })
          `uvm_fatal("SEQ", "Randomization failed for byte offset test")
        finish_item(tr);
      end
    end

    // Test halfword accesses across both offsets (0, 2)
    for (int off = 0; off < 4; off += 2) begin
      foreach (is_st[i]) begin
        tr = lsu_transaction::type_id::create("tr");
        start_item(tr);
        if (!tr.randomize() with {
              instr == (is_st[i] ? INSTR_SH : INSTR_LH);
              addr[1:0] == off[1:0];
            })
          `uvm_fatal("SEQ", "Randomization failed for halfword offset test")
        finish_item(tr);
      end
    end
  endtask
endclass

// ── 4. Sign-Extension Directed Sequence (Positive vs Negative Sign Bit) ───────
class lsu_sign_extension_seq extends lsu_base_seq;
  `uvm_object_utils(lsu_sign_extension_seq)

  function new(string name = "lsu_sign_extension_seq");
    super.new(name);
  endfunction

  task body();
    lsu_transaction tr;

    // Test LB with MSB=1 (negative byte) and MSB=0 (positive byte)
    repeat (10) begin
      tr = lsu_transaction::type_id::create("tr");
      start_item(tr);
      if (!tr.randomize() with {
            instr == INSTR_LB;
            rdata[7] == 1'b1; // Force negative sign bit
          })
        `uvm_fatal("SEQ", "Randomize failed for negative LB")
      finish_item(tr);

      tr = lsu_transaction::type_id::create("tr");
      start_item(tr);
      if (!tr.randomize() with {
            instr == INSTR_LB;
            rdata[7] == 1'b0; // Force positive sign bit
          })
        `uvm_fatal("SEQ", "Randomize failed for positive LB")
      finish_item(tr);
    end

    // Test LH with MSB=1 and MSB=0
    repeat (10) begin
      tr = lsu_transaction::type_id::create("tr");
      start_item(tr);
      if (!tr.randomize() with {
            instr == INSTR_LH;
            rdata[15] == 1'b1; // Force negative sign bit
          })
        `uvm_fatal("SEQ", "Randomize failed for negative LH")
      finish_item(tr);

      tr = lsu_transaction::type_id::create("tr");
      start_item(tr);
      if (!tr.randomize() with {
            instr == INSTR_LH;
            rdata[15] == 1'b0; // Force positive sign bit
          })
        `uvm_fatal("SEQ", "Randomize failed for positive LH")
      finish_item(tr);
    end
  endtask
endclass

// ── 5. Stall Backpressure Sequence ───────────────────────────────────────────
class lsu_backpressure_seq extends lsu_base_seq;
  `uvm_object_utils(lsu_backpressure_seq)
  int unsigned num_ops = 30;

  function new(string name = "lsu_backpressure_seq");
    super.new(name);
  endfunction

  task body();
    lsu_transaction tr;
    repeat (num_ops) begin
      tr = lsu_transaction::type_id::create("tr");
      start_item(tr);
      if (!tr.randomize() with {
            stall_cycles inside {[2:8]};
          })
        `uvm_fatal("SEQ", "Randomize failed for backpressure sequence")
      finish_item(tr);
    end
  endtask
endclass

// ── 6. Bus Error Response Sequence ───────────────────────────────────────────
class lsu_error_seq extends lsu_base_seq;
  `uvm_object_utils(lsu_error_seq)
  int unsigned num_ops = 10;

  function new(string name = "lsu_error_seq");
    super.new(name);
  endfunction

  task body();
    lsu_transaction tr;
    repeat (num_ops) begin
      tr = lsu_transaction::type_id::create("tr");
      start_item(tr);
      if (!tr.randomize() with {
            resp == RESP_ERROR;
            stall_cycles dist { 0 := 34, [1:3] := 33, [4:8] := 33 };
          })
        `uvm_fatal("SEQ", "Randomize failed for error sequence")
      finish_item(tr);
    end
  endtask
endclass

// ── 7. Fully Randomized Workhorse Sequence ───────────────────────────────────
class lsu_rand_seq extends lsu_base_seq;
  `uvm_object_utils(lsu_rand_seq)
  int unsigned num_ops = 150;

  function new(string name = "lsu_rand_seq");
    super.new(name);
  endfunction

  task body();
    lsu_transaction tr;
    repeat (num_ops) begin
      tr = lsu_transaction::type_id::create("tr");
      start_item(tr);
      if (!tr.randomize())
        `uvm_fatal("SEQ", "Randomize failed for lsu_rand_seq")
      finish_item(tr);
    end
  endtask
endclass
