class apb_timer_coverage extends uvm_subscriber #(apb_timer_txn);

    `uvm_component_utils(apb_timer_coverage)

    virtual apb_timer_if vif;

    bit        write_s;
    bit [11:0] addr_s;
    bit [31:0] data_s;


    covergroup apb_cg;
        option.per_instance = 1;

        timer_cp : coverpoint addr_s[4] {
            bins timer0 = {0};
            bins timer1 = {1};
        }

        reg_cp : coverpoint addr_s[3:2] {
            bins timer_reg = {0};
            bins ctrl_reg  = {1};
            bins cmp_reg   = {2};
        }

        rw_cp : coverpoint write_s {
            bins read  = {0};
            bins write = {1};
        }

        timer_reg_rw_cross :
            cross timer_cp, reg_cp, rw_cp;
    endgroup


    covergroup ctrl_cg;
        option.per_instance = 1;

        enable_cp : coverpoint data_s[0] {
            bins disabled = {0};
            bins enabled  = {1};
        }

        prescaler_cp : coverpoint data_s[5:3] {
            bins p0 = {0};
            bins p1 = {1};
            bins p2 = {2};
            bins p3 = {3};
            bins p4 = {4};
            bins p5 = {5};
            bins p6 = {6};
            bins p7 = {7};
        }

        timer_cp : coverpoint addr_s[4] {
            bins timer0 = {0};
            bins timer1 = {1};
        }

        ctrl_cross :
            cross timer_cp, enable_cp, prescaler_cp;
    endgroup


    covergroup cmp_cg;
        option.per_instance = 1;

        cmp_cp : coverpoint data_s {
            bins cmp_zero = {0};
            bins cmp_small[] = {[1:5]};
            bins cmp_medium = {[6:20]};
            bins cmp_other = default;
        }
    endgroup


    covergroup irq_cg with function sample(bit [3:0] irq);
        t0_overflow : coverpoint irq[0] {
            bins hit = {1};
        }

        t0_compare : coverpoint irq[1] {
            bins hit = {1};
        }

        t1_overflow : coverpoint irq[2] {
            bins hit = {1};
        }

        t1_compare : coverpoint irq[3] {
            bins hit = {1};
        }
    endgroup


    function new(string name = "apb_timer_coverage", uvm_component parent = null);
        super.new(name, parent);

        apb_cg  = new();
        ctrl_cg = new();
        cmp_cg  = new();
        irq_cg  = new();
    endfunction


    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual apb_timer_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Interface not found")
    endfunction


    function void write(apb_timer_txn t);
        write_s = t.write;
        addr_s  = t.addr;

        if (t.write)
            data_s = t.wdata;
        else
            data_s = t.rdata;

        apb_cg.sample();


        if (t.write && (t.addr == 12'h004 || t.addr == 12'h014))
	    ctrl_cg.sample();


        if (t.write && (t.addr == 12'h008 ||  t.addr == 12'h018))
	    cmp_cg.sample();
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.HCLK);

            if (vif.HRESETn)
                irq_cg.sample(vif.irq_o);
        end
    endtask

endclass
