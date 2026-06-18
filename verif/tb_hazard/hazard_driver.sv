// hazard_driver.sv
class hazard_driver;
  virtual hazard_if vif;
  mailbox #(hazard_transaction) drv_mbx;

  function new(virtual hazard_if vif, mailbox #(hazard_transaction) drv_mbx);
    this.vif = vif;
    this.drv_mbx = drv_mbx;
  endfunction

  task run();
    forever begin
      hazard_transaction txn;
      drv_mbx.get(txn);

      vif.rst                   = txn.rst;
      vif.RegWriteM             = txn.RegWriteM;
      vif.RegWriteW             = txn.RegWriteW;
      vif.RD_M                  = txn.RD_M;
      vif.RD_W                  = txn.RD_W;
      vif.Rs1_E                 = txn.Rs1_E;
      vif.Rs2_E                 = txn.Rs2_E;
      vif.Rs1_D                 = txn.Rs1_D;
      vif.Rs2_D                 = txn.Rs2_D;
      vif.RdE                   = txn.RdE;
      vif.ResultSrcE            = txn.ResultSrcE;
      vif.PCSrcE                = txn.PCSrcE;
      vif.illegal_instr         = txn.illegal_instr;
      vif.csr_valid_D           = txn.csr_valid_D;
      vif.csr_raddr_D           = txn.csr_raddr_D;
      vif.csr_raddr_E           = txn.csr_raddr_E;
      vif.csr_raddr_W           = txn.csr_raddr_W;
      vif.csr_addr_E            = txn.csr_addr_E;
      vif.csr_addr_M            = txn.csr_addr_M;
      vif.csr_addr_W            = txn.csr_addr_W;
      vif.csr_write_en_W        = txn.csr_write_en_W;
      vif.csr_write_en_M        = txn.csr_write_en_M;
      vif.csr_write_en_E        = txn.csr_write_en_E;
      vif.flush_pipeline_onehot = txn.flush_pipeline_onehot;
      vif.valid_E               = txn.valid_E;
      vif.exc_valid_E           = txn.exc_valid_E;
      vif.valid_M               = txn.valid_M;
      vif.exc_valid_M           = txn.exc_valid_M;
      vif.wb_redirect           = txn.wb_redirect;
      vif.stallM                = txn.stallM;

      #1ns;
    end
  endtask
endclass: hazard_driver
