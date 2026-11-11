`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// File Name   : rv32m_coverage.sv
// Module Name : rv32m_coverage
//
// Description:
//   SystemVerilog Functional Coverage model for RISC-V RV32M Extension.
//   Defines exactly ONE dedicated covergroup for each of the 8 instructions:
//     1. cg_mul    (MUL    : funct3 = 3'b000)
//     2. cg_mulh   (MULH   : funct3 = 3'b001)
//     3. cg_mulhsu (MULHSU : funct3 = 3'b010)
//     4. cg_mulhu  (MULHU  : funct3 = 3'b011)
//     5. cg_div    (DIV    : funct3 = 3'b100)
//     6. cg_divu   (DIVU   : funct3 = 3'b101)
//     7. cg_rem    (REM    : funct3 = 3'b110)
//     8. cg_remu   (REMU   : funct3 = 3'b111)
//
//   Each covergroup specifies extensive coverpoints for:
//     - Operand values and corner cases (0, 1, -1, MaxPos, MaxNeg, MaxUnsigned)
//     - Power-of-2 walking bit patterns
//     - Sign permutation cross-coverage (+/+, +/-, -/+, -/-)
//     - Special RISC-V edge cases (divide-by-zero, signed overflow)
//     - Destination register (rd) coverage (x0, ra, sp, a0-a7, s0-s11, t0-t6)
//     - Result characteristics (zero, positive, negative, upper-half truncation)
//////////////////////////////////////////////////////////////////////////////////

package rv32m_cov_pkg;

    // =========================================================================
    // 1. COVERGROUP: MUL (funct3 = 000)
    // Signed * Signed -> Lower 32 bits of 64-bit product
    // =========================================================================
    covergroup cg_mul with function sample(
        input logic [31:0] rs1,
        input logic [31:0] rs2,
        input logic [31:0] result,
        input logic [4:0]  rd
    );
        option.per_instance = 1;
        option.name = "cg_mul";

        // Multiplicand (Signed)
        cp_rs1_val: coverpoint rs1 {
            bins zero        = {32'h0000_0000};
            bins one         = {32'h0000_0001};
            bins minus_one   = {32'hFFFF_FFFF};
            bins max_pos     = {32'h7FFF_FFFF};
            bins max_neg     = {32'h8000_0000};
            bins small_pos   = {[32'd2 : 32'd255]};
            bins medium_pos  = {[32'd256 : 32'h00FF_FFFF]};
            bins large_pos   = {[32'h0100_0000 : 32'h7FFF_FFFE]};
            bins small_neg   = {[-32'd255 : -32'd2]};
            bins large_neg   = {[32'h8000_0001 : -32'd256]};
            bins powers_of_2[] = {32'h2, 32'h4, 32'h8, 32'h10, 32'h20, 32'h40, 32'h80,
                                  32'h100, 32'h200, 32'h400, 32'h800, 32'h1000, 32'h2000,
                                  32'h4000, 32'h8000, 32'h10000, 32'h20000, 32'h40000,
                                  32'h80000, 32'h100000, 32'h200000, 32'h400000, 32'h800000,
                                  32'h1000000, 32'h2000000, 32'h4000000, 32'h8000000,
                                  32'h10000000, 32'h20000000, 32'h40000000};
        }

        // Multiplier (Signed)
        cp_rs2_val: coverpoint rs2 {
            bins zero        = {32'h0000_0000};
            bins one         = {32'h0000_0001};
            bins minus_one   = {32'hFFFF_FFFF};
            bins max_pos     = {32'h7FFF_FFFF};
            bins max_neg     = {32'h8000_0000};
            bins small_pos   = {[32'd2 : 32'd255]};
            bins large_pos   = {[32'd256 : 32'h7FFF_FFFE]};
            bins small_neg   = {[-32'd255 : -32'd2]};
            bins large_neg   = {[32'h8000_0001 : -32'd256]};
        }

        // Sign permuted cross
        cp_rs1_sign: coverpoint rs1[31] { bins pos = {0}; bins neg = {1}; }
        cp_rs2_sign: coverpoint rs2[31] { bins pos = {0}; bins neg = {1}; }
        x_signs: cross cp_rs1_sign, cp_rs2_sign;

        // Destination Register
        cp_rd: coverpoint rd {
            bins x0_zero   = {5'd0};
            bins x1_ra     = {5'd1};
            bins x2_sp     = {5'd2};
            bins a0_a7     = {[5'd10 : 5'd17]};
            bins s0_s11    = {5'd8, 5'd9, [5'd18 : 5'd27]};
            bins t0_t6     = {[5'd5 : 5'd7], [5'd28 : 5'd31]};
        }

        // Result lower 32-bit characteristics
        cp_res: coverpoint result {
            bins res_zero     = {32'h0000_0000};
            bins res_one      = {32'h0000_0001};
            bins res_neg_one  = {32'hFFFF_FFFF};
            bins res_positive = {[32'd1 : 32'h7FFF_FFFF]};
            bins res_negative = {[32'h8000_0000 : 32'hFFFF_FFFE]};
        }
    endgroup


    // =========================================================================
    // 2. COVERGROUP: MULH (funct3 = 001)
    // Signed * Signed -> Upper 32 bits of 64-bit product
    // =========================================================================
    covergroup cg_mulh with function sample(
        input logic [31:0] rs1,
        input logic [31:0] rs2,
        input logic [31:0] result,
        input logic [4:0]  rd
    );
        option.per_instance = 1;
        option.name = "cg_mulh";

        cp_rs1_val: coverpoint rs1 {
            bins zero      = {32'h0000_0000};
            bins max_pos   = {32'h7FFF_FFFF};
            bins max_neg   = {32'h8000_0000};
            bins minus_one = {32'hFFFF_FFFF};
            bins one       = {32'h0000_0001};
            bins pos_range = {[32'd2 : 32'h7FFF_FFFE]};
            bins neg_range = {[32'h8000_0001 : -32'd2]};
        }

        cp_rs2_val: coverpoint rs2 {
            bins zero      = {32'h0000_0000};
            bins max_pos   = {32'h7FFF_FFFF};
            bins max_neg   = {32'h8000_0000};
            bins minus_one = {32'hFFFF_FFFF};
            bins one       = {32'h0000_0001};
            bins pos_range = {[32'd2 : 32'h7FFF_FFFE]};
            bins neg_range = {[32'h8000_0001 : -32'd2]};
        }

        // Key case: MaxNeg * MaxNeg -> (-2^31) * (-2^31) = +2^62 (upper is 0x4000_0000)
        cp_maxneg_x_maxneg: cross cp_rs1_val, cp_rs2_val {
            bins maxneg_corner = binsof(cp_rs1_val.max_neg) && binsof(cp_rs2_val.max_neg);
        }

        // Upper 32-bit result characteristics
        cp_result: coverpoint result {
            bins upper_zero     = {32'h0000_0000};      // Product < 2^31
            bins upper_neg_one  = {32'hFFFF_FFFF};      // Negative product upper sign extension
            bins upper_pos_max  = {32'h4000_0000};      // Max possible signed upper product
            bins upper_general  = default;
        }

        cp_rd: coverpoint rd {
            bins gpr[] = {[5'd0 : 5'd31]};
        }
    endgroup


    // =========================================================================
    // 3. COVERGROUP: MULHSU (funct3 = 010)
    // Signed (rs1) * Unsigned (rs2) -> Upper 32 bits
    // =========================================================================
    covergroup cg_mulhsu with function sample(
        input logic [31:0] rs1,
        input logic [31:0] rs2,
        input logic [31:0] result,
        input logic [4:0]  rd
    );
        option.per_instance = 1;
        option.name = "cg_mulhsu";

        // Signed Multiplicand rs1
        cp_rs1_signed: coverpoint rs1 {
            bins zero      = {32'h0000_0000};
            bins one       = {32'h0000_0001};
            bins minus_one = {32'hFFFF_FFFF};
            bins max_pos   = {32'h7FFF_FFFF};
            bins max_neg   = {32'h8000_0000};
            bins pos_mid   = {[32'd2 : 32'h7FFF_FFFE]};
            bins neg_mid   = {[32'h8000_0001 : -32'd2]};
        }

        // Unsigned Multiplier rs2 (tests unsigned interpretation when MSB=1)
        cp_rs2_unsigned: coverpoint rs2 {
            bins zero          = {32'h0000_0000};
            bins one           = {32'h0000_0001};
            bins small         = {[32'd2 : 32'd255]};
            bins msb_zero      = {[32'd256 : 32'h7FFF_FFFF]};
            bins msb_one       = {[32'h8000_0000 : 32'hFFFF_FFFE]}; // Critical: bit 31 set, treated as unsigned!
            bins max_unsigned  = {32'hFFFF_FFFF};
        }

        // Cross signed rs1 with unsigned rs2
        x_signed_unsigned: cross cp_rs1_signed, cp_rs2_unsigned;

        // Result upper half
        cp_result: coverpoint result {
            bins upper_zero    = {32'h0000_0000};
            bins upper_all_ones= {32'hFFFF_FFFF}; // rs1=-1, rs2 small
            bins upper_other   = default;
        }

        cp_rd: coverpoint rd { bins gpr[] = {[5'd0 : 5'd31]}; }
    endgroup


    // =========================================================================
    // 4. COVERGROUP: MULHU (funct3 = 011)
    // Unsigned * Unsigned -> Upper 32 bits
    // =========================================================================
    covergroup cg_mulhu with function sample(
        input logic [31:0] rs1,
        input logic [31:0] rs2,
        input logic [31:0] result,
        input logic [4:0]  rd
    );
        option.per_instance = 1;
        option.name = "cg_mulhu";

        cp_rs1_u: coverpoint rs1 {
            bins zero        = {32'h0000_0000};
            bins one         = {32'h0000_0001};
            bins lower_half  = {[32'd2 : 32'h7FFF_FFFF]};
            bins upper_half  = {[32'h8000_0000 : 32'hFFFF_FFFE]};
            bins max_u32     = {32'hFFFF_FFFF};
        }

        cp_rs2_u: coverpoint rs2 {
            bins zero        = {32'h0000_0000};
            bins one         = {32'h0000_0001};
            bins lower_half  = {[32'd2 : 32'h7FFF_FFFF]};
            bins upper_half  = {[32'h8000_0000 : 32'hFFFF_FFFE]};
            bins max_u32     = {32'hFFFF_FFFF};
        }

        // Corner case: MaxU32 * MaxU32 = 0xFFFFFFFE_00000001 -> upper is 0xFFFFFFFE
        x_max_corner: cross cp_rs1_u, cp_rs2_u {
            bins max_x_max = binsof(cp_rs1_u.max_u32) && binsof(cp_rs2_u.max_u32);
        }

        // Result coverage
        cp_result: coverpoint result {
            bins zero          = {32'h0000_0000}; // Product fits in 32 bits
            bins max_upper_res = {32'hFFFF_FFFE}; // 0xFFFFFFFF * 0xFFFFFFFF
            bins non_zero      = {[32'd1 : 32'hFFFF_FFFD]};
        }

        cp_rd: coverpoint rd { bins gpr[] = {[5'd0 : 5'd31]}; }
    endgroup


    // =========================================================================
    // 5. COVERGROUP: DIV (funct3 = 100)
    // Signed / Signed Division
    // =========================================================================
    covergroup cg_div with function sample(
        input logic [31:0] rs1,
        input logic [31:0] rs2,
        input logic [31:0] result,
        input logic [4:0]  rd
    );
        option.per_instance = 1;
        option.name = "cg_div";

        // Dividend rs1 (Signed)
        cp_dividend: coverpoint rs1 {
            bins zero      = {32'h0000_0000};
            bins one       = {32'h0000_0001};
            bins minus_one = {32'hFFFF_FFFF};
            bins max_pos   = {32'h7FFF_FFFF};
            bins max_neg   = {32'h8000_0000}; // Overflow trigger with -1 divisor
            bins pos_mid   = {[32'd2 : 32'h7FFF_FFFE]};
            bins neg_mid   = {[32'h8000_0001 : -32'd2]};
        }

        // Divisor rs2 (Signed)
        cp_divisor: coverpoint rs2 {
            bins zero        = {32'h0000_0000}; // Divide-by-zero corner case
            bins one         = {32'h0000_0001}; // Identity
            bins minus_one   = {32'hFFFF_FFFF}; // Signed overflow trigger
            bins max_pos     = {32'h7FFF_FFFF};
            bins max_neg     = {32'h8000_0000};
            bins powers_of_2 = {32'd2, 32'd4, 32'd8, 32'd16, 32'd32, 32'd64, 32'd128, 32'd256};
            bins pos_other   = default;
        }

        // Sign permuted divisions (+/+, +/-, -/+, -/-)
        cp_s1_sign: coverpoint rs1[31] { bins pos = {0}; bins neg = {1}; }
        cp_s2_sign: coverpoint rs2[31] { bins pos = {0}; bins neg = {1}; }
        x_div_signs: cross cp_s1_sign, cp_s2_sign;

        // Specific RISC-V Hardware Edge Cases
        cp_corner_cases: cross cp_dividend, cp_divisor {
            // 1. Divide by Zero (x / 0 = -1 / 0xFFFFFFFF)
            bins div_by_zero = binsof(cp_divisor.zero);
            // 2. Signed Overflow (-2^31 / -1 = -2^31 / 0x80000000)
            bins signed_overflow = binsof(cp_dividend.max_neg) && binsof(cp_divisor.minus_one);
            // 3. Self division (x / x = 1)
            bins self_div_pos = binsof(cp_dividend.max_pos) && binsof(cp_divisor.max_pos);
            bins self_div_neg = binsof(cp_dividend.max_neg) && binsof(cp_divisor.max_neg);
        }

        // Quotient Result Characteristics
        cp_quotient: coverpoint result {
            bins q_zero      = {32'h0000_0000}; // |rs1| < |rs2|
            bins q_one       = {32'h0000_0001};
            bins q_minus_one = {32'hFFFF_FFFF}; // Divide by zero return
            bins q_overflow  = {32'h8000_0000}; // Signed overflow return
            bins q_positive  = {[32'd2 : 32'h7FFF_FFFF]};
            bins q_negative  = {[32'h8000_0001 : -32'd2]};
        }

        cp_rd: coverpoint rd { bins gpr[] = {[5'd0 : 5'd31]}; }
    endgroup


    // =========================================================================
    // 6. COVERGROUP: DIVU (funct3 = 101)
    // Unsigned / Unsigned Division
    // =========================================================================
    covergroup cg_divu with function sample(
        input logic [31:0] rs1,
        input logic [31:0] rs2,
        input logic [31:0] result,
        input logic [4:0]  rd
    );
        option.per_instance = 1;
        option.name = "cg_divu";

        cp_dividend_u: coverpoint rs1 {
            bins zero        = {32'h0000_0000};
            bins one         = {32'h0000_0001};
            bins mid_vals    = {[32'd2 : 32'h7FFF_FFFF]};
            bins high_bit_set= {[32'h8000_0000 : 32'hFFFF_FFFE]};
            bins max_u32     = {32'hFFFF_FFFF};
        }

        cp_divisor_u: coverpoint rs2 {
            bins zero        = {32'h0000_0000}; // Divide by zero
            bins one         = {32'h0000_0001}; // Identity
            bins powers_of_2 = {32'd2, 32'd4, 32'd8, 32'd16, 32'd32, 32'd64, 32'd128, 32'd256, 32'd1024, 32'd65536};
            bins high_bit_set= {[32'h8000_0000 : 32'hFFFF_FFFE]};
            bins max_u32     = {32'hFFFF_FFFF};
        }

        // Relative Magnitude Cross
        cp_div_by_zero: cross cp_dividend_u, cp_divisor_u {
            bins div_zero = binsof(cp_divisor_u.zero);
        }

        cp_quotient_u: coverpoint result {
            bins q_zero      = {32'h0000_0000}; // rs1 < rs2
            bins q_one       = {32'h0000_0001}; // rs1 == rs2
            bins q_max_u32   = {32'hFFFF_FFFF}; // Div by zero return (2^32 - 1)
            bins q_range     = {[32'd2 : 32'hFFFF_FFFE]};
        }

        cp_rd: coverpoint rd { bins gpr[] = {[5'd0 : 5'd31]}; }
    endgroup


    // =========================================================================
    // 7. COVERGROUP: REM (funct3 = 110)
    // Signed % Signed Remainder
    // =========================================================================
    covergroup cg_rem with function sample(
        input logic [31:0] rs1,
        input logic [31:0] rs2,
        input logic [31:0] result,
        input logic [4:0]  rd
    );
        option.per_instance = 1;
        option.name = "cg_rem";

        cp_dividend: coverpoint rs1 {
            bins zero      = {32'h0000_0000};
            bins one       = {32'h0000_0001};
            bins max_pos   = {32'h7FFF_FFFF};
            bins max_neg   = {32'h8000_0000};
            bins pos_range = {[32'd2 : 32'h7FFF_FFFE]};
            bins neg_range = {[32'h8000_0001 : 32'hFFFF_FFFF]};
        }

        cp_divisor: coverpoint rs2 {
            bins zero      = {32'h0000_0000}; // Remainder by zero
            bins one       = {32'h0000_0001}; // Remainder always 0
            bins minus_one = {32'hFFFF_FFFF}; // Overflow remainder -> 0
            bins max_pos   = {32'h7FFF_FFFF};
            bins max_neg   = {32'h8000_0000};
            bins other     = default;
        }

        // Remainder Sign Rule (Sign MUST match dividend)
        cp_s1_sign: coverpoint rs1[31] { bins pos = {0}; bins neg = {1}; }
        cp_res_sign: coverpoint result[31] { bins pos = {0}; bins neg = {1}; }
        x_rem_sign_match: cross cp_s1_sign, cp_res_sign {
            // Illegal / unwanted condition: positive dividend producing negative remainder
            ignore_bins pos_div_neg_rem = binsof(cp_s1_sign.pos) && binsof(cp_res_sign.neg);
            // Illegal condition: negative dividend producing positive remainder (when non-zero)
            // Note: zero remainder has sign bit 0
        }

        // Corner cases
        cp_rem_corners: cross cp_dividend, cp_divisor {
            bins rem_by_zero = binsof(cp_divisor.zero); // Should return dividend rs1
            bins rem_overflow= binsof(cp_dividend.max_neg) && binsof(cp_divisor.minus_one); // Returns 0
        }

        // Remainder values
        cp_remainder: coverpoint result {
            bins zero         = {32'h0000_0000}; // Exact division
            bins pos_rem      = {[32'd1 : 32'h7FFF_FFFF]};
            bins neg_rem      = {[32'h8000_0000 : 32'hFFFF_FFFF]};
        }

        cp_rd: coverpoint rd { bins gpr[] = {[5'd0 : 5'd31]}; }
    endgroup


    // =========================================================================
    // 8. COVERGROUP: REMU (funct3 = 111)
    // Unsigned % Unsigned Remainder
    // =========================================================================
    covergroup cg_remu with function sample(
        input logic [31:0] rs1,
        input logic [31:0] rs2,
        input logic [31:0] result,
        input logic [4:0]  rd
    );
        option.per_instance = 1;
        option.name = "cg_remu";

        cp_dividend_u: coverpoint rs1 {
            bins zero     = {32'h0000_0000};
            bins one      = {32'h0000_0001};
            bins mid_u    = {[32'd2 : 32'h7FFF_FFFF]};
            bins high_u   = {[32'h8000_0000 : 32'hFFFF_FFFE]};
            bins max_u32  = {32'hFFFF_FFFF};
        }

        cp_divisor_u: coverpoint rs2 {
            bins zero     = {32'h0000_0000}; // Remainder by zero
            bins one      = {32'h0000_0001}; // Remainder always 0
            bins mid_u    = {[32'd2 : 32'h7FFF_FFFF]};
            bins high_u   = {[32'h8000_0000 : 32'hFFFF_FFFE]};
            bins max_u32  = {32'hFFFF_FFFF};
        }

        // Corner case: rem by zero
        cp_remu_by_zero: cross cp_dividend_u, cp_divisor_u {
            bins remu_zero = binsof(cp_divisor_u.zero);
        }

        // Remainder output
        cp_rem_val: coverpoint result {
            bins zero      = {32'h0000_0000}; // Exact division
            bins non_zero  = {[32'd1 : 32'hFFFF_FFFE]};
            bins max_u32   = {32'hFFFF_FFFF}; // Only when rs1=0xFFFFFFFF and rs2=0
        }

        cp_rd: coverpoint rd { bins gpr[] = {[5'd0 : 5'd31]}; }
    endgroup

    // =========================================================================
    // Coverage Collector Class
    // =========================================================================
    class rv32m_coverage_collector;
        cg_mul    cov_mul;
        cg_mulh   cov_mulh;
        cg_mulhsu cov_mulhsu;
        cg_mulhu  cov_mulhu;
        cg_div    cov_div;
        cg_divu   cov_divu;
        cg_rem    cov_rem;
        cg_remu   cov_remu;

        function new();
            cov_mul    = new();
            cov_mulh   = new();
            cov_mulhsu = new();
            cov_mulhu  = new();
            cov_div    = new();
            cov_divu   = new();
            cov_rem    = new();
            cov_remu   = new();
        endfunction

        function void sample(
            input logic [2:0]  funct3,
            input logic [31:0] rs1,
            input logic [31:0] rs2,
            input logic [31:0] result,
            input logic [4:0]  rd
        );
            case (funct3)
                3'b000: cov_mul.sample(rs1, rs2, result, rd);
                3'b001: cov_mulh.sample(rs1, rs2, result, rd);
                3'b010: cov_mulhsu.sample(rs1, rs2, result, rd);
                3'b011: cov_mulhu.sample(rs1, rs2, result, rd);
                3'b100: cov_div.sample(rs1, rs2, result, rd);
                3'b101: cov_divu.sample(rs1, rs2, result, rd);
                3'b110: cov_rem.sample(rs1, rs2, result, rd);
                3'b111: cov_remu.sample(rs1, rs2, result, rd);
            endcase
        endfunction

        function void report();
            $display("\n==================================================================");
            $display("              RV32M FUNCTIONAL COVERAGE REPORT                    ");
            $display("==================================================================");
            $display(" 1. MUL    Coverage : %0.2f %%", cov_mul.get_coverage());
            $display(" 2. MULH   Coverage : %0.2f %%", cov_mulh.get_coverage());
            $display(" 3. MULHSU Coverage : %0.2f %%", cov_mulhsu.get_coverage());
            $display(" 4. MULHU  Coverage : %0.2f %%", cov_mulhu.get_coverage());
            $display(" 5. DIV    Coverage : %0.2f %%", cov_div.get_coverage());
            $display(" 6. DIVU   Coverage : %0.2f %%", cov_divu.get_coverage());
            $display(" 7. REM    Coverage : %0.2f %%", cov_rem.get_coverage());
            $display(" 8. REMU   Coverage : %0.2f %%", cov_remu.get_coverage());
            $display("==================================================================\n");
        endfunction
    endclass

endpackage : rv32m_cov_pkg

// =============================================================================
// Standalone Monitor Module (Can be bound to DUT or instantiated in TB)
// =============================================================================
module rv32m_coverage_monitor (
    input logic        clk,
    input logic        rst_n,
    input logic [31:0] rs1,
    input logic [31:0] rs2,
    input logic [2:0]  funct3,
    input logic [4:0]  rd_in,
    input logic        valid_in,
    input logic        stall,
    input logic [31:0] result,
    input logic [4:0]  rd_out,
    input logic        valid_out
);
    import rv32m_cov_pkg::*;

    // Shadow registers to capture inputs on valid_in
    logic [31:0] s_rs1;
    logic [31:0] s_rs2;
    logic [2:0]  s_funct3;
    logic [4:0]  s_rd;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_rs1    <= '0;
            s_rs2    <= '0;
            s_funct3 <= '0;
            s_rd     <= '0;
        end else if (valid_in) begin
            s_rs1    <= rs1;
            s_rs2    <= rs2;
            s_funct3 <= funct3;
            s_rd     <= rd_in;
        end
    end

    // Instantiate Covergroups
    cg_mul    u_cg_mul    = new();
    cg_mulh   u_cg_mulh   = new();
    cg_mulhsu u_cg_mulhsu = new();
    cg_mulhu  u_cg_mulhu  = new();
    cg_div    u_cg_div    = new();
    cg_divu   u_cg_divu   = new();
    cg_rem    u_cg_rem    = new();
    cg_remu   u_cg_remu   = new();

    // Sample covergroup corresponding to the completed operation when valid_out pulses
    always_ff @(posedge clk) begin
        if (rst_n && valid_out) begin
            case (s_funct3)
                3'b000: u_cg_mul.sample(s_rs1, s_rs2, result, rd_out);
                3'b001: u_cg_mulh.sample(s_rs1, s_rs2, result, rd_out);
                3'b010: u_cg_mulhsu.sample(s_rs1, s_rs2, result, rd_out);
                3'b011: u_cg_mulhu.sample(s_rs1, s_rs2, result, rd_out);
                3'b100: u_cg_div.sample(s_rs1, s_rs2, result, rd_out);
                3'b101: u_cg_divu.sample(s_rs1, s_rs2, result, rd_out);
                3'b110: u_cg_rem.sample(s_rs1, s_rs2, result, rd_out);
                3'b111: u_cg_remu.sample(s_rs1, s_rs2, result, rd_out);
            endcase
        end
    end

endmodule
