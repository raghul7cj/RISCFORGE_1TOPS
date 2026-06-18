class csr_driver;
    virtual csr_if vif;
    mailbox #(csr_transaction) seq2drv;
    mailbox #(csr_transaction) drv2ref;

    function new(virtual csr_if vif,
                     mailbox #(csr_transaction) seq2drv,
                     mailbox #(csr_transaction) drv2ref);
        this.vif = vif;
        this.seq2drv = seq2drv;
        this.drv2ref = drv2ref;
    endfunction;

    task run();
        csr_transaction tx = new();
        forever begin
            seq2drv.get(tx);            //receive the transaction object from the sequence
            drv2ref.put(tx.copy());  //send the transaction object to the reference model
            drive_tx(tx);  
        end
    endtask //run

    task drive_tx(csr_transaction tx);
        @(posedge vif.clk);
            vif.rst_n_i = tx.rst_n_i; 

            vif.csr_raddr_i = tx.csr_raddr_i;
            vif.csr_waddr_normal_i = tx.csr_waddr_normal_i;
            vif.csr_wdata_normal_i = tx.csr_wdata_normal_i;
            vif.csr_write_en_normal_i = tx.csr_write_en_normal_i;

            vif.csr_waddr_mret_i = tx.csr_waddr_mret_i;
            vif.csr_wdata_mret_i = tx.csr_wdata_mret_i;
            vif.csr_write_en_mret_i = tx.csr_write_en_mret_i;

            vif.trap_valid_i = tx.trap_valid_i;
            vif.trap_cause_i = tx.trap_cause_i;
            vif.trap_pc_i = tx.trap_pc_i;
            vif.trap_addr_i = tx.trap_addr_i;
            vif.trap_addr_valid_i = tx.trap_addr_valid_i;
            vif.trap_is_interrupt_i = tx.trap_is_interrupt_i;

            vif.timer_intr_i = tx.timer_intr_i;
            vif.ext_intr_i = tx.ext_intr_i;
            vif.msft_intr_i = tx.msft_intr_i;
    endtask 


endclass //csr_driver