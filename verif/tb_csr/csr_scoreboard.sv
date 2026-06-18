class csr_scoreboard;
    mailbox #(csr_transaction) ref2scb;
    mailbox #(csr_transaction) obs2scb;

    int pass_count;
    int fail_count;
    int fail_flag;
    int unsigned tx_count = 0;

    function new(mailbox #(csr_transaction) ref2scb,
                 mailbox #(csr_transaction) obs2scb);
        this.ref2scb = ref2scb;
        this.obs2scb  = obs2scb;
        pass_count = 0;
        fail_count = 0;
        fail_flag = 0;
        tx_count = 0;
    endfunction

    task run();
        csr_transaction predicted;
        csr_transaction observed;
        forever begin
            fail_flag = 0;
            ref2scb.get(predicted);
            obs2scb.get(observed);
            tx_count++;
            compare(predicted, observed);
        end
    endtask

    task compare(csr_transaction predicted, csr_transaction observed);
        if (predicted.csr_rdata_o !== observed.csr_rdata_o) begin
            fail_flag = 1;
            $error("Mismatch in csr_rdata_o: predicted=%h, observed=%h, transaction_count=%0d",
                   predicted.csr_rdata_o, observed.csr_rdata_o, tx_count);
        end
        if (predicted.mtvec_out_o !== observed.mtvec_out_o) begin
            fail_flag = 1;
            $error("Mismatch in mtvec_out_o: predicted=%h, observed=%h, transaction_count=%0d",
                   predicted.mtvec_out_o, observed.mtvec_out_o, tx_count);
        end
        if (predicted.mie_out_o !== observed.mie_out_o) begin
            fail_flag = 1;
            $error("Mismatch in mie_out_o: predicted=%h, observed=%h, transaction_count=%0d",
                   predicted.mie_out_o, observed.mie_out_o, tx_count);
        end
        if (predicted.mip_out_o !== observed.mip_out_o) begin
            fail_flag = 1;
            $error("Mismatch in mip_out_o: predicted=%h, observed=%h, transaction_count=%0d",
                   predicted.mip_out_o, observed.mip_out_o, tx_count);
        end
        if (predicted.mstatus_mie_out_o !== observed.mstatus_mie_out_o) begin
            fail_flag = 1;
            $error("Mismatch in mstatus_mie_out_o: predicted=%h, observed=%h, transaction_count=%0d",
                   predicted.mstatus_mie_out_o, observed.mstatus_mie_out_o, tx_count);
        end
        if (predicted.mepc_out_o !== observed.mepc_out_o) begin
            fail_flag = 1;
            $error("Mismatch in mepc_out_o: predicted=%h, observed=%h, transaction_count=%0d",
                   predicted.mepc_out_o, observed.mepc_out_o, tx_count);
        end
        if (predicted.mcause_out_o !== observed.mcause_out_o) begin
            fail_flag = 1;
            $error("Mismatch in mcause_out_o: predicted=%h, observed=%h, transaction_count=%0d",
                   predicted.mcause_out_o, observed.mcause_out_o, tx_count);
        end
        if (predicted.mstatus_out_o !== observed.mstatus_out_o) begin
            fail_flag = 1;
            $error("Mismatch in mstatus_out_o: predicted=%h, observed=%h, transaction_count=%0d",
                   predicted.mstatus_out_o, observed.mstatus_out_o, tx_count);
        end

        if (fail_flag) begin
            fail_count++;
        end
        else begin
            pass_count++;
        end
    endtask

    function void report();
        $display("CSR Scoreboard Report:");
        $display("Pass Count: %0d", pass_count);
        $display("Fail Count: %0d", fail_count);
        if ((pass_count + fail_count) != 0) begin
            $display("Pass Rate: %.2f%%", (pass_count * 100.0) / (pass_count + fail_count));
        end
        else begin
            $display("Pass Rate: N/A");
        end
    endfunction
endclass
