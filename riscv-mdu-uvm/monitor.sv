// =============================================================================
// File: monitor.sv
// Description: UVM Monitor for RV32M Coprocessor Unit
// =============================================================================
`ifndef MONITOR_SV
`define MONITOR_SV

class rv32m_monitor extends uvm_monitor;
    `uvm_component_utils(rv32m_monitor)

    virtual rv32m_if vif;
    uvm_analysis_port #(rv32m_transaction) monitor_port;
    uvm_analysis_port #(rv32m_transaction) ap; // standard alias

    function new(string name = "rv32m_monitor", uvm_component parent = null);
        super.new(name, parent);
        `uvm_info("MONITOR", "Constructed rv32m_monitor", UVM_HIGH)
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("MONITOR", "Build phase rv32m_monitor", UVM_HIGH)
        monitor_port = new("monitor_port", this);
        ap           = monitor_port; // point both ports to the same handle

        if (!uvm_config_db#(virtual rv32m_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("MONITOR", "Could not get virtual interface vif in monitor!")
        end
    endfunction

    task run_phase(uvm_phase phase);
        super.run_phase(phase);
        `uvm_info("MONITOR", "Run phase rv32m_monitor active", UVM_HIGH)

        // Wait for reset release
        wait (vif.rst_n === 1'b1);
        @(posedge vif.clk);

        forever begin
            sample_transaction();
        end
    endtask

    virtual task sample_transaction();
        rv32m_transaction tr;
        int unsigned cycles;
        bit timeout;

        // 1. Detect start of an M-extension operation (valid_in asserted)
        while (vif.valid_in !== 1'b1) begin
            @(posedge vif.clk);
        end

        tr = rv32m_transaction::type_id::create("mon_tr");
        tr.rs1    = vif.rs1;
        tr.rs2    = vif.rs2;
        tr.funct3 = vif.funct3;
        tr.rd_in  = vif.rd_in;
        cycles    = 1;
        timeout   = 0;

        // 2. Track execution cycles until valid_out is asserted
        @(posedge vif.clk);
        while (vif.valid_out !== 1'b1 && !timeout) begin
            cycles++;
            if (cycles > 100) begin
                timeout = 1;
            end else begin
                @(posedge vif.clk);
            end
        end

        if (timeout) begin
            `uvm_fatal("MON_TIMEOUT", $sformatf("FSM Timeout! Operation %s hung after %0d cycles (rs1=0x%08h, rs2=0x%08h)",
                       tr.get_op_name(), cycles, tr.rs1, tr.rs2))
        end

        // 3. Sample outputs at valid_out completion
        tr.result        = vif.result;
        tr.rd_out        = vif.rd_out;
        tr.actual_cycles = cycles;

        `uvm_info("MONITOR", $sformatf("Sampled: %s", tr.convert2string()), UVM_MEDIUM)

        // Broadcast transaction to Scoreboard and Coverage Subscriber
        monitor_port.write(tr);
    endtask

    // Backward-compatible alias method
    virtual task sample();
        sample_transaction();
    endtask

endclass : rv32m_monitor

// Backward-compatible alias for template integration
typedef rv32m_monitor mon;

`endif // MONITOR_SV
