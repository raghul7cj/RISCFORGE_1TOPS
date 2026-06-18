// alu_monitor.sv
class alu_monitor;
  virtual alu_if vif;
  mailbox #(alu_transaction) mon_to_sb;
  mailbox #(alu_transaction) mon_to_cov;

  function new(virtual alu_if vif, mailbox #(alu_transaction) mon_to_sb, mailbox #(alu_transaction) mon_to_cov);
    this.vif = vif;
    this.mon_to_sb = mon_to_sb;
    this.mon_to_cov = mon_to_cov;
  endfunction

  task run();
    forever begin
      // Sample inputs and outputs after combinational settling
      #1ns;
      begin
        alu_transaction txn = new();
        txn.A          = vif.A;
        txn.B          = vif.B;
        txn.ALUControl = vif.ALUControl;
        txn.Result     = vif.Result;
        txn.Zero       = vif.Zero;
        txn.flags      = vif.flags;
        
        // Distribute transaction clone to scoreboard and coverage
        mon_to_sb.put(txn);
        mon_to_cov.put(txn.clone());
      end
    end
  endtask
endclass: alu_monitor
