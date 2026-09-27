class apb_timer_test extends uvm_test;

    `uvm_component_utils(apb_timer_test)

    apb_timer_env env;
    virtual apb_timer_if vif;

    function new(string name = "apb_timer_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction


    function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        env = apb_timer_env::type_id::create("env", this);

        if (!uvm_config_db#(virtual apb_timer_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Interface not found")

    endfunction


    task reset_dut();
        vif.HRESETn = 0;
        repeat (5)
            @(posedge vif.HCLK);

        @(negedge vif.HCLK);
        vif.HRESETn = 1;
    endtask

    task run_phase(uvm_phase phase);

        apb_register_seq      reg_seq;
        apb_prescaler_seq     prescaler_seq;
        apb_compare_irq_seq   compare_seq;
        apb_overflow_seq      overflow_seq;
        apb_cmp_zero_seq      zero_seq;
        apb_independence_seq  independence_seq;
        apb_random_seq        random_seq;

        int err_before;

        phase.raise_objection(this);

        reset_dut();

        // REGISTER TEST
        `uvm_info("TEST", "START REGISTER TEST", UVM_LOW)

        err_before = env.sb.errors;

        reg_seq = apb_register_seq::type_id::create("reg_seq");

        reg_seq.start(env.agent.seqr);

        if (env.sb.errors == err_before)
            `uvm_info("PASS", "REGISTER TEST PASSED", UVM_NONE)
        else
            `uvm_error("FAIL", "REGISTER TEST FAILED")


        // PRESCALER TEST
        `uvm_info("TEST", "START PRESCALER TEST", UVM_LOW)

        err_before = env.sb.errors;

        prescaler_seq = apb_prescaler_seq::type_id::create("prescaler_seq");

        prescaler_seq.start(env.agent.seqr);

        if (env.sb.errors == err_before)
            `uvm_info("PASS", "PRESCALER TEST PASSED", UVM_NONE)
        else
            `uvm_error("FAIL", "PRESCALER TEST FAILED")


        // COMPARE IRQ TEST
        `uvm_info("TEST", "START COMPARE IRQ TEST", UVM_LOW)

        err_before = env.sb.errors;

        compare_seq = apb_compare_irq_seq::type_id::create("compare_seq");

        compare_seq.start(env.agent.seqr);

        if (env.sb.errors == err_before)
            `uvm_info("PASS", "COMPARE IRQ TEST PASSED", UVM_NONE)
        else
            `uvm_error("FAIL", "COMPARE IRQ TEST FAILED")


        // OVERFLOW TEST
        `uvm_info("TEST", "START OVERFLOW TEST", UVM_LOW)

        err_before = env.sb.errors;

        overflow_seq = apb_overflow_seq::type_id::create("overflow_seq");

        overflow_seq.start(env.agent.seqr);

        if (env.sb.errors == err_before)
            `uvm_info("PASS", "OVERFLOW TEST PASSED", UVM_NONE)
        else
            `uvm_error("FAIL", "OVERFLOW TEST FAILED")


        // CMP ZERO TEST
        `uvm_info("TEST", "START CMP ZERO TEST", UVM_LOW)

        err_before = env.sb.errors;

        zero_seq = apb_cmp_zero_seq::type_id::create("zero_seq");

        zero_seq.start(env.agent.seqr);

        if (env.sb.errors == err_before)
            `uvm_info("PASS", "CMP ZERO TEST PASSED", UVM_NONE)
        else
            `uvm_error("FAIL", "CMP ZERO TEST FAILED")


        // INDEPENDENCE TEST
        `uvm_info("TEST", "START INDEPENDENCE TEST", UVM_LOW)

        err_before = env.sb.errors;

        independence_seq = apb_independence_seq::type_id::create("independence_seq");

        independence_seq.start(env.agent.seqr);

        if (env.sb.errors == err_before)
            `uvm_info("PASS", "INDEPENDENCE TEST PASSED", UVM_NONE)
        else
            `uvm_error("FAIL", "INDEPENDENCE TEST FAILED")


        // RANDOM TEST
        `uvm_info("TEST", "START RANDOM TEST", UVM_LOW)

        err_before = env.sb.errors;

        random_seq =
            apb_random_seq::type_id::create("random_seq");

        random_seq.count = 5000;

        random_seq.start(env.agent.seqr);

        if (env.sb.errors == err_before)
            `uvm_info("PASS", "RANDOM TEST PASSED", UVM_NONE)
        else
            `uvm_error("FAIL", "RANDOM TEST FAILED")


        repeat (20)
            @(posedge vif.HCLK);

        phase.drop_objection(this);

    endtask


    function void check_phase(uvm_phase phase);

        if (env.sb.errors == 0)
            `uvm_info("FINAL", "ALL TESTS PASSED", UVM_NONE)
        else
            `uvm_error("FINAL", $sformatf("TEST FAILED: TOTAL ERRORS = %0d", env.sb.errors))

    endfunction

endclass
