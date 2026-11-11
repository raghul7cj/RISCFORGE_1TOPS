// =============================================================================
// File: coverage.sv
// Description: UVM Functional Coverage Subscriber for RV32M Coprocessor Unit
//              Implements 8 distinct covergroups (1 per instruction) + Crosses
// =============================================================================
`ifndef COVERAGE_SV
`define COVERAGE_SV

class rv32m_coverage extends uvm_subscriber #(rv32m_transaction);
    `uvm_component_utils(rv32m_coverage)

    // Latched transaction for covergroup sampling
    rv32m_transaction t_item;

    // Helper variables for clean bin evaluation
    logic signed [31:0] s_rs1;
    logic signed [31:0] s_rs2;
    logic signed [31:0] s_res;

    // =========================================================================
    // Master Instruction & Register Covergroup
    // =========================================================================
    covergroup cg_instruction;
        option.per_instance = 1;
        option.name = "cg_instruction";

        cp_op: coverpoint t_item.funct3 {
            bins mul    = {OP_MUL};
            bins mulh   = {OP_MULH};
            bins mulhsu = {OP_MULHSU};
            bins mulhu  = {OP_MULHU};
            bins div    = {OP_DIV};
            bins divu   = {OP_DIVU};
            bins rem    = {OP_REM};
            bins remu   = {OP_REMU};
        }

        cp_rd: coverpoint t_item.rd_in {
            bins zero = {5'd0};
            bins low  = {[5'd1:5'd7]};
            bins mid  = {[5'd8:5'd23]};
            bins high = {[5'd24:5'd31]};
        }

        cross_op_rd: cross cp_op, cp_rd;
    endgroup

    // =========================================================================
    // 1. cg_mul: Lower 32-bit Product Covergroup
    // =========================================================================
    covergroup cg_mul;
        option.per_instance = 1;
        option.name = "cg_mul";

        cp_rs1: coverpoint t_item.rs1 {
            bins zero    = {32'h0000_0000};
            bins one     = {32'h0000_0001};
            bins minus1  = {32'hFFFF_FFFF};
            bins max_pos = {32'h7FFF_FFFF};
            bins max_neg = {32'h8000_0000};
            bins pos_gen = {[32'h2 : 32'h7FFF_FFFE]};
            bins neg_gen = {[32'h8000_0001 : 32'hFFFF_FFFE]};
        }

        cp_rs2: coverpoint t_item.rs2 {
            bins zero    = {32'h0000_0000};
            bins one     = {32'h0000_0001};
            bins minus1  = {32'hFFFF_FFFF};
            bins max_pos = {32'h7FFF_FFFF};
            bins max_neg = {32'h8000_0000};
            bins pos_gen = {[32'h2 : 32'h7FFF_FFFE]};
            bins neg_gen = {[32'h8000_0001 : 32'hFFFF_FFFE]};
        }

        cp_res_zero: coverpoint (t_item.result == 32'h0) {
            bins res_zero    = {1'b1};
            bins res_nonzero = {1'b0};
        }

        cross_signs: cross cp_rs1, cp_rs2;
    endgroup

    // =========================================================================
    // 2. cg_mulh: Signed Upper 32-bit Product Covergroup
    // =========================================================================
    covergroup cg_mulh;
        option.per_instance = 1;
        option.name = "cg_mulh";

        cp_rs1_sign: coverpoint s_rs1 {
            bins zero    = {32'sd0};
            bins pos     = {[32'sd1 : 32'sh7FFF_FFFF]};
            bins neg     = {[-32'sd2147483648 : -32'sd1]};
            bins max_pos = {32'sh7FFF_FFFF};
            bins max_neg = {-32'sd2147483648};
        }

        cp_rs2_sign: coverpoint s_rs2 {
            bins zero    = {32'sd0};
            bins pos     = {[32'sd1 : 32'sh7FFF_FFFF]};
            bins neg     = {[-32'sd2147483648 : -32'sd1]};
            bins max_pos = {32'sh7FFF_FFFF};
            bins max_neg = {-32'sd2147483648};
        }

        cp_res_upper: coverpoint t_item.result {
            bins upper_zero    = {32'h0000_0000};
            bins upper_minus1  = {32'hFFFF_FFFF};
            bins maxneg_corner = {32'h4000_0000}; // (-2^31 * -2^31) upper
            bins others        = default;
        }

        cross_mulh_signs: cross cp_rs1_sign, cp_rs2_sign;
    endgroup

    // =========================================================================
    // 3. cg_mulhsu: Signed x Unsigned Upper Product Covergroup
    // =========================================================================
    covergroup cg_mulhsu;
        option.per_instance = 1;
        option.name = "cg_mulhsu";

        cp_rs1_signed: coverpoint s_rs1 {
            bins zero    = {32'sd0};
            bins pos     = {[32'sd1 : 32'sh7FFF_FFFF]};
            bins neg     = {[-32'sd2147483648 : -32'sd1]};
            bins max_neg = {-32'sd2147483648};
        }

        cp_rs2_unsigned: coverpoint t_item.rs2 {
            bins zero      = {32'h0000_0000};
            bins one       = {32'h0000_0001};
            bins low_half  = {[32'h2 : 32'h7FFF_FFFF]};
            bins high_half = {[32'h8000_0000 : 32'hFFFF_FFFF]};
            bins max_u     = {32'hFFFF_FFFF};
        }

        cross_mulhsu: cross cp_rs1_signed, cp_rs2_unsigned;
    endgroup

    // =========================================================================
    // 4. cg_mulhu: Unsigned x Unsigned Upper Product Covergroup
    // =========================================================================
    covergroup cg_mulhu;
        option.per_instance = 1;
        option.name = "cg_mulhu";

        cp_rs1_u: coverpoint t_item.rs1 {
            bins zero      = {32'h0000_0000};
            bins one       = {32'h0000_0001};
            bins low_half  = {[32'h2 : 32'h7FFF_FFFF]};
            bins high_half = {[32'h8000_0000 : 32'hFFFF_FFFE]};
            bins max_u     = {32'hFFFF_FFFF};
        }

        cp_rs2_u: coverpoint t_item.rs2 {
            bins zero      = {32'h0000_0000};
            bins one       = {32'h0000_0001};
            bins low_half  = {[32'h2 : 32'h7FFF_FFFF]};
            bins high_half = {[32'h8000_0000 : 32'hFFFF_FFFE]};
            bins max_u     = {32'hFFFF_FFFF};
        }

        cp_res_u_corner: coverpoint t_item.result {
            bins max_saturation = {32'hFFFF_FFFE}; // MaxU * MaxU upper
            bins zero           = {32'h0000_0000};
            bins others         = default;
        }

        cross_mulhu: cross cp_rs1_u, cp_rs2_u;
    endgroup

    // =========================================================================
    // 5. cg_div: Signed Division Covergroup
    // =========================================================================
    covergroup cg_div;
        option.per_instance = 1;
        option.name = "cg_div";

        cp_rs1_s: coverpoint s_rs1 {
            bins zero    = {32'sd0};
            bins pos     = {[32'sd1 : 32'sh7FFF_FFFF]};
            bins neg     = {[-32'sd2147483648 : -32'sd1]};
            bins max_neg = {-32'sd2147483648};
        }

        cp_rs2_s: coverpoint s_rs2 {
            bins zero    = {32'sd0};
            bins pos     = {[32'sd1 : 32'sh7FFF_FFFF]};
            bins neg     = {[-32'sd2147483648 : -32'sd1]};
            bins minus1  = {-32'sd1};
        }

        cp_corners: coverpoint {t_item.is_div_by_zero(), t_item.is_signed_overflow()} {
            bins normal          = {2'b00};
            bins div_by_zero     = {2'b10};
            bins signed_overflow = {2'b01};
        }

        cp_self_div: coverpoint (t_item.rs1 == t_item.rs2 && t_item.rs2 != 0) {
            bins self_div = {1'b1};
        }

        cross_div_signs: cross cp_rs1_s, cp_rs2_s;
    endgroup

    // =========================================================================
    // 6. cg_divu: Unsigned Division Covergroup
    // =========================================================================
    covergroup cg_divu;
        option.per_instance = 1;
        option.name = "cg_divu";

        cp_rs1_u: coverpoint t_item.rs1 {
            bins zero   = {32'h0000_0000};
            bins low    = {[32'h1 : 32'h0000_00FF]};
            bins mid    = {[32'h0000_0100 : 32'h7FFF_FFFF]};
            bins high   = {[32'h8000_0000 : 32'hFFFF_FFFF]};
        }

        cp_rs2_u: coverpoint t_item.rs2 {
            bins zero   = {32'h0000_0000}; // Div-by-zero
            bins one    = {32'h0000_0001};
            bins low    = {[32'h2 : 32'h0000_00FF]};
            bins mid    = {[32'h0000_0100 : 32'h7FFF_FFFF]};
            bins high   = {[32'h8000_0000 : 32'hFFFF_FFFF]};
        }

        cp_less_than: coverpoint (t_item.rs1 < t_item.rs2 && t_item.rs2 != 0) {
            bins quotient_zero = {1'b1};
        }

        cross_divu: cross cp_rs1_u, cp_rs2_u;
    endgroup

    // =========================================================================
    // 7. cg_rem: Signed Remainder Covergroup
    // =========================================================================
    covergroup cg_rem;
        option.per_instance = 1;
        option.name = "cg_rem";

        cp_rs1_s: coverpoint s_rs1 {
            bins zero    = {32'sd0};
            bins pos     = {[32'sd1 : 32'sh7FFF_FFFF]};
            bins neg     = {[-32'sd2147483648 : -32'sd1]};
            bins max_neg = {-32'sd2147483648};
        }

        cp_rs2_s: coverpoint s_rs2 {
            bins zero    = {32'sd0};
            bins pos     = {[32'sd1 : 32'sh7FFF_FFFF]};
            bins neg     = {[-32'sd2147483648 : -32'sd1]};
            bins minus1  = {-32'sd1};
        }

        cp_rem_zero: coverpoint (t_item.result == 32'h0) {
            bins exact_div = {1'b1};
        }

        cp_corners: coverpoint {t_item.is_div_by_zero(), t_item.is_signed_overflow()} {
            bins normal          = {2'b00};
            bins rem_by_zero     = {2'b10};
            bins signed_overflow = {2'b01};
        }

        cross_rem_signs: cross cp_rs1_s, cp_rs2_s;
    endgroup

    // =========================================================================
    // 8. cg_remu: Unsigned Remainder Covergroup
    // =========================================================================
    covergroup cg_remu;
        option.per_instance = 1;
        option.name = "cg_remu";

        cp_rs1_u: coverpoint t_item.rs1 {
            bins zero = {32'h0000_0000};
            bins mid  = {[32'h1 : 32'h7FFF_FFFF]};
            bins high = {[32'h8000_0000 : 32'hFFFF_FFFF]};
        }

        cp_rs2_u: coverpoint t_item.rs2 {
            bins zero = {32'h0000_0000}; // Remu-by-zero
            bins mid  = {[32'h1 : 32'h7FFF_FFFF]};
            bins high = {[32'h8000_0000 : 32'hFFFF_FFFF]};
        }

        cp_remu_zero: coverpoint (t_item.result == 32'h0) {
            bins exact_multiple = {1'b1};
        }

        cp_remu_less_than: coverpoint (t_item.rs1 < t_item.rs2 && t_item.rs2 != 0) {
            bins returns_dividend = {1'b1};
        }

        cross_remu: cross cp_rs1_u, cp_rs2_u;
    endgroup

    // ── Constructor ──────────────────────────────────────────────────────────
    function new(string name = "rv32m_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_instruction = new();
        cg_mul         = new();
        cg_mulh        = new();
        cg_mulhsu      = new();
        cg_mulhu       = new();
        cg_div         = new();
        cg_divu        = new();
        cg_rem         = new();
        cg_remu        = new();
        `uvm_info("COVERAGE", "Constructed rv32m_coverage with 8 instruction covergroups", UVM_HIGH)
    endfunction

    // ── Sample Incoming Monitored Transaction ────────────────────────────────
    virtual function void write(rv32m_transaction t);
        t_item = t;
        s_rs1  = t.rs1;
        s_rs2  = t.rs2;
        s_res  = t.result;

        // Sample global instruction & register covergroup
        cg_instruction.sample();

        // Sample targeted covergroup based on funct3
        case (t.funct3)
            OP_MUL:    cg_mul.sample();
            OP_MULH:   cg_mulh.sample();
            OP_MULHSU: cg_mulhsu.sample();
            OP_MULHU:  cg_mulhu.sample();
            OP_DIV:    cg_div.sample();
            OP_DIVU:   cg_divu.sample();
            OP_REM:    cg_rem.sample();
            OP_REMU:   cg_remu.sample();
            default: ;
        endcase
    endfunction

    // ── Report Phase ─────────────────────────────────────────────────────────
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("COV_REPORT", "==================================================================", UVM_NONE)
        `uvm_info("COV_REPORT", "              RV32M FUNCTIONAL COVERAGE REPORT                    ", UVM_NONE)
        `uvm_info("COV_REPORT", "==================================================================", UVM_NONE)
        `uvm_info("COV_REPORT", $sformatf(" Total Overall Coverage : %6.2f %%", $get_coverage()), UVM_NONE)
        `uvm_info("COV_REPORT", $sformatf(" - Instruction Opcode   : %6.2f %%", cg_instruction.get_inst_coverage()), UVM_NONE)
        `uvm_info("COV_REPORT", $sformatf(" - MUL Covergroup       : %6.2f %%", cg_mul.get_inst_coverage()), UVM_NONE)
        `uvm_info("COV_REPORT", $sformatf(" - MULH Covergroup      : %6.2f %%", cg_mulh.get_inst_coverage()), UVM_NONE)
        `uvm_info("COV_REPORT", $sformatf(" - MULHSU Covergroup    : %6.2f %%", cg_mulhsu.get_inst_coverage()), UVM_NONE)
        `uvm_info("COV_REPORT", $sformatf(" - MULHU Covergroup     : %6.2f %%", cg_mulhu.get_inst_coverage()), UVM_NONE)
        `uvm_info("COV_REPORT", $sformatf(" - DIV Covergroup       : %6.2f %%", cg_div.get_inst_coverage()), UVM_NONE)
        `uvm_info("COV_REPORT", $sformatf(" - DIVU Covergroup      : %6.2f %%", cg_divu.get_inst_coverage()), UVM_NONE)
        `uvm_info("COV_REPORT", $sformatf(" - REM Covergroup       : %6.2f %%", cg_rem.get_inst_coverage()), UVM_NONE)
        `uvm_info("COV_REPORT", $sformatf(" - REMU Covergroup      : %6.2f %%", cg_remu.get_inst_coverage()), UVM_NONE)
        `uvm_info("COV_REPORT", "==================================================================", UVM_NONE)
    endfunction

endclass : rv32m_coverage

`endif // COVERAGE_SV
