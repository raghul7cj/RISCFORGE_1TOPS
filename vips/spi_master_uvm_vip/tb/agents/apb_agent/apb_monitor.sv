//------------------------------------------------------------------------------
// apb_monitor : samples the APB bus every clock and publishes one
// apb_transaction per completed transfer (PSEL && PENABLE && PREADY).
//------------------------------------------------------------------------------
class apb_monitor extends uvm_monitor;
    `uvm_component_utils(apb_monitor)

    apb_agent_config cfg;
    uvm_analysis_port #(apb_transaction) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(apb_agent_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("APB_MON", "apb_agent_config not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(cfg.vif.mon_cb);
            if (cfg.vif.mon_cb.PSEL && cfg.vif.mon_cb.PENABLE && cfg.vif.mon_cb.PREADY) begin
                apb_transaction tr = apb_transaction::type_id::create("tr");
                tr.addr  = cfg.vif.mon_cb.PADDR;
                tr.dir   = cfg.vif.mon_cb.PWRITE ? APB_WRITE : APB_READ;
                tr.wdata = cfg.vif.mon_cb.PWDATA;
                tr.rdata = cfg.vif.mon_cb.PRDATA;
                tr.error = cfg.vif.mon_cb.PSLVERR;
                `uvm_info("APB_MON", tr.convey(), UVM_HIGH)
                ap.write(tr);
            end
        end
    endtask

endclass : apb_monitor
