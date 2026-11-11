// =============================================================================
// File: rand_test.sv
// Description: UVM Test Suite (Random, Directed Corner, Stress, and Regression)
// =============================================================================
`ifndef RAND_TEST_SV
`define RAND_TEST_SV

// ── Base Test ────────────────────────────────────────────────────────────────
class rv32m_base_test extends uvm_test;
    `uvm_component_utils(rv32m_base_test)

    rv32m_env environment;

    function new(string name = "rv32m_base_test", uvm_component parent = null);
        super.new(name, parent);
        `uvm_info("BASE_TEST", "Constructed rv32m_base_test", UVM_HIGH)
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("BASE_TEST", "Build phase rv32m_base_test", UVM_HIGH)
        environment = rv32m_env::type_id::create("environment", this);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        `uvm_info("TOPOLOGY", "Testbench Component Hierarchy:", UVM_LOW)
        uvm_top.print_topology();
    endfunction

endclass : rv32m_base_test

// ── Random Test (Default Template Target) ────────────────────────────────────
class rv32m_rand_test extends rv32m_base_test;
    `uvm_component_utils(rv32m_rand_test)

    function new(string name = "rv32m_rand_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        rv32m_rand_seq seq;
        super.run_phase(phase);
        phase.raise_objection(this, "Starting rv32m_rand_test");

        seq = rv32m_rand_seq::type_id::create("seq");
        seq.set_no_of_tr(200);
        seq.start(environment.agent.sequencer);

        #100ns;
        phase.drop_objection(this, "Completed rv32m_rand_test");
    endtask

endclass : rv32m_rand_test

// ── Directed Corner Test (Exhaustive 79-Vector Matrix) ───────────────────────
class rv32m_directed_test extends rv32m_base_test;
    `uvm_component_utils(rv32m_directed_test)

    function new(string name = "rv32m_directed_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        rv32m_directed_corner_seq seq;
        super.run_phase(phase);
        phase.raise_objection(this, "Starting rv32m_directed_test");

        seq = rv32m_directed_corner_seq::type_id::create("seq");
        seq.start(environment.agent.sequencer);

        #100ns;
        phase.drop_objection(this, "Completed rv32m_directed_test");
    endtask

endclass : rv32m_directed_test

// ── Stress Test (High Volume Mul & Div) ──────────────────────────────────────
class rv32m_stress_test extends rv32m_base_test;
    `uvm_component_utils(rv32m_stress_test)

    function new(string name = "rv32m_stress_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        rv32m_mul_stress_seq mul_seq;
        rv32m_div_stress_seq div_seq;
        super.run_phase(phase);
        phase.raise_objection(this, "Starting rv32m_stress_test");

        mul_seq = rv32m_mul_stress_seq::type_id::create("mul_seq");
        mul_seq.set_no_of_tr(150);
        mul_seq.start(environment.agent.sequencer);

        div_seq = rv32m_div_stress_seq::type_id::create("div_seq");
        div_seq.set_no_of_tr(100);
        div_seq.start(environment.agent.sequencer);

        #100ns;
        phase.drop_objection(this, "Completed rv32m_stress_test");
    endtask

endclass : rv32m_stress_test

// ── Master Full Regression Test ──────────────────────────────────────────────
class rv32m_regression_test extends rv32m_base_test;
    `uvm_component_utils(rv32m_regression_test)

    function new(string name = "rv32m_regression_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        rv32m_directed_corner_seq corner_seq;
        rv32m_rand_seq            rand_seq;
        rv32m_mul_stress_seq      mul_seq;
        rv32m_div_stress_seq      div_seq;
        rv32m_cross_pair_seq      cross_seq;

        super.run_phase(phase);
        phase.raise_objection(this, "Starting rv32m_regression_test");

        `uvm_info("REGRESSION", "=== STAGE 1: 79 DIRECTED CORNER CASES ===", UVM_LOW)
        corner_seq = rv32m_directed_corner_seq::type_id::create("corner_seq");
        corner_seq.start(environment.agent.sequencer);

        `uvm_info("REGRESSION", "=== STAGE 2: 1000 RANDOMIZED TRANSACTIONS ===", UVM_LOW)
        rand_seq = rv32m_rand_seq::type_id::create("rand_seq");
        rand_seq.set_no_of_tr(10000);
        rand_seq.start(environment.agent.sequencer);

        `uvm_info("REGRESSION", "=== STAGE 3: MULTIPLIER PIPELINE STRESS ===", UVM_LOW)
        mul_seq = rv32m_mul_stress_seq::type_id::create("mul_seq");
        mul_seq.set_no_of_tr(15000);
        mul_seq.start(environment.agent.sequencer);

        `uvm_info("REGRESSION", "=== STAGE 4: DIVIDER FSM STRESS ===", UVM_LOW)
        div_seq = rv32m_div_stress_seq::type_id::create("div_seq");
        div_seq.set_no_of_tr(10000);
        div_seq.start(environment.agent.sequencer);

        `uvm_info("REGRESSION", "=== STAGE 5: CROSS-PAIR CORNER WALK ===", UVM_LOW)
        cross_seq = rv32m_cross_pair_seq::type_id::create("cross_seq");
        cross_seq.start(environment.agent.sequencer);

        #100ns;
        phase.drop_objection(this, "Completed rv32m_regression_test");
    endtask

endclass : rv32m_regression_test

// Backward-compatible alias for template integration
typedef rv32m_rand_test rand_test;

`endif // RAND_TEST_SV
