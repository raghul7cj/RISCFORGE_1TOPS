class apb_timer_sequencer extends uvm_sequencer #(apb_timer_txn);

    `uvm_component_utils(apb_timer_sequencer)

    function new(string name = "apb_timer_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass
