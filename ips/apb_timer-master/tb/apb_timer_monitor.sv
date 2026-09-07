class apb_timer_monitor extends uvm_monitor;

    `uvm_component_utils(apb_timer_monitor)

    virtual apb_timer_if vif;

    uvm_analysis_port #(apb_timer_txn) ap;

    function new(string name = "apb_timer_monitor",uvm_component parent = null);

        super.new(name, parent);
        ap = new("ap", this);

    endfunction


    function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        if (!uvm_config_db#(virtual apb_timer_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Interface not found")

    endfunction


    task run_phase(uvm_phase phase);

        apb_timer_txn tr;

        forever begin

            @(posedge vif.HCLK);

            if (vif.HRESETn && vif.PSEL && vif.PENABLE && vif.PREADY) begin

                tr = apb_timer_txn::type_id::create("tr");

                tr.addr   = vif.PADDR;
                tr.write  = vif.PWRITE;
                tr.wdata  = vif.PWDATA;
                tr.rdata  = vif.PRDATA;
                tr.slverr = vif.PSLVERR;

                ap.write(tr);

            end

        end

    endtask

endclass
