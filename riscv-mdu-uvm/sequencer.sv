// =============================================================================
// File: sequencer.sv
// Description: UVM Sequencer for RV32M Coprocessor Unit
// =============================================================================
`ifndef SEQUENCER_SV
`define SEQUENCER_SV

class rv32m_sequencer extends uvm_sequencer #(rv32m_transaction);
    `uvm_component_utils(rv32m_sequencer)

    function new(string name = "rv32m_sequencer", uvm_component parent = null);
        super.new(name, parent);
        `uvm_info("SEQUENCER", "Constructed rv32m_sequencer", UVM_HIGH)
    endfunction

endclass : rv32m_sequencer

// Backward-compatible alias for template integration
typedef rv32m_sequencer seqr;

`endif // SEQUENCER_SV
