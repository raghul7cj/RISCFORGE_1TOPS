// =============================================================================
// lsu_driver.sv — Driver for RV32I Load/Store Unit
// Emulates both upstream pipeline core and downstream memory bridge.
// =============================================================================

import lsu_pkg::*;

class lsu_driver extends uvm_driver #(lsu_transaction);
  `uvm_component_utils(lsu_driver)

  import lsu_pkg::*;

  virtual lsu_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual lsu_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "Failed to get virtual interface from config_db")
  endfunction

  // ── Main driver loop ───────────────────────────────────────────────────────
  task run_phase(uvm_phase phase);
    lsu_transaction tr;
    init_signals();
    @(posedge vif.clk iff vif.rst_n);

    forever begin
      seq_item_port.get_next_item(tr);
      drive_transaction(tr);
      seq_item_port.item_done();
    end
  endtask

  // ── Reset all interface signals to safe defaults ──────────────────────────
  task init_signals();
    vif.driver_cb.core_addr  <= 32'd0;
    vif.driver_cb.core_wdata <= 32'd0;
    vif.driver_cb.lsunit     <= 5'd0;
    vif.driver_cb.mem_rdata  <= 32'd0;
    vif.driver_cb.mem_stall  <= 1'b0;
    vif.driver_cb.mem_err    <= 1'b0;
  endtask

  // ── Drive a single complete LSU transaction ────────────────────────────────
  task drive_transaction(lsu_transaction tr);
    @(vif.driver_cb);

    // 1. Upstream CPU drives core pipeline interface
    vif.driver_cb.core_addr  <= tr.addr;
    vif.driver_cb.core_wdata <= tr.wdata;
    vif.driver_cb.lsunit     <= tr.get_lsunit();

    // 2. Downstream memory drives read data (for loads)
    vif.driver_cb.mem_rdata  <= tr.rdata;

    // 3. Inject memory bridge stall / backpressure if requested
    if (tr.stall_cycles > 0) begin
      vif.driver_cb.mem_stall <= 1'b1;
      repeat (tr.stall_cycles) @(vif.driver_cb);
      vif.driver_cb.mem_stall <= 1'b0;
    end

    // 4. Inject memory bridge error if requested
    if (tr.resp == RESP_ERROR) begin
      vif.driver_cb.mem_err <= 1'b1;
      @(vif.driver_cb);
      vif.driver_cb.mem_err <= 1'b0;
    end else begin
      vif.driver_cb.mem_err <= 1'b0;
      @(vif.driver_cb);
    end

    // 5. Deassert request and allow one idle cycle between transactions
    vif.driver_cb.lsunit <= 5'd0;
    @(vif.driver_cb);

  endtask

endclass
