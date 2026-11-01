class apb_timer_env extends uvm_env;

    `uvm_component_utils(apb_timer_env)

    apb_timer_agent      agent;
    apb_timer_scoreboard sb;
    apb_timer_coverage   cov;

    function new(string name = "apb_timer_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction


    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        agent = apb_timer_agent::type_id::create("agent", this);
        sb    = apb_timer_scoreboard::type_id::create("sb", this);
        cov   = apb_timer_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        agent.mon.ap.connect(cov.analysis_export);
    endfunction

endclass
