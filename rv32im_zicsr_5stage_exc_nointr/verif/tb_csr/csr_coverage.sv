class csr_coverage;

    csr_transaction tx;
    mailbox #(csr_transaction) mon2cov;

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

    localparam int ILLEGAL_INSTRUCTION      = 2;
    localparam int EBREAK                   = 3;
    localparam int LOAD_ADDRESS_MISALIGNED  = 4;
    localparam int LOAD_ACCESS_FAULT        = 5;
    localparam int STORE_ADDRESS_MISALIGNED = 6;
    localparam int STORE_ACCESS_FAULT       = 7;
    localparam int ECALL                    = 11;

    localparam logic [2:0] CSR_OP_NOP          = 3'd0;
    localparam logic [2:0] CSR_OP_READ         = 3'd1;
    localparam logic [2:0] CSR_OP_WRITE_NORMAL = 3'd2;
    localparam logic [2:0] CSR_OP_WRITE_MRET   = 3'd3;
    localparam logic [2:0] CSR_OP_TRAP         = 3'd4;
    localparam logic [2:0] CSR_OP_CONCURRENT   = 3'd5;
    localparam logic [2:0] CSR_OP_RESET        = 3'd6;


    covergroup csr_cg;
        cp_opcode: coverpoint tx.csr_op_code {
            bins read         = {CSR_OP_READ};
            bins write_normal = {CSR_OP_WRITE_NORMAL};
            bins write_mret   = {CSR_OP_WRITE_MRET};
            bins trap         = {CSR_OP_TRAP};
            bins concurrent   = {CSR_OP_CONCURRENT};
            bins reset        = {CSR_OP_RESET};
        }

        cp_raddr: coverpoint tx.csr_raddr_i {
            bins mstatus   = {MSTATUS_ADDR};
            bins mie       = {MIE_ADDR};
            bins mtvec     = {MTVEC_ADDR};
            bins mscratch  = {MSCRATCH_ADDR};
            bins mepc      = {MEPC_ADDR};
            bins mcause    = {MCAUSE_ADDR};
            bins mtval     = {MTVAL_ADDR};
            bins mip       = {MIP_ADDR};
            bins mcycle    = {MCYCLE_ADDR};
            bins minstret  = {MINSTRET_ADDR};
            bins mcycleh   = {MCYCLEH_ADDR};
            bins minstreth = {MINSTRETH_ADDR};
        }

        cp_waddr_normal: coverpoint tx.csr_waddr_normal_i {
            bins mstatus   = {MSTATUS_ADDR};
            bins mie       = {MIE_ADDR};
            bins mtvec     = {MTVEC_ADDR};
            bins mscratch  = {MSCRATCH_ADDR};
            bins mepc      = {MEPC_ADDR};
            bins mcause    = {MCAUSE_ADDR};
            bins mtval     = {MTVAL_ADDR};
            bins mip       = {MIP_ADDR};
            bins mcycle    = {MCYCLE_ADDR};
            bins minstret  = {MINSTRET_ADDR};
            bins mcycleh   = {MCYCLEH_ADDR};
            bins minstreth = {MINSTRETH_ADDR};
        }

        cp_waddr_mret: coverpoint tx.csr_waddr_mret_i {
            bins mstatus = {MSTATUS_ADDR};
        }

        cp_trap_cause: coverpoint tx.trap_cause_i {
            bins illegal_instruction      = {ILLEGAL_INSTRUCTION};
            bins ebreak                   = {EBREAK};
            bins load_address_misaligned  = {LOAD_ADDRESS_MISALIGNED};
            bins load_access_fault        = {LOAD_ACCESS_FAULT};
            bins store_address_misaligned = {STORE_ADDRESS_MISALIGNED};
            bins store_access_fault       = {STORE_ACCESS_FAULT};
            bins ecall                    = {ECALL};
        }

        cc_op_waddr: cross cp_opcode, cp_waddr_normal, cp_waddr_mret;
        cc_op_raddr: cross cp_opcode, cp_raddr;
    endgroup

    function new(mailbox #(csr_transaction) mon2cov);
        this.mon2cov = mon2cov;
        csr_cg = new();
    endfunction

    task run();
        forever begin
            mon2cov.get(tx);
            cover_tx(tx);
        end
    endtask

    task cover_tx(csr_transaction tx);
        this.tx = tx;
        csr_cg.sample();
    endtask

    function void display_stats();
        $display("---------------------------------------------------");
        $display("CSR Coverage Report:");
        $display("  Overall Type Coverage: %0.2f%%", csr_cg.get_coverage());
        $display("  This Instance Coverage: %0.2f%%", csr_cg.get_inst_coverage());
        $display("---------------------------------------------------");
    endfunction

endclass
