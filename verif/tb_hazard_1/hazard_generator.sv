class hazard_generator;
    hazard_transaction tr;
    mailbox #(hazard_transaction) mbx_gd;
    int num_transactions;
    event drv_done;
   
    function new(mailbox #(hazard_transaction) mbx_gd, event scb_done);
        this.mbx_gd = mbx_gd;
        this.drv_done = drv_done;
        num_transactions = 5000;
    endfunction

    task run();
        int sel;
        repeat(num_transactions)
        begin
            sel = $urandom_range(0,99);
            if(sel < 25)
                tr = new mem_forward_txn();

            else if(sel < 45)
                tr = new wb_forward_txn();

            else if(sel < 60)
                tr = new load_use_txn();

            else if(sel < 75)
                tr = new csr_stall_txn();

            else if(sel < 85)
                tr = new mem_priority_txn();

            else if(sel < 92)
                tr = new csr_gpr_stall_txn();

            else if(sel < 97)
                tr = new x0_forward_txn();

            else
                tr = new redirect_txn();

            if(!tr.randomize())
            begin
                $error("GENERATOR RANDOMIZATION FAILED");
                $finish;
            end
            tr.display("GEN");
            mbx_gd.put(tr.copy());
            @(scb_done);
        end
        $display("Stimulus Generation Finished");
        $display("Total Transactions = %0d",num_transactions);
    endtask
endclass