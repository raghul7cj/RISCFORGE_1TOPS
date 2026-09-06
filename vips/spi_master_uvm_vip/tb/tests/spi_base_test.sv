//------------------------------------------------------------------------------
// spi_base_test : builds the environment, wires in the virtual interfaces
// published by the HDL top, and provides a watchdog. Concrete tests extend
// this and implement run_phase() by starting one or more (virtual)
// sequences.
//------------------------------------------------------------------------------
class spi_base_test extends uvm_test;
    `uvm_component_utils(spi_base_test)

    spi_env        env;
    spi_env_config cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        cfg         = spi_env_config::type_id::create("cfg");
        cfg.apb_cfg = apb_agent_config::type_id::create("apb_cfg");
        cfg.spi_cfg = spi_agent_config::type_id::create("spi_cfg");

        cfg.apb_cfg.is_active = UVM_ACTIVE;
        cfg.spi_cfg.is_active = UVM_ACTIVE;

        if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", cfg.apb_cfg.vif))
            `uvm_fatal("SPI_BASE_TEST", "virtual apb_if 'apb_vif' not found in config_db")
        if (!uvm_config_db#(virtual spi_if)::get(this, "", "spi_vif", cfg.spi_cfg.vif))
            `uvm_fatal("SPI_BASE_TEST", "virtual spi_if 'spi_vif' not found in config_db")

        uvm_config_db#(spi_env_config)::set(this, "env", "cfg", cfg);
        env = spi_env::type_id::create("env", this);
    endfunction

    // Helper for derived tests: raises the run_phase objection, starts the
    // given virtual sequence on the environment's virtual sequencer under a
    // watchdog, then drops the objection. Keeps every concrete test to a
    // one-liner in run_phase().
    task automatic run_vseq(uvm_phase phase, uvm_sequence seq, int unsigned watchdog_ns = 1_000_000);
        phase.raise_objection(this);
        fork
            begin : WATCHDOG
                #(watchdog_ns * 1ns);
                `uvm_fatal("SPI_BASE_TEST", "Watchdog timeout")
            end
            begin : SEQ
                seq.start(env.vsqr);
                disable WATCHDOG;
            end
        join
        phase.drop_objection(this);
    endtask

    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

endclass : spi_base_test
