class csr_sequencer;

    mailbox #(csr_transaction) seq2drv;
    virtual csr_if vif;

    localparam logic [11:0] MSTATUS_ADDR   = 12'h300;
    localparam logic [11:0] MIE_ADDR       = 12'h304;
    localparam logic [11:0] MTVEC_ADDR     = 12'h305;
    localparam logic [11:0] MSCRATCH_ADDR  = 12'h340;
    localparam logic [11:0] MEPC_ADDR      = 12'h341;
    localparam logic [11:0] MCAUSE_ADDR    = 12'h342;
    localparam logic [11:0] MTVAL_ADDR     = 12'h343;
    localparam logic [11:0] MIP_ADDR       = 12'h344;
    localparam logic [11:0] MCYCLE_ADDR    = 12'hB00;
    localparam logic [11:0] MINSTRET_ADDR  = 12'hB02;
    localparam logic [11:0] MCYCLEH_ADDR   = 12'hB80;
    localparam logic [11:0] MINSTRETH_ADDR = 12'hB82;

    function new(mailbox #(csr_transaction) seq2drv,
                 virtual csr_if vif = null);
        this.seq2drv = seq2drv;
        this.vif = vif;
    endfunction

    task run();
        // Bring the CSR block through the full set of directed scenarios first.
        seq2drv.put(create_csr_reset_tx());

        seq2drv.put(create_csr_write_tx(MSTATUS_ADDR,  32'h0000_188A));
        seq2drv.put(create_csr_write_tx(MIE_ADDR,      32'h0000_0888));
        seq2drv.put(create_csr_write_tx(MTVEC_ADDR,    32'h0000_0123));
        seq2drv.put(create_csr_write_tx(MSCRATCH_ADDR, 32'hA5A5_5A5A));
        seq2drv.put(create_csr_write_tx(MEPC_ADDR,     32'h1000_0011));
        seq2drv.put(create_csr_write_tx(MCAUSE_ADDR,   32'h8000_0003));
        seq2drv.put(create_csr_write_tx(MTVAL_ADDR,    32'hDEAD_BEEF));
        seq2drv.put(create_csr_write_tx(MIP_ADDR,      32'h0000_0008));
        seq2drv.put(create_csr_write_tx(MCYCLE_ADDR,   32'h0000_0005));
        seq2drv.put(create_csr_write_tx(MINSTRET_ADDR, 32'h0000_0007));
        seq2drv.put(create_csr_write_tx(MCYCLEH_ADDR,  32'h0000_0001));
        seq2drv.put(create_csr_write_tx(MINSTRETH_ADDR,32'h0000_0002));

        seq2drv.put(create_csr_read_tx(MSTATUS_ADDR));
        seq2drv.put(create_csr_read_tx(MIE_ADDR));
        seq2drv.put(create_csr_read_tx(MTVEC_ADDR));
        seq2drv.put(create_csr_read_tx(MSCRATCH_ADDR));
        seq2drv.put(create_csr_read_tx(MEPC_ADDR));
        seq2drv.put(create_csr_read_tx(MCAUSE_ADDR));
        seq2drv.put(create_csr_read_tx(MTVAL_ADDR));
        seq2drv.put(create_csr_read_tx(MIP_ADDR));
        seq2drv.put(create_csr_read_tx(MCYCLE_ADDR));
        seq2drv.put(create_csr_read_tx(MINSTRET_ADDR));
        seq2drv.put(create_csr_read_tx(MCYCLEH_ADDR));
        seq2drv.put(create_csr_read_tx(MINSTRETH_ADDR));

        seq2drv.put(create_csr_mret_tx(32'h0000_188A));
        seq2drv.put(create_csr_trap_tx(1'b0, 31'd2, 32'h0000_1040, 32'h0000_2004, 1'b1));
        seq2drv.put(create_csr_trap_tx(1'b1, 31'd7, 32'h0000_1080, 32'h0000_0000, 1'b0));
        seq2drv.put(create_csr_concurrent_tx());

        // Mix in unconstrained random traffic after the directed cases.
        repeat (40) begin
            seq2drv.put(create_csr_random_tx());
        end
    endtask

    function csr_transaction create_csr_reset_tx();
        csr_transaction tx = new();
        void'(tx.randomize() with {
            csr_op_code == CSR_OP_RESET;
            valid_csr   == 1'b0;
        });
        tx.csr_raddr_i = 12'hFFF;
        tx.csr_waddr_normal_i = 12'hFFF;
        tx.csr_waddr_mret_i   = 12'hFFE;
        return tx;
    endfunction

    function csr_transaction create_csr_write_tx(logic [11:0] addr,
                                                 logic [31:0] data);
        csr_transaction tx = new();
        void'(tx.randomize() with {
            csr_op_code == CSR_OP_WRITE_NORMAL;
            valid_csr   == 1'b1;
        });
        tx.csr_raddr_i = addr;
        tx.csr_waddr_normal_i = addr;
        tx.csr_wdata_normal_i = data;
        return tx;
    endfunction

    function csr_transaction create_csr_mret_tx(logic [31:0] data);
        csr_transaction tx = new();
        void'(tx.randomize() with {
            csr_op_code == CSR_OP_WRITE_MRET;
            valid_csr   == 1'b1;
        });
        tx.csr_raddr_i = MSTATUS_ADDR;
        tx.csr_waddr_mret_i = MSTATUS_ADDR;
        tx.csr_wdata_mret_i = data;
        return tx;
    endfunction

    function csr_transaction create_csr_trap_tx(
        bit trap_is_interrupt,
        logic [30:0] trap_cause,
        logic [31:0] trap_pc,
        logic [31:0] trap_addr,
        bit trap_addr_valid
    );
        csr_transaction tx = new();
        void'(tx.randomize() with {
            csr_op_code == CSR_OP_TRAP;
            valid_csr   == 1'b1;
        });
        tx.csr_raddr_i = MEPC_ADDR;
        tx.trap_is_interrupt_i = trap_is_interrupt;
        tx.trap_cause_i        = trap_cause;
        tx.trap_pc_i           = trap_pc;
        tx.trap_addr_i         = trap_addr;
        tx.trap_addr_valid_i   = trap_addr_valid;
        return tx;
    endfunction

    function csr_transaction create_csr_read_tx(logic [11:0] addr,
                                                 bit valid = 1'b1);
        csr_transaction tx = new();
        void'(tx.randomize() with {
            csr_op_code == CSR_OP_READ;
            valid_csr   == valid;
        });
        tx.csr_raddr_i = valid ? addr : 12'hFFF;
        tx.csr_waddr_normal_i = valid ? addr : 12'hFFE;
        tx.csr_waddr_mret_i   = valid ? addr : 12'hFFD;
        return tx;
    endfunction

    function csr_transaction create_csr_concurrent_tx();
        csr_transaction tx = new();
        void'(tx.randomize() with {
            csr_op_code == CSR_OP_CONCURRENT;
            valid_csr   == 1'b1;
        });
        tx.csr_raddr_i          = MEPC_ADDR;
        tx.csr_waddr_normal_i   = MSCRATCH_ADDR;
        tx.csr_wdata_normal_i   = 32'h1234_5678;
        tx.csr_write_en_normal_i = 1'b1;
        tx.csr_waddr_mret_i     = MSTATUS_ADDR;
        tx.csr_wdata_mret_i     = 32'h0000_188A;
        tx.csr_write_en_mret_i  = 1'b1;
        tx.trap_valid_i         = 1'b1;
        tx.trap_cause_i         = 31'd3;
        tx.trap_pc_i            = 32'h0000_3000;
        tx.trap_addr_i          = 32'h0000_4000;
        tx.trap_addr_valid_i    = 1'b1;
        tx.trap_is_interrupt_i   = 1'b0;
        return tx;
    endfunction

    function csr_transaction create_csr_random_tx();
        csr_transaction tx = new();
        if (!tx.randomize()) begin
            $fatal(1, "[CSR_SEQ] Randomization failed");
        end
        return tx;
    endfunction

endclass
