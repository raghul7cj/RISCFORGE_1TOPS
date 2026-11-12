`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_branch_unit
// Signoff Item: 4.5 - Unit TB for branch unit (JB_unit.v + ALU.v flag path)
// Criteria: Full compare matrix passes; rs1<rs2, rs1=rs2, rs1>rs2 covered
//           signed and unsigned (VCS / Verdi)
////////////////////////////////////////////////////////////////////////////////

module tb_branch_unit;

    // -------------------------------------------------------------------------
    // DUT 1: Standalone JB_unit (exhaustive control/flags matrix)
    // -------------------------------------------------------------------------
    reg  [2:0] jb_flags;
    reg  [1:0] jb_J;
    reg  [3:0] jb_B;
    wire       jb_yes;
    wire       jb_JALR;

    JB_unit dut_jb_standalone (
        .flags (jb_flags),
        .J     (jb_J),
        .B     (jb_B),
        .yes   (jb_yes),
        .JALR  (jb_JALR)
    );

    // -------------------------------------------------------------------------
    // DUT 2: Integrated ALU comparison flags -> JB_unit (rs1 vs rs2 matrix)
    // -------------------------------------------------------------------------
    reg  [31:0] rs1;
    reg  [31:0] rs2;
    reg  [1:0]  cmp_J;
    reg  [3:0]  cmp_B;
    wire [31:0] alu_result;
    wire        alu_zero;
    wire [2:0]  alu_flags;
    wire        cmp_yes;
    wire        cmp_JALR;

    ALU dut_alu_cmp (
        .A          (rs1),
        .B          (rs2),
        .ALUControl (4'b0001), // SUB (flags are computed continuously from A, B)
        .Result     (alu_result),
        .Zero       (alu_zero),
        .flags      (alu_flags)
    );

    JB_unit dut_jb_cmp (
        .flags (alu_flags),
        .J     (cmp_J),
        .B     (cmp_B),
        .yes   (cmp_yes),
        .JALR  (cmp_JALR)
    );

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // Ordering coverage counters
    integer cov_slt = 0, cov_seq = 0, cov_sgt = 0;
    integer cov_ult = 0, cov_ueq = 0, cov_ugt = 0;

    // Dummy clock for sampling SystemVerilog covergroup cleanly
    reg cov_clk = 1'b0;

`ifndef NO_COVERGROUP
    typedef enum int {REL_LT = 0, REL_EQ = 1, REL_GT = 2} rel_e;
    rel_e signed_rel;
    rel_e unsigned_rel;

    covergroup cg_branch_compare @(posedge cov_clk);
        option.per_instance = 1;
        cp_branch_en : coverpoint cmp_B[3];
        cp_funct3    : coverpoint cmp_B[2:0] {
            bins beq     = {3'b000};
            bins bne     = {3'b001};
            bins blt     = {3'b100};
            bins bge     = {3'b101};
            bins bltu    = {3'b110};
            bins bgeu    = {3'b111};
            bins illegal = {3'b010, 3'b011};
        }
        cp_jump : coverpoint cmp_J {
            bins no_jump = {2'b00, 2'b01};
            bins jalr    = {2'b10};
            bins jal     = {2'b11};
        }
        cp_signed_rel   : coverpoint signed_rel;
        cp_unsigned_rel : coverpoint unsigned_rel;
        cp_taken        : coverpoint cmp_yes;

        cx_branch_signed   : cross cp_branch_en, cp_funct3, cp_signed_rel
                             iff (cmp_B[3] == 1'b1);
        cx_branch_unsigned : cross cp_branch_en, cp_funct3, cp_unsigned_rel
                             iff (cmp_B[3] == 1'b1);
        cx_sign_diverge    : cross cp_signed_rel, cp_unsigned_rel;
    endgroup

    cg_branch_compare cg_inst = new();
`endif

    // Golden JB_unit reference task
    task automatic golden_jb(
        input  [2:0] flags_i,
        input  [1:0] J_i,
        input  [3:0] B_i,
        output       exp_yes,
        output       exp_jalr
    );
        reg branch_en;
        reg [2:0] f3;
        reg br_taken;
        begin
            branch_en = B_i[3];
            f3        = B_i[2:0];
            case (f3)
                3'b000: br_taken = flags_i[2];   // BEQ
                3'b001: br_taken = ~flags_i[2];  // BNE
                3'b100: br_taken = flags_i[1];   // BLT
                3'b101: br_taken = ~flags_i[1];  // BGE
                3'b110: br_taken = flags_i[0];   // BLTU
                3'b111: br_taken = ~flags_i[0];  // BGEU
                default: br_taken = 1'b0;        // Reserved 010/011
            endcase
            exp_yes  = (branch_en & br_taken) | J_i[1];
            exp_jalr = J_i[1] & ~J_i[0];
        end
    endtask

    task automatic verify_standalone(
        input [2:0] f_val,
        input [1:0] j_val,
        input [3:0] b_val
    );
        reg exp_y, exp_jr;
        begin
            jb_flags = f_val;
            jb_J     = j_val;
            jb_B     = b_val;
            #1;
            golden_jb(f_val, j_val, b_val, exp_y, exp_jr);
            if (jb_yes !== exp_y || jb_JALR !== exp_jr) begin
                $display("[FAIL] Standalone | flags=%3b J=%2b B=%4b | yes=%b (exp %b) JALR=%b (exp %b)",
                         f_val, j_val, b_val, jb_yes, exp_y, jb_JALR, exp_jr);
                fail_cnt = fail_cnt + 1;
            end else begin
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    task automatic verify_cmp_pair(
        input [31:0] a_val,
        input [31:0] b_val,
        input [1:0]  j_val,
        input [3:0]  br_val
    );
        reg [2:0] exp_flags;
        reg       exp_y, exp_jr;
        begin
            rs1   = a_val;
            rs2   = b_val;
            cmp_J = j_val;
            cmp_B = br_val;
            #1;

            // Track signed & unsigned ordering coverage
            if ($signed(a_val) < $signed(b_val)) begin
                cov_slt = cov_slt + 1;
`ifndef NO_COVERGROUP
                signed_rel = REL_LT;
`endif
            end else if ($signed(a_val) == $signed(b_val)) begin
                cov_seq = cov_seq + 1;
`ifndef NO_COVERGROUP
                signed_rel = REL_EQ;
`endif
            end else begin
                cov_sgt = cov_sgt + 1;
`ifndef NO_COVERGROUP
                signed_rel = REL_GT;
`endif
            end

            if (a_val < b_val) begin
                cov_ult = cov_ult + 1;
`ifndef NO_COVERGROUP
                unsigned_rel = REL_LT;
`endif
            end else if (a_val == b_val) begin
                cov_ueq = cov_ueq + 1;
`ifndef NO_COVERGROUP
                unsigned_rel = REL_EQ;
`endif
            end else begin
                cov_ugt = cov_ugt + 1;
`ifndef NO_COVERGROUP
                unsigned_rel = REL_GT;
`endif
            end

            // Sample covergroup
            cov_clk = 1'b1; #1; cov_clk = 1'b0;

            // Independent reference calculation from raw 32-bit rs1, rs2
            exp_flags[2] = (a_val == b_val);
            exp_flags[1] = ($signed(a_val) < $signed(b_val));
            exp_flags[0] = (a_val < b_val);
            golden_jb(exp_flags, j_val, br_val, exp_y, exp_jr);

            if (alu_flags !== exp_flags || cmp_yes !== exp_y || cmp_JALR !== exp_jr) begin
                $display("[FAIL] Compare | rs1=0x%08h rs2=0x%08h J=%2b B=%4b | flags=%3b (exp %3b) yes=%b (exp %b) JALR=%b (exp %b)",
                         a_val, b_val, j_val, br_val, alu_flags, exp_flags, cmp_yes, exp_y, cmp_JALR, exp_jr);
                fail_cnt = fail_cnt + 1;
            end else begin
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    initial begin
`ifdef FSDB
        $fsdbDumpfile("tb_branch_unit.fsdb");
        $fsdbDumpvars(0, tb_branch_unit);
`elsif SHM
        $shm_open("tb_branch_unit.shm");
        $shm_probe("AS");
`elsif VCD
        $dumpfile("tb_branch_unit.vcd");
        $dumpvars(0, tb_branch_unit);
`endif

        // -----------------------------------------------------------------
        // Phase 1: Exhaustive standalone JB_unit matrix (8 * 4 * 16 = 512)
        // -----------------------------------------------------------------
        for (int f = 0; f < 8; f = f + 1) begin
            for (int j = 0; j < 4; j = j + 1) begin
                for (int b = 0; b < 16; b = b + 1) begin
                    verify_standalone(f[2:0], j[1:0], b[3:0]);
                end
            end
        end

        // -----------------------------------------------------------------
        // Phase 2: Full compare matrix across signed & unsigned boundaries
        //   Covers:
        //     - rs1 < rs2, rs1 == rs2, rs1 > rs2 (signed)
        //     - rs1 < rs2, rs1 == rs2, rs1 > rs2 (unsigned)
        //     - Sign-divergence cases (e.g., 0x80000000 vs 0x7FFFFFFF, -1 vs 0)
        //     - All 6 branch funct3 + reserved 010/011 + Branch=0 + JAL/JALR
        // -----------------------------------------------------------------
        begin
            reg [31:0] op_vec [0:10];
            op_vec[0]  = 32'h0000_0000; //  0
            op_vec[1]  = 32'h0000_0001; // +1
            op_vec[2]  = 32'h0000_0002; // +2
            op_vec[3]  = 32'h7FFF_FFFE; // INT_MAX - 1
            op_vec[4]  = 32'h7FFF_FFFF; // INT_MAX
            op_vec[5]  = 32'h8000_0000; // INT_MIN (2^31)
            op_vec[6]  = 32'h8000_0001; // INT_MIN + 1
            op_vec[7]  = 32'hFFFF_FFFE; // -2 (2^32 - 2)
            op_vec[8]  = 32'hFFFF_FFFF; // -1 (UINT_MAX)
            op_vec[9]  = 32'h5555_5555; // Alternating 01
            op_vec[10] = 32'hAAAA_AAAA; // Alternating 10

            for (int i = 0; i < 11; i = i + 1) begin
                for (int k = 0; k < 11; k = k + 1) begin
                    // All 8 funct3 values with Branch=1, J=00
                    for (int f3 = 0; f3 < 8; f3 = f3 + 1) begin
                        verify_cmp_pair(op_vec[i], op_vec[k], 2'b00, {1'b1, f3[2:0]});
                    end
                    // Branch=0 with J=00 (never taken), JALR (J=10), JAL (J=11)
                    verify_cmp_pair(op_vec[i], op_vec[k], 2'b00, 4'b0000);
                    verify_cmp_pair(op_vec[i], op_vec[k], 2'b10, 4'b0000);
                    verify_cmp_pair(op_vec[i], op_vec[k], 2'b11, 4'b0000);
                end
            end
        end

        // -----------------------------------------------------------------
        // Phase 3: Randomized 32-bit stress across all valid branch ops
        // -----------------------------------------------------------------
        begin
            reg [31:0] r_a, r_b;
            reg [2:0]  valid_f3 [0:5];
            valid_f3[0] = 3'b000; // BEQ
            valid_f3[1] = 3'b001; // BNE
            valid_f3[2] = 3'b100; // BLT
            valid_f3[3] = 3'b101; // BGE
            valid_f3[4] = 3'b110; // BLTU
            valid_f3[5] = 3'b111; // BGEU

            for (int t = 0; t < 2000; t = t + 1) begin
                r_a = $urandom();
                r_b = (t % 10 == 0) ? r_a : $urandom();
                verify_cmp_pair(r_a, r_b, 2'b00, {1'b1, valid_f3[t % 6]});
            end
        end

        // Verify all 6 ordering buckets were hit
        if (cov_slt == 0 || cov_seq == 0 || cov_sgt == 0 ||
            cov_ult == 0 || cov_ueq == 0 || cov_ugt == 0) begin
            $display("[FAIL] Incomplete compare ordering coverage: signed(<:%0d, ==:%0d, >:%0d) unsigned(<:%0d, ==:%0d, >:%0d)",
                     cov_slt, cov_seq, cov_sgt, cov_ult, cov_ueq, cov_ugt);
            fail_cnt = fail_cnt + 1;
        end

        // Summary
        $display("============================================================");
        $display("Signed   coverage counts: rs1<rs2=%0d, rs1==rs2=%0d, rs1>rs2=%0d",
                 cov_slt, cov_seq, cov_sgt);
        $display("Unsigned coverage counts: rs1<rs2=%0d, rs1==rs2=%0d, rs1>rs2=%0d",
                 cov_ult, cov_ueq, cov_ugt);
        $display("tb_branch_unit SUMMARY: PASS=%0d, FAIL=%0d", pass_cnt, fail_cnt);
        $display("============================================================");
        if (fail_cnt != 0)
            $fatal(1, "tb_branch_unit FAILED with %0d error(s)", fail_cnt);
        $finish;
    end

endmodule
