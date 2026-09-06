//------------------------------------------------------------------------------
// apb_agent
//------------------------------------------------------------------------------
class apb_agent extends uvm_agent;
    `uvm_component_utils(apb_agent)

    apb_agent_config cfg;
    apb_sequencer    sqr;
    apb_driver       drv;
    apb_monitor      mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(apb_agent_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("APB_AGT", "apb_agent_config not found in config_db")

        is_active = cfg.is_active;

        mon = apb_monitor::type_id::create("mon", this);
        uvm_config_db#(apb_agent_config)::set(this, "mon", "cfg", cfg);

        if (is_active == UVM_ACTIVE) begin
            sqr = apb_sequencer::type_id::create("sqr", this);
            drv = apb_driver::type_id::create("drv", this);
            uvm_config_db#(apb_agent_config)::set(this, "drv", "cfg", cfg);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (is_active == UVM_ACTIVE)
            drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass : apb_agent
