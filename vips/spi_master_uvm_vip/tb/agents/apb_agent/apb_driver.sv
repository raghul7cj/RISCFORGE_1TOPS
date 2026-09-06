//------------------------------------------------------------------------------
// apb_driver : drives apb_transaction items onto the APB3 bus.
// Timing follows the legacy apb_master_bfm task semantics: SETUP phase at
// one posedge, ACCESS phase (PENABLE=1) at the next, sampling PRDATA/PSLVERR
// once PREADY is observed high, so wait-states inserted by the slave (e.g.
// RXFIFO empty / TXFIFO full backpressure) are respected transparently.
//------------------------------------------------------------------------------
class apb_driver extends uvm_driver #(apb_transaction);
    `uvm_component_utils(apb_driver)

    apb_agent_config cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(apb_agent_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("APB_DRV", "apb_agent_config not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        idle_bus();
        wait (cfg.vif.HRESETn === 1'b1);
        forever begin
            apb_transaction req;
            seq_item_port.get_next_item(req);
            drive(req);
            seq_item_port.item_done();
        end
    endtask

    task idle_bus();
        cfg.vif.PADDR   <= '0;
        cfg.vif.PWDATA  <= '0;
        cfg.vif.PWRITE  <= 1'b0;
        cfg.vif.PSEL    <= 1'b0;
        cfg.vif.PENABLE <= 1'b0;
    endtask

    task drive(apb_transaction req);
        int unsigned waits;
        waits = 0;

        @(posedge cfg.vif.HCLK); #1;
        cfg.vif.PADDR   = req.addr;
        cfg.vif.PWDATA  = (req.dir == APB_WRITE) ? req.wdata : '0;
        cfg.vif.PWRITE  = (req.dir == APB_WRITE);
        cfg.vif.PSEL    = 1'b1;
        cfg.vif.PENABLE = 1'b0;

        @(posedge cfg.vif.HCLK); #1;
        cfg.vif.PENABLE = 1'b1;

        while (cfg.vif.PREADY !== 1'b1) begin
            waits++;
            @(posedge cfg.vif.HCLK); #1;
        end

        req.rdata       = cfg.vif.PRDATA;
        req.error       = cfg.vif.PSLVERR;
        req.wait_states = waits;

        @(posedge cfg.vif.HCLK); #1;
        cfg.vif.PSEL    = 1'b0;
        cfg.vif.PENABLE = 1'b0;
        cfg.vif.PWRITE  = 1'b0;
        cfg.vif.PADDR   = '0;
        cfg.vif.PWDATA  = '0;
    endtask

endclass : apb_driver
