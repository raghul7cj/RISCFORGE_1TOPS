`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// File Name   : rv32m_assertions.sv
// Module Name : rv32m_assertions
//
// Description:
//   Formal and Dynamic SystemVerilog Assertions (SVA) for rv32m_unit.
//   Verifies:
//     1. Protocol Handshakes (stall assertion on cycle 0, 1-cycle valid_out pulse,
//        submodule mutual exclusion).
//     2. Multiplier Latency & Timing (fixed 3 cycles, 3-cycle stall duration).
//     3. Divider FSM & Fast Path Timing (1-cycle corner exit for divide-by-zero
//        and signed overflow, 34-cycle standard non-restoring loop).
//     4. Data Integrity (No X/Z unknown values on valid outputs, rd index preservation).
//     5. RISC-V Specification Compliance (division-by-zero outputs, overflow outputs,
//        remainder sign invariants).
//////////////////////////////////////////////////////////////////////////////////

module rv32m_assertions (
    input logic        clk,
    input logic        rst_n,

    // Monitored Interface Ports
    input logic [31:0] rs1,
    input logic [31:0] rs2,
    input logic [2:0]  funct3,
    input logic [4:0]  rd_in,
    input logic        valid_in,
    input logic        stall,
    input logic [31:0] result,
    input logic [4:0]  rd_out,
    input logic        valid_out,

    // Internal Submodule Wires (for internal checking)
    input logic        mul_valid,
    input logic        div_valid,
    input logic        mul_stall,
    input logic        div_stall
);

    // Default clocking for all concurrent assertions
    default clocking def_clk @(posedge clk); endclocking
    default disable iff (!rst_n);

    // =========================================================================
    // SECTION 1: Interface & Protocol Assertions
    // =========================================================================

    // ASSERTION 1: Immediate Stall on Issue
    // When valid_in is high, stall MUST be asserted in the exact same cycle
    property p_stall_immediate;
        valid_in |-> stall;
    endproperty
    a_stall_immediate: assert property (p_stall_immediate)
        else $error("[SVA VIOLATION #1] Pipeline stall missing on valid_in cycle!");

    // ASSERTION 2: Submodule Mutual Exclusion
    // Multiplier and Divider must NEVER produce valid_out at the same cycle
    property p_mutex_submodules;
        not (mul_valid && div_valid);
    endproperty
    a_mutex_submodules: assert property (p_mutex_submodules)
        else $error("[SVA VIOLATION #2] Conflict! mul_valid and div_valid asserted simultaneously!");

    // ASSERTION 3: Single-Cycle Valid Out Pulse
    // valid_out must be an exact 1-cycle pulse; it cannot stay high across consecutive cycles
    property p_valid_out_single_cycle;
        valid_out |=> !valid_out;
    endproperty
    a_valid_out_single_cycle: assert property (p_valid_out_single_cycle)
        else $error("[SVA VIOLATION #3] valid_out stayed high for more than 1 clock cycle!");

    // ASSERTION 4: No X/Z on Outputs
    // When valid_out is high, result and rd_out must be completely resolved
    property p_no_unknown_outputs;
        valid_out |-> (!$isunknown(result) && !$isunknown(rd_out));
    endproperty
    a_no_unknown_outputs: assert property (p_no_unknown_outputs)
        else $error("[SVA VIOLATION #4] Output result or rd_out contains X/Z unknown values!");

    // ASSERTION 5: Destination Register (rd) Preservation
    // The rd_out index at completion must match the rd_in supplied at issue
    property p_rd_preservation;
        logic [4:0] saved_rd;
        (valid_in, saved_rd = rd_in) |-> ##[1:40] (valid_out && (rd_out == saved_rd));
    endproperty
    a_rd_preservation: assert property (p_rd_preservation)
        else $error("[SVA VIOLATION #5] Destination register rd corrupted during execution!");


    // =========================================================================
    // SECTION 2: Multiplier Timing & Latency Assertions
    // =========================================================================

    // ASSERTION 6: Multiplier 3-Cycle Latency
    // Any MUL operation (funct3[2] == 0) must assert valid_out in exactly 3 clock cycles
    property p_mul_exact_3cycles;
        (valid_in && !funct3[2]) |-> ##3 valid_out;
    endproperty
    a_mul_exact_3cycles: assert property (p_mul_exact_3cycles)
        else $error("[SVA VIOLATION #6] Multiplier latency is not exactly 3 cycles!");

    // ASSERTION 7: Multiplier Stall Duration
    // Multiplier stall must remain asserted for cycles 0, 1, and 2
    property p_mul_stall_duration;
        (valid_in && !funct3[2]) |-> (stall [*3]);
    endproperty
    a_mul_stall_duration: assert property (p_mul_stall_duration)
        else $error("[SVA VIOLATION #7] Multiplier stall did not hold for required 3 cycles!");


    // =========================================================================
    // SECTION 3: Divider FSM & Corner-Case Fast-Path Assertions
    // =========================================================================

    // ASSERTION 8: Divide-by-Zero Fast Path Timing (2 Cycles from valid_in)
    // Divisor == 0 must complete via fast path in 2 clock cycles (1 cycle latency in DUT)
    property p_div_zero_fast_timing;
        (valid_in && funct3[2] && (rs2 == 32'b0)) |-> ##2 valid_out;
    endproperty
    a_div_zero_fast_timing: assert property (p_div_zero_fast_timing)
        else $error("[SVA VIOLATION #8] Divide-by-zero did not take the 2-cycle fast path!");

    // ASSERTION 9: Divide-by-Zero DIV/DIVU Return Value
    // RISC-V Spec: x / 0 must return 32'hFFFF_FFFF (-1)
    property p_div_zero_quotient_result;
        (valid_in && (funct3 == 3'b100 || funct3 == 3'b101) && (rs2 == 32'b0)) |-> ##2 (result == 32'hFFFF_FFFF);
    endproperty
    a_div_zero_quotient_result: assert property (p_div_zero_quotient_result)
        else $error("[SVA VIOLATION #9] Divide-by-zero failed to return 0xFFFFFFFF for DIV/DIVU!");

    // ASSERTION 10: Remainder-by-Zero REM/REMU Return Value
    // RISC-V Spec: x % 0 must return the dividend x
    property p_rem_zero_remainder_result;
        logic [31:0] saved_dividend;
        (valid_in && (funct3 == 3'b110 || funct3 == 3'b111) && (rs2 == 32'b0), saved_dividend = rs1)
            |-> ##2 (result == saved_dividend);
    endproperty
    a_rem_zero_remainder_result: assert property (p_rem_zero_remainder_result)
        else $error("[SVA VIOLATION #10] Remainder-by-zero failed to preserve dividend x!");

    // ASSERTION 11: Signed Overflow Fast Path Timing
    // -2^31 / -1 (0x80000000 / 0xFFFFFFFF) must complete in 2 cycles
    property p_signed_overflow_fast_timing;
        (valid_in && (funct3 == 3'b100 || funct3 == 3'b110) && (rs1 == 32'h8000_0000) && (rs2 == 32'hFFFF_FFFF))
            |-> ##2 valid_out;
    endproperty
    a_signed_overflow_fast_timing: assert property (p_signed_overflow_fast_timing)
        else $error("[SVA VIOLATION #11] Signed overflow failed to trigger fast path!");

    // ASSERTION 12: Signed Overflow Return Values
    // RISC-V Spec: -2^31 / -1 -> -2^31 (0x80000000), -2^31 % -1 -> 0
    property p_signed_overflow_div_result;
        (valid_in && (funct3 == 3'b100) && (rs1 == 32'h8000_0000) && (rs2 == 32'hFFFF_FFFF))
            |-> ##2 (result == 32'h8000_0000);
    endproperty
    a_signed_overflow_div_result: assert property (p_signed_overflow_div_result)
        else $error("[SVA VIOLATION #12] Signed overflow DIV failed to return 0x80000000!");

    property p_signed_overflow_rem_result;
        (valid_in && (funct3 == 3'b110) && (rs1 == 32'h8000_0000) && (rs2 == 32'hFFFF_FFFF))
            |-> ##2 (result == 32'h0000_0000);
    endproperty
    a_signed_overflow_rem_result: assert property (p_signed_overflow_rem_result)
        else $error("[SVA VIOLATION #12b] Signed overflow REM failed to return 0!");

    // ASSERTION 13: Normal Division Latency (35 Cycles Total)
    // 1 cycle issue + 32 cycle non-restoring loop + 1 cycle correct + 1 cycle done
    property p_div_normal_latency;
        (valid_in && funct3[2] && (rs2 != 32'b0) &&
         !((funct3 == 3'b100 || funct3 == 3'b110) && (rs1 == 32'h8000_0000) && (rs2 == 32'hFFFF_FFFF)))
            |-> ##35 valid_out;
    endproperty
    a_div_normal_latency: assert property (p_div_normal_latency)
        else $error("[SVA VIOLATION #13] Normal non-restoring division latency is not 35 cycles!");


    // =========================================================================
    // SECTION 4: Mathematical Invariant Assertions
    // =========================================================================

    // ASSERTION 14: Remainder Sign Invariant
    // In RISC-V, non-zero remainder sign MUST match the dividend sign
    property p_rem_sign_invariant;
        logic [31:0] saved_dividend;
        (valid_in && (funct3 == 3'b110) && (rs2 != 32'b0), saved_dividend = rs1)
            |-> ##[1:36] valid_out && ((result == 32'b0) || (result[31] == saved_dividend[31]));
    endproperty
    a_rem_sign_invariant: assert property (p_rem_sign_invariant)
        else $error("[SVA VIOLATION #14] Remainder sign does not match dividend sign!");

endmodule


// =============================================================================
// Direct Bind Statement: Binds rv32m_assertions to rv32m_unit automatically
// =============================================================================
bind rv32m_unit rv32m_assertions u_rv32m_sva (
    .clk        (clk),
    .rst_n      (rst_n),
    .rs1        (rs1),
    .rs2        (rs2),
    .funct3     (funct3),
    .rd_in      (rd_in),
    .valid_in   (valid_in),
    .stall      (stall),
    .result     (result),
    .rd_out     (rd_out),
    .valid_out  (valid_out),
    .mul_valid  (mul_valid),
    .div_valid  (div_valid),
    .mul_stall  (mul_stall),
    .div_stall  (div_stall)
);
