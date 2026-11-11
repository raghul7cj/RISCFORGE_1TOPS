// =============================================================================
// File: env.sv
// Description: UVM Environment for RV32M Coprocessor Unit
// =============================================================================
`ifndef ENV_SV
`define ENV_SV

class rv32m_env extends uvm_env;
    `uvm_component_utils(rv32m_env)

    rv32m_agent      agent;
    rv32m_scoreboard scoreboard;
    rv32m_coverage   coverage;

    function new(string name = "rv32m_env", uvm_component parent = null);
        super.new(name, parent);
        `uvm_info("ENV", "Constructed rv32m_env", UVM_HIGH)
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("ENV", "Build phase rv32m_env", UVM_HIGH)

        agent      = rv32m_agent::type_id::create("agent", this);
        scoreboard = rv32m_scoreboard::type_id::create("scoreboard", this);
        coverage   = rv32m_coverage::type_id::create("coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        `uvm_info("ENV", "Connect phase rv32m_env", UVM_HIGH)

        // Connect monitor analysis port to scoreboard and coverage subscriber
        agent.monitor.monitor_port.connect(scoreboard.scoreboard_port);
        agent.monitor.monitor_port.connect(coverage.analysis_export);
    endfunction

endclass : rv32m_env

// Backward-compatible alias for template integration
typedef rv32m_env env;

`endif // ENV_SV
