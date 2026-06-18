// hazard_monitor.sv
class hazard_monitor;
  virtual hazard_if vif;
  mailbox #(hazard_transaction) mon_mbx;

  function new(virtual hazard_if vif, mailbox #(hazard_transaction) mon_mbx);
    this.vif = vif;
    this.mon_mbx = mon_mbx;
  endfunction

  task run();
    forever begin
      #1ns;
      begin
        hazard_transaction txn = new();
        txn.rst                   = vif.rst;
        txn.RegWriteM             = vif.RegWriteM;
        txn.RegWriteW             = vif.RegWriteW;
        txn.RD_M                  = vif.RD_M;
        txn.RD_W                  = vif.RD_W;
        txn.Rs1_E                 = vif.Rs1_E;
        txn.Rs2_E                 = vif.Rs2_E;
        txn.Rs1_D                 = vif.Rs1_D;
        txn.Rs2_D                 = vif.Rs2_D;
        txn.RdE                   = vif.RdE;
        txn.ResultSrcE            = vif.ResultSrcE;
        txn.PCSrcE                = vif.PCSrcE;
        txn.illegal_instr         = vif.illegal_instr;
        txn.csr_valid_D           = vif.csr_valid_D;
        txn.csr_raddr_D           = vif.csr_raddr_D;
        txn.csr_raddr_E           = vif.csr_raddr_E;
        txn.csr_raddr_W           = vif.csr_raddr_W;
        txn.csr_addr_E            = vif.csr_addr_E;
        txn.csr_addr_M            = vif.csr_addr_M;
        txn.csr_addr_W            = vif.csr_addr_W;
        txn.csr_write_en_W        = vif.csr_write_en_W;
        txn.csr_write_en_M        = vif.csr_write_en_M;
        txn.csr_write_en_E        = vif.csr_write_en_E;
        txn.flush_pipeline_onehot = vif.flush_pipeline_onehot;
        txn.valid_E               = vif.valid_E;
        txn.exc_valid_E           = vif.exc_valid_E;
        txn.valid_M               = vif.valid_M;
        txn.exc_valid_M           = vif.exc_valid_M;
        txn.wb_redirect           = vif.wb_redirect;
        txn.stallM                = vif.stallM;

        // Captured Outputs
        txn.ForwardAE             = vif.ForwardAE;
        txn.ForwardBE             = vif.ForwardBE;
        txn.StallF                = vif.StallF;
        txn.StallD                = vif.StallD;
        txn.FlushD                = vif.FlushD;
        txn.FlushE                = vif.FlushE;
        txn.FlushM                = vif.FlushM;
        txn.FlushW                = vif.FlushW;

        mon_mbx.put(txn);
      end
    end
  endtask
endclass: hazard_monitor
