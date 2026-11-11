// =============================================================================
// lsu_env.sv — Top-level environment: wires Agent → Scoreboard + Coverage
// =============================================================================

import lsu_pkg::*;

class lsu_env extends uvm_env;
  `uvm_component_utils(lsu_env)

  lsu_agent      m_agent;
  lsu_scoreboard m_scoreboard;
  lsu_coverage   m_coverage;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m_agent      = lsu_agent::type_id::create("m_agent",      this);
    m_scoreboard = lsu_scoreboard::type_id::create("m_scoreboard", this);
    m_coverage   = lsu_coverage::type_id::create("m_coverage",    this);
  endfunction

  function void connect_phase(uvm_phase phase);
    // Broadcast Monitor output to both Scoreboard and Coverage
    m_agent.m_monitor.ap.connect(m_scoreboard.analysis_export);
    m_agent.m_monitor.ap.connect(m_coverage.analysis_export);
  endfunction

endclass
