class csr_monitor;

    virtual csr_if vif;

    mailbox #(csr_transaction) mon2scb;
    mailbox #(csr_transaction) mon2cov;

    function new(virtual csr_if vif,
                 mailbox #(csr_transaction) mon2scb,
                 mailbox #(csr_transaction) mon2cov);
        this.vif = vif;
        this.mon2scb = mon2scb;
        this.mon2cov = mon2cov;
    endfunction

    task run();
        csr_transaction tx;
        forever begin
            @(vif.mon_clk);
            tx = new();
            collect_tx(tx);
            mon2scb.put(tx.copy());
            mon2cov.put(tx.copy());
        end
    endtask
    localparam logic [2:0] CSR_OP_NOP          = 3'd0;
    localparam logic [2:0] CSR_OP_READ         = 3'd1;
    localparam logic [2:0] CSR_OP_WRITE_NORMAL = 3'd2;
    localparam logic [2:0] CSR_OP_WRITE_MRET   = 3'd3;
    localparam logic [2:0] CSR_OP_TRAP         = 3'd4;
    localparam logic [2:0] CSR_OP_CONCURRENT   = 3'd5;
    localparam logic [2:0] CSR_OP_RESET        = 3'd6;

    task collect_tx(csr_transaction tx);
        tx.rst_n_i = vif.mon_clk.rst_n_i;

        if ($isunknown(vif.mon_clk.csr_rdata_o)) begin
            $error("X/Z detected on csr_rdata_o");
        end

        if (vif.mon_clk.trap_valid_i) begin
            tx.csr_op_code = CSR_OP_TRAP;
        end
        else if (vif.mon_clk.csr_write_en_mret_i) begin
            tx.csr_op_code = CSR_OP_WRITE_MRET;
        end
        else if (vif.mon_clk.csr_write_en_normal_i) begin
            tx.csr_op_code = CSR_OP_WRITE_NORMAL;
        end
        else begin
            tx.csr_op_code = CSR_OP_READ;
        end

        tx.csr_raddr_i = vif.mon_clk.csr_raddr_i;
        tx.csr_waddr_normal_i = vif.mon_clk.csr_waddr_normal_i;
        tx.csr_wdata_normal_i = vif.mon_clk.csr_wdata_normal_i;
        tx.csr_write_en_normal_i = vif.mon_clk.csr_write_en_normal_i;

        tx.csr_waddr_mret_i = vif.mon_clk.csr_waddr_mret_i;
        tx.csr_wdata_mret_i = vif.mon_clk.csr_wdata_mret_i;
        tx.csr_write_en_mret_i = vif.mon_clk.csr_write_en_mret_i;

        tx.trap_valid_i = vif.mon_clk.trap_valid_i;
        tx.trap_cause_i = vif.mon_clk.trap_cause_i;
        tx.trap_pc_i = vif.mon_clk.trap_pc_i;
        tx.trap_addr_i = vif.mon_clk.trap_addr_i;
        tx.trap_addr_valid_i = vif.mon_clk.trap_addr_valid_i;
        tx.trap_is_interrupt_i = vif.mon_clk.trap_is_interrupt_i;

        tx.timer_intr_i = vif.mon_clk.timer_intr_i;
        tx.ext_intr_i = vif.mon_clk.ext_intr_i;
        tx.msft_intr_i = vif.mon_clk.msft_intr_i;

        tx.csr_rdata_o = vif.mon_clk.csr_rdata_o;
        tx.mtvec_out_o = vif.mon_clk.mtvec_out_o;
        tx.mie_out_o = vif.mon_clk.mie_out_o;
        tx.mip_out_o = vif.mon_clk.mip_out_o;
        tx.mstatus_mie_out_o = vif.mon_clk.mstatus_mie_out_o;
        tx.mepc_out_o = vif.mon_clk.mepc_out_o;
        tx.mcause_out_o = vif.mon_clk.mcause_out_o;
        tx.mstatus_out_o = vif.mon_clk.mstatus_out_o;

        tx.valid_csr = vif.mon_clk.csr_valid_o;
    endtask

endclass
