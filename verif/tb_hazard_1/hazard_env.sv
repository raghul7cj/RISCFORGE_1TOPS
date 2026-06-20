class hazard_env;
    // Components
    hazard_generator  gen;
    hazard_driver     drv;
    hazard_monitor    mon;
    hazard_scoreboard sco;
    hazard_coverage   cov;

    // Mailboxes
    mailbox #(hazard_transaction) mbx_gd;
    mailbox #(hazard_transaction) mbx_ms;
    mailbox #(hazard_transaction) mbx_mc;

    // Events
    event drv_done;
    event mon_done;
    event sco_done;

    virtual hazard_if vif;
    function new(virtual hazard_if vif);
        this.vif = vif;
        mbx_gd = new();
        mbx_ms = new();
        mbx_mc = new();

        gen = new(mbx_gd,drv_done,sco_done);
        drv = new(mbx_gd,vif,drv_done);
        mon = new(mbx_ms,mbx_mc,vif,drv_done,mon_done);
        sco = new(mbx_ms,mon_done,sco_done);
        cov = new(mbx_mc);
    endfunction

    task run();
        fork
            gen.run();
            drv.run();
            mon.run();
            sco.run();
            cov.run();
        join_none
    endtask
endclass