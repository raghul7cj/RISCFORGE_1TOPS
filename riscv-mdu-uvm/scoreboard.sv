// =============================================================================
// File: scoreboard.sv
// Description: UVM Scoreboard with Golden Algorithmic Model for RV32M
// =============================================================================
`ifndef SCOREBOARD_SV
`define SCOREBOARD_SV

class rv32m_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(rv32m_scoreboard)

    uvm_analysis_imp #(rv32m_transaction, rv32m_scoreboard) scoreboard_port;

    int unsigned total_checks;
    int unsigned pass_count;
    int unsigned fail_count;
    int unsigned latency_mismatches;

    function new(string name = "rv32m_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        total_checks       = 0;
        pass_count         = 0;
        fail_count         = 0;
        latency_mismatches = 0;
        `uvm_info("SCOREBOARD", "Constructed rv32m_scoreboard", UVM_HIGH)
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("SCOREBOARD", "Build phase rv32m_scoreboard", UVM_HIGH)
        scoreboard_port = new("scoreboard_port", this);
    endfunction

    // ── Golden Reference Mathematical Model ──────────────────────────────────
    virtual function bit [31:0] ref_model(input bit [2:0]  f3,
                                          input bit [31:0] a,
                                          input bit [31:0] b);
        logic signed [31:0] sa, sb;
        logic signed [63:0] sprod;
        logic [63:0]        uprod;
        logic signed [63:0] suprod;

        sa = a;
        sb = b;

        case (f3)
            OP_MUL: begin
                return (a * b);
            end

            OP_MULH: begin
                sprod = sa * sb;
                return sprod[63:32];
            end

            OP_MULHSU: begin
                suprod = sa * $signed({1'b0, b});
                return suprod[63:32];
            end

            OP_MULHU: begin
                uprod = {32'b0, a} * {32'b0, b};
                return uprod[63:32];
            end

            OP_DIV: begin
                if (b == 32'b0)
                    return 32'hFFFF_FFFF;                     // Div-by-zero returns -1
                else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF)
                    return 32'h8000_0000;                     // Signed overflow returns -2^31
                else
                    return (sa / sb);
            end

            OP_DIVU: begin
                if (b == 32'b0)
                    return 32'hFFFF_FFFF;                     // Unsigned div-by-zero returns 0xFFFFFFFF
                else
                    return (a / b);
            end

            OP_REM: begin
                if (b == 32'b0)
                    return a;                                 // Rem-by-zero returns dividend
                else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF)
                    return 32'h0000_0000;                     // Signed overflow rem returns 0
                else
                    return (sa % sb);
            end

            OP_REMU: begin
                if (b == 32'b0)
                    return a;                                 // Remu-by-zero returns dividend
                else
                    return (a % b);
            end

            default: return 32'h0;
        endcase
    endfunction

    // ── Expected Hardware Latency Oracle ─────────────────────────────────────
    virtual function int unsigned expected_latency(rv32m_transaction tr);
        if (tr.is_mul()) begin
            return 3; // Fixed 3-stage Booth-Dadda multiplier pipeline
        end else if (tr.is_div_by_zero() || tr.is_signed_overflow()) begin
            return 2; // Speculative fast-path corner exit
        end else begin
            return 35; // 1 IDLE + 32 non-restoring loop iterations + 1 CORRECT + 1 DONE
        end
    endfunction

    // ── Analysis Write Callback ──────────────────────────────────────────────
    virtual function void write(rv32m_transaction tr);
        compare(tr);
    endfunction

    // ── Comparison & Verification Logic ──────────────────────────────────────
    virtual function void compare(rv32m_transaction tr);
        bit [31:0]    exp_res;
        int unsigned  exp_cycles;
        bit           res_match;
        bit           rd_match;
        bit           lat_match;

        exp_res    = ref_model(tr.funct3, tr.rs1, tr.rs2);
        exp_cycles = expected_latency(tr);

        res_match = (tr.result === exp_res);
        rd_match  = (tr.rd_out === tr.rd_in);
        lat_match = (tr.actual_cycles === exp_cycles);

        total_checks++;

        // 1. Result Data Check
        if (!res_match) begin
            fail_count++;
            `uvm_error("SCB_DATA_MISMATCH",
                $sformatf("Result Mismatch! [%s] rs1=0x%08h (%0d), rs2=0x%08h (%0d) | Expected: 0x%08h, Got: 0x%08h",
                          tr.get_op_name(), tr.rs1, $signed(tr.rs1), tr.rs2, $signed(tr.rs2), exp_res, tr.result))
        end else if (!rd_match) begin
            fail_count++;
            `uvm_error("SCB_RD_MISMATCH",
                $sformatf("Destination Register Corrupted! Expected rd=x%0d, Got rd=x%0d", tr.rd_in, tr.rd_out))
        end else begin
            pass_count++;
            `uvm_info("SCB_PASS",
                $sformatf("[CHECK #%03d PASS] %-8s: rs1=0x%08h, rs2=0x%08h -> res=0x%08h (rd=x%0d, %0d cyc)",
                          total_checks, tr.get_op_name(), tr.rs1, tr.rs2, tr.result, tr.rd_out, tr.actual_cycles), UVM_HIGH)
        end

        // 2. Hardware Cycle Latency Check
        if (!lat_match) begin
            latency_mismatches++;
            `uvm_warning("SCB_LATENCY_WARN",
                $sformatf("Latency Deviation on [%s]! Expected: %0d cycles, Measured: %0d cycles (rs1=0x%08h, rs2=0x%08h)",
                          tr.get_op_name(), exp_cycles, tr.actual_cycles, tr.rs1, tr.rs2))
        end
    endfunction

    // ── UVM Report Phase Sign-off ────────────────────────────────────────────
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCB_SUMMARY", "==================================================================", UVM_NONE)
        `uvm_info("SCB_SUMMARY", "             RV32M SCOREBOARD VERIFICATION SUMMARY                ", UVM_NONE)
        `uvm_info("SCB_SUMMARY", "==================================================================", UVM_NONE)
        `uvm_info("SCB_SUMMARY", $sformatf(" Total Checks Evaluated : %0d", total_checks), UVM_NONE)
        `uvm_info("SCB_SUMMARY", $sformatf(" Passed Checks          : %0d", pass_count), UVM_NONE)
        `uvm_info("SCB_SUMMARY", $sformatf(" Failed Checks          : %0d", fail_count), UVM_NONE)
        `uvm_info("SCB_SUMMARY", $sformatf(" Latency Deviations     : %0d", latency_mismatches), UVM_NONE)
        if (fail_count == 0 && total_checks > 0) begin
            `uvm_info("SCB_SUMMARY", " >>> STATUS: [100% VERIFICATION SUCCESS - ZERO MISMATCHES] <<<", UVM_NONE)
        end else begin
            `uvm_error("SCB_SUMMARY", $sformatf(" >>> STATUS: [VERIFICATION FAILED: %0d ERRORS DETECTED] <<<", fail_count))
        end
        `uvm_info("SCB_SUMMARY", "==================================================================", UVM_NONE)
    endfunction

endclass : rv32m_scoreboard

// Backward-compatible alias for template integration
typedef rv32m_scoreboard scb;

`endif // SCOREBOARD_SV
