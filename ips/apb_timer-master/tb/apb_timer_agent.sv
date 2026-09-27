class apb_timer_agent extends uvm_agent;

    `uvm_component_utils(apb_timer_agent)

    apb_timer_driver    drv;
    apb_timer_monitor   mon;
    apb_timer_sequencer seqr;

    function new(string name = "apb_timer_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction


    function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        mon = apb_timer_monitor::type_id::create("mon", this);

        if (get_is_active() == UVM_ACTIVE) begin
            drv  = apb_timer_driver::type_id::create("drv", this);
            seqr = apb_timer_sequencer::type_id::create("seqr", this);
        end

    endfunction


    function void connect_phase(uvm_phase phase);

        if (get_is_active() == UVM_ACTIVE)
            drv.seq_item_port.connect(seqr.seq_item_export);

    endfunction

endclass
