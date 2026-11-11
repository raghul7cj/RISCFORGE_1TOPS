// =============================================================================
// lsu_agent.sv — Bundles Sequencer + Driver + Monitor
// =============================================================================

import lsu_pkg::*;

// Sequencer needs no customisation — alias the base class
typedef uvm_sequencer #(lsu_transaction) lsu_sequencer;

class lsu_agent extends uvm_agent;
  `uvm_component_utils(lsu_agent)

  lsu_driver    m_driver;
  lsu_sequencer m_sequencer;
  lsu_monitor   m_monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m_monitor = lsu_monitor::type_id::create("m_monitor", this);
    if (get_is_active() == UVM_ACTIVE) begin
      m_driver    = lsu_driver::type_id::create("m_driver",    this);
      m_sequencer = lsu_sequencer::type_id::create("m_sequencer", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE)
      m_driver.seq_item_port.connect(m_sequencer.seq_item_export);
  endfunction

endclass
