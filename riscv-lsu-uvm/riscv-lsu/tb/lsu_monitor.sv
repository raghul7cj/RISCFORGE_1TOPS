// =============================================================================
// lsu_monitor.sv — Passive Monitor for RV32I Load/Store Unit
// Observes interface activity, reconstructs transactions and broadcasts to SCB & COV.
// =============================================================================

import lsu_pkg::*;

class lsu_monitor extends uvm_monitor;
  `uvm_component_utils(lsu_monitor)

  import lsu_pkg::*;

  virtual lsu_if vif;
  uvm_analysis_port #(lsu_transaction) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual lsu_if)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "Failed to get virtual interface from config_db")
  endfunction

  task run_phase(uvm_phase phase);
    @(posedge vif.clk iff vif.rst_n);
    forever collect_transaction();
  endtask

  task collect_transaction();
    lsu_transaction tr;

    // Sample when memory request is asserted
    @(vif.monitor_cb iff vif.monitor_cb.mem_req);

    tr = lsu_transaction::type_id::create("tr");

    // Sample observed port values
    tr.core_addr_obs  = vif.monitor_cb.core_addr;
    tr.core_wdata_obs = vif.monitor_cb.core_wdata;
    tr.lsunit_obs     = vif.monitor_cb.lsunit;
    tr.mem_req_obs    = vif.monitor_cb.mem_req;
    tr.mem_we_obs     = vif.monitor_cb.mem_we;
    tr.mem_addr_obs   = vif.monitor_cb.mem_addr;
    tr.mem_wdata_obs  = vif.monitor_cb.mem_wdata;
    tr.mem_be_obs     = vif.monitor_cb.mem_be;
    tr.rdata          = vif.monitor_cb.mem_rdata;
    tr.core_rdata_obs = vif.monitor_cb.core_rdata;
    tr.core_stall_obs = vif.monitor_cb.core_stall;
    tr.core_err_obs   = vif.monitor_cb.core_err;

    // Fields used by analysis components
    tr.addr  = tr.core_addr_obs;
    tr.wdata = tr.core_wdata_obs;

    // Count stall cycles and observe error across the whole request window.
    // (mem_req stays asserted for the full transaction; mem_err is pulsed
    //  near the end, so it must be watched until req deasserts)
    begin
      int unsigned stall_cnt;
      bit          saw_err;
      stall_cnt = tr.core_stall_obs ? 1 : 0;
      saw_err   = tr.core_err_obs;
      while (vif.monitor_cb.mem_req) begin
        @(vif.monitor_cb);
        if (vif.monitor_cb.core_stall) stall_cnt++;
        if (vif.monitor_cb.core_err)   saw_err = 1;
      end
      tr.stall_cycles = stall_cnt;
      tr.core_err_obs = saw_err;
      tr.resp         = saw_err ? RESP_ERROR : RESP_OKAY;
    end

    // Reconstruct instruction enum from lsunit[4:0]
    if (tr.lsunit_obs[3]) begin // Store
      case (tr.lsunit_obs[2:0])
        3'b000:  tr.instr = INSTR_SB;
        3'b001:  tr.instr = INSTR_SH;
        3'b010:  tr.instr = INSTR_SW;
        default: tr.instr = INSTR_NOP;
      endcase
    end else begin // Load
      case (tr.lsunit_obs[2:0])
        3'b000:  tr.instr = INSTR_LB;
        3'b001:  tr.instr = INSTR_LH;
        3'b010:  tr.instr = INSTR_LW;
        3'b100:  tr.instr = INSTR_LBU;
        3'b101:  tr.instr = INSTR_LHU;
        default: tr.instr = INSTR_NOP;
      endcase
    end

    `uvm_info("MON", $sformatf("Sampled %s: addr=%08h wdata=%08h rdata=%08h be=%04b out_rdata=%08h stall=%0b err=%0b",
              tr.instr.name(), tr.addr, tr.wdata, tr.rdata, tr.mem_be_obs, tr.core_rdata_obs, tr.core_stall_obs, tr.core_err_obs), UVM_HIGH)

    ap.write(tr);
  endtask

endclass
