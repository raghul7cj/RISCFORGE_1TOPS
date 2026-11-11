// =============================================================================
// lsu_tests.sv — Test library for RV32I Load/Store Unit
// Run with: +UVM_TESTNAME=<test_name>
// =============================================================================

import lsu_pkg::*;

// ── Base Test ─────────────────────────────────────────────────────────────────
class lsu_base_test extends uvm_test;
  `uvm_component_utils(lsu_base_test)
  lsu_env m_env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m_env = lsu_env::type_id::create("m_env", this);
  endfunction

  task run_sequence(uvm_sequence #(lsu_transaction) seq);
    seq.start(m_env.m_agent.m_sequencer);
  endtask
endclass

// ── 1. Smoke: Word Read and Write ─────────────────────────────────────────────
class lsu_smoke_test extends lsu_base_test;
  `uvm_component_utils(lsu_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    lsu_word_rw_seq seq;
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting lsu_smoke_test...", UVM_LOW)
    seq = lsu_word_rw_seq::type_id::create("seq");
    seq.num_ops = 20;
    run_sequence(seq);
    phase.drop_objection(this);
  endtask
endclass

// ── 2. Coverage Closure Test ──────────────────────────────────────────────────
class lsu_coverage_test extends lsu_base_test;
  `uvm_component_utils(lsu_coverage_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    lsu_all_instructions_seq all_seq;
    lsu_byte_offset_seq      off_seq;
    lsu_sign_extension_seq   sign_seq;
    lsu_error_seq            err_seq;

    phase.raise_objection(this);
    `uvm_info("TEST", "Starting lsu_coverage_test...", UVM_LOW)

    all_seq  = lsu_all_instructions_seq::type_id::create("all_seq");
    off_seq  = lsu_byte_offset_seq::type_id::create("off_seq");
    sign_seq = lsu_sign_extension_seq::type_id::create("sign_seq");
    err_seq  = lsu_error_seq::type_id::create("err_seq");

    run_sequence(all_seq);
    run_sequence(off_seq);
    run_sequence(sign_seq);
    run_sequence(err_seq);

    phase.drop_objection(this);
  endtask
endclass

// ── 3. Stress & Backpressure Test ─────────────────────────────────────────────
class lsu_stress_test extends lsu_base_test;
  `uvm_component_utils(lsu_stress_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    lsu_backpressure_seq bp_seq;
    lsu_rand_seq         rand_seq;

    phase.raise_objection(this);
    `uvm_info("TEST", "Starting lsu_stress_test...", UVM_LOW)

    bp_seq   = lsu_backpressure_seq::type_id::create("bp_seq");
    rand_seq = lsu_rand_seq::type_id::create("rand_seq");

    bp_seq.num_ops   = 40;
    rand_seq.num_ops = 100;

    run_sequence(bp_seq);
    run_sequence(rand_seq);

    phase.drop_objection(this);
  endtask
endclass

// ── 4. Full Regression Suite ──────────────────────────────────────────────────
class lsu_regression_test extends lsu_base_test;
  `uvm_component_utils(lsu_regression_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    lsu_word_rw_seq          smoke;
    lsu_all_instructions_seq all_ops;
    lsu_byte_offset_seq      offsets;
    lsu_sign_extension_seq   sign_ext;
    lsu_backpressure_seq     stalls;
    lsu_error_seq            errors;
    lsu_rand_seq             randoms;

    phase.raise_objection(this);
    `uvm_info("TEST", "Starting lsu_regression_test suite...", UVM_LOW)

    smoke    = lsu_word_rw_seq::type_id::create("smoke");
    all_ops  = lsu_all_instructions_seq::type_id::create("all_ops");
    offsets  = lsu_byte_offset_seq::type_id::create("offsets");
    sign_ext = lsu_sign_extension_seq::type_id::create("sign_ext");
    stalls   = lsu_backpressure_seq::type_id::create("stalls");
    errors   = lsu_error_seq::type_id::create("errors");
    randoms  = lsu_rand_seq::type_id::create("randoms");

    run_sequence(smoke);
    run_sequence(all_ops);
    run_sequence(offsets);
    run_sequence(sign_ext);
    run_sequence(stalls);
    run_sequence(errors);
    run_sequence(randoms);

    phase.drop_objection(this);
  endtask
endclass
