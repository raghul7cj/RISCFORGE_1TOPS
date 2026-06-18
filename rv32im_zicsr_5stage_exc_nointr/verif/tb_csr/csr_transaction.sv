class csr_transaction; // Removed the empty parentheses "()" which is deprecated syntax

    rand logic [2:0] csr_op_code;;

    localparam logic [2:0] CSR_OP_NOP          = 3'd0;
    localparam logic [2:0] CSR_OP_READ         = 3'd1;
    localparam logic [2:0] CSR_OP_WRITE_NORMAL = 3'd2;
    localparam logic [2:0] CSR_OP_WRITE_MRET   = 3'd3;
    localparam logic [2:0] CSR_OP_TRAP         = 3'd4;
    localparam logic [2:0] CSR_OP_CONCURRENT   = 3'd5;
    localparam logic [2:0] CSR_OP_RESET        = 3'd6;
    
    // input to CSR  
    rand bit valid_csr;
    rand logic rst_n_i;
    
    // Matched address width to 12 bits to prevent truncation warnings
    rand logic [11:0] csr_raddr_i;
    rand logic [11:0] csr_waddr_normal_i;
    rand logic [31:0] csr_wdata_normal_i;
    rand logic        csr_write_en_normal_i;
    
    rand logic [11:0] csr_waddr_mret_i;
    rand logic [31:0] csr_wdata_mret_i;
    rand logic        csr_write_en_mret_i;

    rand logic        trap_valid_i;
    rand logic [30:0] trap_cause_i;
    rand logic [31:0] trap_pc_i;
    rand logic [31:0] trap_addr_i;
    rand logic        trap_addr_valid_i;
    rand logic        trap_is_interrupt_i;

    // Constrain interrupt inputs to standard binary 0 or 1, and make them 0 most of the time
    rand bit          timer_intr_i;
    rand bit          ext_intr_i;
    rand bit          msft_intr_i;
    
    // outputs from csr
    logic [31:0] csr_rdata_o;
    logic [31:0] mtvec_out_o;
    logic [31:0] mie_out_o;
    logic [31:0] mip_out_o;
    logic        mstatus_mie_out_o;
    logic [31:0] mepc_out_o;
    logic [31:0] mcause_out_o;
    logic [31:0] mstatus_out_o;
    
    constraint c_rst {
        if (csr_op_code == CSR_OP_RESET) 
            rst_n_i  == 1'b0;
        else
            rst_n_i  == 1'b1; // Drive 1 when deasserted (instead of 1'bz)
    }

    constraint c_op_code {
        if (csr_op_code == CSR_OP_NOP || csr_op_code == CSR_OP_RESET) {
            trap_valid_i          == 1'b0;
            csr_write_en_normal_i == 1'b0;
            csr_write_en_mret_i   == 1'b0;
        }
        if (csr_op_code == CSR_OP_READ) {
            trap_valid_i          == 1'b0;
            csr_write_en_normal_i == 1'b0;
            csr_write_en_mret_i   == 1'b0;
        }   
        if (csr_op_code == CSR_OP_WRITE_NORMAL){
            trap_valid_i          == 1'b0;
            csr_write_en_normal_i == 1'b1;
            csr_write_en_mret_i   == 1'b0;
        }
        if (csr_op_code == CSR_OP_WRITE_MRET){
            trap_valid_i          == 1'b0;
            csr_write_en_normal_i == 1'b0;
            csr_write_en_mret_i   == 1'b1;
        }
        if (csr_op_code == CSR_OP_TRAP){
            trap_valid_i          == 1'b1;
            csr_write_en_normal_i == 1'b0;
            csr_write_en_mret_i   == 1'b0;
        }
        if (csr_op_code == CSR_OP_CONCURRENT){
            trap_valid_i          == 1'b1;
            csr_write_en_normal_i == 1'b1;
            csr_write_en_mret_i   == 1'b1;
        }
    }

    // Weight constraints for interrupt inputs (stops interrupts from spamming every transaction)
    constraint c_interrupts {
        timer_intr_i dist {1'b1 := 10, 1'b0 := 90};
        ext_intr_i   dist {1'b1 := 10, 1'b0 := 90};
        msft_intr_i  dist {1'b1 := 10, 1'b0 := 90};
    }

    constraint c_waddr_mret {
        if (csr_write_en_mret_i) {
            csr_waddr_mret_i inside {12'h300};
        }
    }

    

    // Default clean values for trap signals
    constraint c_trap_details {
        if (!trap_valid_i) {
            trap_cause_i        == 0;
            trap_pc_i           == 0;
            trap_addr_i         == 0;
            trap_addr_valid_i   == 0;
            trap_is_interrupt_i == 0;
        } else {
            // Keep cause code within standard RISC-V boundaries (e.g. 0-15)
            trap_cause_i < 16; 
        }
    }

    constraint c_validity {          
        valid_csr dist {1 := 90, 0 := 10};
    }
    
    constraint c_valid_addr {
        if (valid_csr) {
            csr_waddr_normal_i inside {
                12'h300, 12'h304, 12'h305,
                12'h340, 12'h341, 12'h342,
                12'h343, 12'h344,
                12'hB00, 12'hB02,
                12'hB80, 12'hB82
            };

            csr_waddr_mret_i inside {
                12'h300, 12'h304, 12'h305,
                12'h340, 12'h341, 12'h342,
                12'h343, 12'h344,
                12'hB00, 12'hB02,
                12'hB80, 12'hB82
            };

            csr_raddr_i inside {
                12'h300, 12'h304, 12'h305,
                12'h340, 12'h341, 12'h342,
                12'h343, 12'h344,
                12'hB00, 12'hB02,
                12'hB80, 12'hB82
            };
        } else {
            // Force the address to be invalid when valid_csr is 0
            !(csr_waddr_normal_i inside {
                12'h300, 12'h304, 12'h305,
                12'h340, 12'h341, 12'h342,
                12'h343, 12'h344,
                12'hB00, 12'hB02,
                12'hB80, 12'hB82
            });
            !(csr_waddr_mret_i inside {
                12'h300, 12'h304, 12'h305,
                12'h340, 12'h341, 12'h342,
                12'h343, 12'h344,
                12'hB00, 12'hB02,
                12'hB80, 12'hB82
            });
            !(csr_raddr_i inside {
                12'h300, 12'h304, 12'h305,
                12'h340, 12'h341, 12'h342,
                12'h343, 12'h344,
                12'hB00, 12'hB02,
                12'hB80, 12'hB82
            });
        }
    }
    
    // Copy function
    function csr_transaction copy();
        csr_transaction cpy = new();
        cpy.csr_op_code          = this.csr_op_code;
        cpy.valid_csr            = this.valid_csr;
        cpy.rst_n_i              = this.rst_n_i;
        cpy.csr_raddr_i          = this.csr_raddr_i;
        cpy.csr_waddr_normal_i   = this.csr_waddr_normal_i;
        cpy.csr_wdata_normal_i   = this.csr_wdata_normal_i;
        cpy.csr_write_en_normal_i = this.csr_write_en_normal_i;
        cpy.csr_waddr_mret_i     = this.csr_waddr_mret_i;
        cpy.csr_wdata_mret_i     = this.csr_wdata_mret_i;
        cpy.csr_write_en_mret_i  = this.csr_write_en_mret_i;
        cpy.trap_valid_i         = this.trap_valid_i;
        cpy.trap_cause_i         = this.trap_cause_i;
        cpy.trap_pc_i            = this.trap_pc_i;
        cpy.trap_addr_i          = this.trap_addr_i;
        cpy.trap_addr_valid_i    = this.trap_addr_valid_i;
        cpy.trap_is_interrupt_i  = this.trap_is_interrupt_i;
        cpy.timer_intr_i         = this.timer_intr_i;
        cpy.ext_intr_i           = this.ext_intr_i;
        cpy.msft_intr_i          = this.msft_intr_i;
        cpy.csr_rdata_o          = this.csr_rdata_o;
        cpy.mtvec_out_o          = this.mtvec_out_o;
        cpy.mie_out_o            = this.mie_out_o;
        cpy.mip_out_o            = this.mip_out_o;
        cpy.mstatus_mie_out_o    = this.mstatus_mie_out_o;
        cpy.mepc_out_o           = this.mepc_out_o;
        cpy.mcause_out_o         = this.mcause_out_o;
        cpy.mstatus_out_o        = this.mstatus_out_o;
        return cpy;
    endfunction

endclass
