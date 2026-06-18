// alu_seq_crv.sv
class alu_seq_crv;
  mailbox #(alu_transaction) drv_mbx;
  int num_transactions = 100;

  function new(mailbox #(alu_transaction) drv_mbx, int num_transactions = 100);
    this.drv_mbx = drv_mbx;
    this.num_transactions = num_transactions;
  endfunction

  task body();
    $display("[Sequence] Starting Constrained Random ALU Sequence (%0d items)...", num_transactions);
    
    for (int i = 0; i < num_transactions; i++) begin
      alu_transaction txn = new();
      if (!txn.randomize()) begin
        $error("[Sequence] CRV Randomization failed!");
      end else begin
        drv_mbx.put(txn);
        #2ns;
      end
    end

    $display("[Sequence] Constrained Random ALU Sequence Done.");
  endtask
endclass: alu_seq_crv
