class apb_timer_driver extends uvm_driver #(apb_timer_txn);

    `uvm_component_utils(apb_timer_driver)

    virtual apb_timer_if vif;

    function new(string name = "apb_timer_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual apb_timer_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Interface not found")
    endfunction

    task run_phase(uvm_phase phase);
        apb_timer_txn tr;

        vif.PADDR   = '0;
        vif.PWDATA  = '0;
        vif.PWRITE  = 0;
        vif.PSEL    = 0;
        vif.PENABLE = 0;

        wait(vif.HRESETn);
        forever begin
            seq_item_port.get_next_item(tr);

            if (tr.write)
                apb_write(tr);
            else
                apb_read(tr);

            seq_item_port.item_done();
        end
    endtask


    task apb_write(apb_timer_txn tr);
        @(negedge vif.HCLK);

        vif.PADDR   = tr.addr;
        vif.PWDATA  = tr.wdata;
        vif.PWRITE  = 1;
        vif.PSEL    = 1;
        vif.PENABLE = 0;

        @(negedge vif.HCLK);

        vif.PENABLE = 1;

        @(posedge vif.HCLK);

        while (!vif.PREADY)
            @(posedge vif.HCLK);

        tr.slverr = vif.PSLVERR;

        @(negedge vif.HCLK);

        vif.PSEL    = 0;
        vif.PENABLE = 0;
        vif.PWRITE  = 0;
        vif.PADDR   = '0;
        vif.PWDATA  = '0;
    endtask


    task apb_read(apb_timer_txn tr);
        @(negedge vif.HCLK);

        vif.PADDR   = tr.addr;
        vif.PWRITE  = 0;
        vif.PSEL    = 1;
        vif.PENABLE = 0;

        @(negedge vif.HCLK);

        vif.PENABLE = 1;

        @(posedge vif.HCLK);

        while (!vif.PREADY)
            @(posedge vif.HCLK);

        tr.rdata  = vif.PRDATA;
        tr.slverr = vif.PSLVERR;

        @(negedge vif.HCLK);

        vif.PSEL    = 0;
        vif.PENABLE = 0;
        vif.PADDR   = '0;
    endtask

endclass
