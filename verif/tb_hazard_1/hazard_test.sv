class hazard_test;
    hazard_env env;
    virtual hazard_if vif;
    function new(virtual hazard_if vif);
        this.vif = vif;
        env = new(vif);
    endfunction

    task run();
        env.run();
        wait(env.sco.total_transactions == env.gen.num_transactions);
        #10;
        $finish;
    endtask
endclass