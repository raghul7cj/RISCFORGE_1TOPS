class csr_reference_model;
    mailbox #(csr_transaction) drv2ref;
    mailbox #(csr_transaction) ref2scb;

    logic [31:0] mstatus_r;
    logic [31:0] mie_r;
    logic [31:0] mtvec_r;
    logic [31:0] mepc_r;
    logic [31:0] mcause_r;
    logic [31:0] mtval_r;
    logic [31:0] mscratch_r;
    logic        msip_r;
    logic [63:0] mcycle_r;
    logic [63:0] minstret_r;

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

    localparam logic [2:0] CSR_OP_NOP          = 3'd0;
    localparam logic [2:0] CSR_OP_READ         = 3'd1;
    localparam logic [2:0] CSR_OP_WRITE_NORMAL = 3'd2;
    localparam logic [2:0] CSR_OP_WRITE_MRET   = 3'd3;
    localparam logic [2:0] CSR_OP_TRAP         = 3'd4;
    localparam logic [2:0] CSR_OP_CONCURRENT   = 3'd5;
    localparam logic [2:0] CSR_OP_RESET        = 3'd6;

    function new(mailbox #(csr_transaction) drv2ref,
                 mailbox #(csr_transaction) ref2scb);
        this.drv2ref = drv2ref;
        this.ref2scb = ref2scb;
        reset_model();
    endfunction

    function void reset_model();
        mstatus_r  = 32'h0;
        mie_r      = 32'h0;
        mtvec_r    = 32'h0;
        mepc_r     = 32'h0;
        mcause_r   = 32'h0;
        mtval_r    = 32'h0;
        mscratch_r = 32'h0;
        msip_r     = 1'b0;
        mcycle_r   = 64'h0;
        minstret_r = 64'h0;
    endfunction

    task run();
        csr_transaction tx;
        forever begin
            drv2ref.get(tx);
            predict(tx);
            ref2scb.put(tx);
        end
    endtask

    task predict(csr_transaction tx);
        logic [31:0] mip_w;

        if (!tx.rst_n_i) begin
            reset_model();
        end
        else begin
            mcycle_r = mcycle_r + 1;

            case (tx.csr_op_code)
                CSR_OP_TRAP: begin
                    mepc_r    = tx.trap_pc_i;
                    mcause_r  = {tx.trap_is_interrupt_i, tx.trap_cause_i};
                    mtval_r   = (tx.trap_addr_valid_i) ? tx.trap_addr_i : 32'h0;
                    mstatus_r[7]     = mstatus_r[3];
                    mstatus_r[3]     = 1'b0;
                    mstatus_r[12:11] = 2'b11;
                end
                CSR_OP_WRITE_MRET: begin
                    apply_write(tx.csr_waddr_mret_i, tx.csr_wdata_mret_i);
                    if (tx.csr_waddr_mret_i == MIP_ADDR)
                        msip_r = tx.csr_wdata_mret_i[3];
                end
                CSR_OP_WRITE_NORMAL: begin
                    apply_write(tx.csr_waddr_normal_i, tx.csr_wdata_normal_i);
                    if (tx.csr_waddr_normal_i == MIP_ADDR)
                        msip_r = tx.csr_wdata_normal_i[3];
                end
                default: ;
            endcase
        end

        mip_w = {20'b0, tx.ext_intr_i, 3'b0, tx.timer_intr_i, 3'b0, (msip_r | tx.msft_intr_i), 3'b0};

        tx.csr_rdata_o         = predict_read(tx.csr_raddr_i, mip_w);
        tx.mtvec_out_o         = mtvec_r;
        tx.mie_out_o           = mie_r;
        tx.mip_out_o           = mip_w;
        tx.mstatus_mie_out_o   = mstatus_r[3];
        tx.mepc_out_o          = mepc_r;
        tx.mcause_out_o        = mcause_r;
        tx.mstatus_out_o       = mstatus_r;
    endtask

    function void apply_write(logic [11:0] addr, logic [31:0] wdata);
        case (addr)
            MSTATUS_ADDR: begin
                mstatus_r[1]     = wdata[1];
                mstatus_r[3]     = wdata[3];
                mstatus_r[7]     = wdata[7];
                mstatus_r[12:11] = wdata[12:11];
            end
            MIE_ADDR:      mie_r      = (wdata & 32'h00000888) | (mie_r & ~32'h00000888);
            MTVEC_ADDR:    mtvec_r    = (wdata & 32'hFFFFFFFC) | (mtvec_r & ~32'hFFFFFFFC);
            MSCRATCH_ADDR: mscratch_r = wdata;
            MEPC_ADDR:     mepc_r     = wdata;
            MCAUSE_ADDR:   mcause_r   = wdata;
            MTVAL_ADDR:    mtval_r    = wdata;
            MCYCLE_ADDR:    mcycle_r[31:0]  = wdata;
            MCYCLEH_ADDR:   mcycle_r[63:32] = wdata;
            MINSTRET_ADDR:  minstret_r[31:0]  = wdata;
            MINSTRETH_ADDR: minstret_r[63:32] = wdata;
            default: ;
        endcase
    endfunction

    function logic [31:0] predict_read(logic [11:0] addr, logic [31:0] mip_w);
        case (addr)
            MSTATUS_ADDR:   return mstatus_r;
            MIE_ADDR:       return mie_r;
            MTVEC_ADDR:     return mtvec_r;
            MSCRATCH_ADDR:  return mscratch_r;
            MEPC_ADDR:      return mepc_r;
            MCAUSE_ADDR:    return mcause_r;
            MTVAL_ADDR:     return mtval_r;
            MIP_ADDR:       return mip_w;
            MCYCLE_ADDR:    return mcycle_r[31:0];
            MCYCLEH_ADDR:   return mcycle_r[63:32];
            MINSTRET_ADDR:  return minstret_r[31:0];
            MINSTRETH_ADDR: return minstret_r[63:32];
            default:        return 32'h0;
        endcase
    endfunction

endclass
