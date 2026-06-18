class csr_env;
    virtual csr_if vif;

    csr_sequencer sequencer;
    csr_driver driver;
    csr_monitor monitor;
    csr_scoreboard scoreboard;
    csr_coverage coverage;
    csr_reference_model ref_model;

    mailbox #(csr_transaction) seq2drv;
    mailbox #(csr_transaction) drv2ref;
    mailbox #(csr_transaction) ref2scb;
    mailbox #(csr_transaction) mon2scb;
    mailbox #(csr_transaction) mon2cov;

    function new(virtual csr_if vif);
        this.vif = vif;
    endfunction

    task build();
        seq2drv = new();
        drv2ref = new();
        ref2scb = new();
        mon2scb = new();
        mon2cov = new();

        driver     = new(vif, seq2drv, drv2ref);
        monitor    = new(vif, mon2scb, mon2cov);
        ref_model  = new(drv2ref, ref2scb);
        scoreboard = new(ref2scb, mon2scb);
        coverage   = new(mon2cov);
        sequencer  = new(seq2drv, vif);
    endtask

    task run();
        fork
            sequencer.run();
            driver.run();
            monitor.run();
            ref_model.run();
            scoreboard.run();
            coverage.run();
        join_none
    endtask

    function void report();
        coverage.display_stats();
        scoreboard.report();
    endfunction
endclass
