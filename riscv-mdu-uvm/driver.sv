// =============================================================================
// File: driver.sv
// Description: UVM Driver for RV32M Coprocessor Unit
// =============================================================================
`ifndef DRIVER_SV
`define DRIVER_SV

class rv32m_driver extends uvm_driver #(rv32m_transaction);
    `uvm_component_utils(rv32m_driver)

    virtual rv32m_if vif;

    function new(string name = "rv32m_driver", uvm_component parent = null);
        super.new(name, parent);
        `uvm_info("DRIVER", "Constructed rv32m_driver", UVM_HIGH)
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("DRIVER", "Build phase rv32m_driver", UVM_HIGH)
        if (!uvm_config_db#(virtual rv32m_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("DRIVER", "Could not get virtual interface vif from config_db!")
        end
    endfunction

    task run_phase(uvm_phase phase);
        super.run_phase(phase);
        `uvm_info("DRIVER", "Run phase rv32m_driver active", UVM_HIGH)

        // Reset default outputs
        vif.valid_in <= 1'b0;
        vif.funct3   <= 3'b0;
        vif.rs1      <= 32'b0;
        vif.rs2      <= 32'b0;
        vif.rd_in    <= 5'b0;

        // Wait for reset deassertion
        wait (vif.rst_n === 1'b1);
        @(posedge vif.clk);

        forever begin
            seq_item_port.get_next_item(req);
            drive_transaction(req);
            seq_item_port.item_done();
        end
    endtask

    virtual task drive_transaction(rv32m_transaction tr);
        // Wait if pipeline is stalled
        while (vif.stall === 1'b1) begin
            @(posedge vif.clk);
        end

        // Assert valid_in and drive operands on negative clock edge for clean setup
        @(negedge vif.clk);
        vif.funct3   <= tr.funct3;
        vif.rs1      <= tr.rs1;
        vif.rs2      <= tr.rs2;
        vif.rd_in    <= tr.rd_in;
        vif.valid_in <= 1'b1;

        // Hold valid_in high for exactly 1 clock cycle
        @(negedge vif.clk);
        vif.valid_in <= 1'b0;

        // Wait for DUT to assert valid_out indicating operation completion
        while (vif.valid_out !== 1'b1) begin
            @(negedge vif.clk);
        end

        `uvm_info("DRIVER", $sformatf("Completed driving %s: rs1=0x%08h, rs2=0x%08h, rd=x%0d",
                  tr.get_op_name(), tr.rs1, tr.rs2, tr.rd_in), UVM_HIGH)
    endtask

    // Backward-compatible alias method
    virtual task drive(rv32m_transaction tr);
        drive_transaction(tr);
    endtask

endclass : rv32m_driver

// Backward-compatible alias for template integration
typedef rv32m_driver drv;

`endif // DRIVER_SV
