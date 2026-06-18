// alu_driver.sv
class alu_driver;
  virtual alu_if vif;
  mailbox #(alu_transaction) drv_mbx;

  function new(virtual alu_if vif, mailbox #(alu_transaction) drv_mbx);
    this.vif = vif;
    this.drv_mbx = drv_mbx;
  endfunction

  task run();
    forever begin
      alu_transaction txn;
      drv_mbx.get(txn);
      
      // Drive inputs combinationally
      vif.A          = txn.A;
      vif.B          = txn.B;
      vif.ALUControl = txn.ALUControl;
      
      // Small delay for combinational settling
      #1ns;
    end
  endtask
endclass: alu_driver
