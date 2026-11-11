// =============================================================================
// File: agent.sv
// Description: UVM Agent for RV32M Coprocessor Unit
// =============================================================================
`ifndef AGENT_SV
`define AGENT_SV

class rv32m_agent extends uvm_agent;
    `uvm_component_utils(rv32m_agent)

    rv32m_driver    driver;
    rv32m_sequencer sequencer;
    rv32m_monitor   monitor;

    function new(string name = "rv32m_agent", uvm_component parent = null);
        super.new(name, parent);
        `uvm_info("AGENT", "Constructed rv32m_agent", UVM_HIGH)
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("AGENT", "Build phase rv32m_agent", UVM_HIGH)

        monitor = rv32m_monitor::type_id::create("monitor", this);

        if (get_is_active() == UVM_ACTIVE) begin
            driver    = rv32m_driver::type_id::create("driver", this);
            sequencer = rv32m_sequencer::type_id::create("sequencer", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        `uvm_info("AGENT", "Connect phase rv32m_agent", UVM_HIGH)

        if (get_is_active() == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass : rv32m_agent

// Backward-compatible alias for template integration
typedef rv32m_agent agnt;

`endif // AGENT_SV
