`timescale 1ns / 1ps

module tb_rv32m_unit;

    // -------------------------------------------------------------------------
    // Clock and Reset Signals
    // -------------------------------------------------------------------------
    reg clk;
    reg rst_n;

    // Inputs to DUT
    reg  [31:0] rs1;
    reg  [31:0] rs2;
    reg  [2:0]  funct3;
    reg  [4:0]  rd_in;
    reg         valid_in;

    // Outputs from DUT
    wire        stall;
    wire [31:0] result;
    wire [4:0]  rd_out;
    wire        valid_out;

    // Tracking
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    // -------------------------------------------------------------------------
    // Device Under Test (DUT)
    // -------------------------------------------------------------------------
    rv32m_unit dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .rs1       (rs1),
        .rs2       (rs2),
        .funct3    (funct3),
        .rd_in     (rd_in),
        .valid_in  (valid_in),
        .stall     (stall),
        .result    (result),
        .rd_out    (rd_out),
        .valid_out (valid_out)
    );

    // Clock Generator (10ns period -> 100 MHz)
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Reference Golden Mathematical Model
    // -------------------------------------------------------------------------
    function [31:0] ref_model;
        input [2:0]  f3;
        input [31:0] a;
        input [31:0] b;

        reg signed [31:0] sa, sb;
        reg signed [63:0] sprod;
        reg [63:0]        uprod;
        reg signed [63:0] suprod;
        begin
            sa = a;
            sb = b;
            case (f3)
                3'b000: ref_model = a * b;
                3'b001: begin
                    sprod = sa * sb;
                    ref_model = sprod[63:32];
                end
                3'b010: begin
                    suprod = sa * $signed({1'b0, b});
                    ref_model = suprod[63:32];
                end
                3'b011: begin
                    uprod = {32'b0, a} * {32'b0, b};
                    ref_model = uprod[63:32];
                end
                3'b100: begin
                    if (b == 32'b0)
                        ref_model = 32'hFFFF_FFFF;
                    else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF)
                        ref_model = 32'h8000_0000;
                    else
                        ref_model = sa / sb;
                end
                3'b101: begin
                    if (b == 32'b0)
                        ref_model = 32'hFFFF_FFFF;
                    else
                        ref_model = a / b;
                end
                3'b110: begin
                    if (b == 32'b0)
                        ref_model = a;
                    else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF)
                        ref_model = 32'h0000_0000;
                    else
                        ref_model = sa % sb;
                end
                3'b111: begin
                    if (b == 32'b0)
                        ref_model = a;
                    else
                        ref_model = a % b;
                end
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // Reusable Test Task
    // -------------------------------------------------------------------------
    task run_test;
        input [2:0]    in_funct3;
        input [31:0]   in_rs1;
        input [31:0]   in_rs2;
        input [4:0]    in_rd;
        input [8*12:1] in_name;

        reg [31:0] gold_result;
        integer    actual_cycles;
        reg        timeout;
        begin
            test_num      = test_num + 1;
            gold_result   = ref_model(in_funct3, in_rs1, in_rs2);
            actual_cycles = 1;
            timeout       = 0;

            @(negedge clk);
            funct3   = in_funct3;
            rs1      = in_rs1;
            rs2      = in_rs2;
            rd_in    = in_rd;
            valid_in = 1'b1;

            @(negedge clk);
            valid_in = 1'b0;

            while (!valid_out && !timeout) begin
                @(negedge clk);
                actual_cycles = actual_cycles + 1;
                if (actual_cycles > 50) timeout = 1'b1;
            end

            if (timeout) begin
                $display("[FAIL #%02d] %-8s: TIMEOUT!", test_num, in_name);
                fail_count = fail_count + 1;
            end else if (result !== gold_result) begin
                $display("[FAIL #%02d] %-8s: MISMATCH! rs1=0x%08h, rs2=0x%08h | Exp: 0x%08h, Got: 0x%08h",
                         test_num, in_name, in_rs1, in_rs2, gold_result, result);
                fail_count = fail_count + 1;
            end else begin
                $display("[PASS #%02d] %-8s: rs1=0x%08h, rs2=0x%08h -> res=0x%08h (rd=x%0d, %0d cycles)",
                         test_num, in_name, in_rs1, in_rs2, result, rd_out, actual_cycles);
                pass_count = pass_count + 1;
            end

            @(negedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Verification Flow with Full Coverage Stimulus
    // -------------------------------------------------------------------------
    initial begin
        clk      = 0;
        rst_n    = 0;
        rs1      = 0;
        rs2      = 0;
        funct3   = 0;
        rd_in    = 0;
        valid_in = 0;

        $display("==================================================================");
        $display("   RV32M Full Functional Verification Stimulus Driver            ");
        $display("==================================================================");

        #25;
        @(negedge clk);
        rst_n = 1;
        #20;

        // ---------------------------------------------------------------------
        // 1. cg_mul: Full Bin Exercise
        // ---------------------------------------------------------------------
        run_test(3'b000, 32'd0,          32'd0,          5'd1, "MUL"); // zero x zero
        run_test(3'b000, 32'd1,          32'd1,          5'd2, "MUL"); // one x one
        run_test(3'b000, -32'd1,         -32'd1,         5'd3, "MUL"); // -1 x -1
        run_test(3'b000, 32'h7FFFFFFF,   32'h7FFFFFFF,   5'd4, "MUL"); // max_pos x max_pos
        run_test(3'b000, 32'h80000000,   32'h80000000,   5'd5, "MUL"); // max_neg x max_neg
        run_test(3'b000, 32'd16,         32'd8,          5'd6, "MUL"); // power of 2
        run_test(3'b000, 32'd45,         -32'd12,        5'd7, "MUL"); // + x -
        run_test(3'b000, -32'd45,        32'd12,         5'd8, "MUL"); // - x +
        run_test(3'b000, 32'd1000,       32'd0,          5'd9, "MUL"); // result zero

        // ---------------------------------------------------------------------
        // 2. cg_mulh: Full Bin Exercise
        // ---------------------------------------------------------------------
        run_test(3'b001, 32'd0,          32'd50,         5'd10, "MULH");
        run_test(3'b001, 32'd50,         32'd0,          5'd10, "MULH"); // rs2=0
        run_test(3'b001, 32'h7FFFFFFF,   32'h7FFFFFFF,   5'd11, "MULH"); // rs2=max_pos
        run_test(3'b001, 32'h80000000,   32'h80000000,   5'd12, "MULH"); // MaxNeg x MaxNeg corner (upper 0x40000000)
        run_test(3'b001, -32'd1,         32'd1,          5'd13, "MULH"); // -1 * 1 -> upper 0xFFFFFFFF
        run_test(3'b001, -32'd1,         32'hFFFFFFFF,   5'd13, "MULH"); // rs2=-1
        run_test(3'b001, -32'd2,         -32'd2,         5'd14, "MULH"); // upper zero
        run_test(3'b001, 32'd100,        32'd200,        5'd15, "MULH");
        run_test(3'b001, -32'd100,       -32'd200,       5'd16, "MULH");

        // ---------------------------------------------------------------------
        // 3. cg_mulhsu: Full Bin Exercise
        // ---------------------------------------------------------------------
        run_test(3'b010, 32'd0,          32'd0,          5'd17, "MULHSU"); // rs2=0
        run_test(3'b010, 32'd50,         32'd1,          5'd17, "MULHSU"); // rs2=1
        run_test(3'b010, 32'h7FFFFFFF,   32'hFFFFFFFF,   5'd18, "MULHSU");
        run_test(3'b010, 32'h80000000,   32'd2,          5'd19, "MULHSU");
        run_test(3'b010, -32'd1,         32'd2,          5'd20, "MULHSU"); // upper -1
        run_test(3'b010, -32'd50,        32'h80000000,   5'd21, "MULHSU"); // neg x msb=1
        run_test(3'b010, 32'd50,         32'h80000000,   5'd22, "MULHSU"); // pos x msb=1
        run_test(3'b010, 32'd2,          32'd2,          5'd23, "MULHSU"); // upper zero

        // ---------------------------------------------------------------------
        // 4. cg_mulhu: Full Bin Exercise
        // ---------------------------------------------------------------------
        run_test(3'b011, 32'hFFFFFFFF,   32'd0,          5'd24, "MULHU"); // rs2=0
        run_test(3'b011, 32'd0,          32'hFFFFFFFF,   5'd24, "MULHU"); // rs1=0
        run_test(3'b011, 32'd1,          32'd1,          5'd25, "MULHU");
        run_test(3'b011, 32'hFFFFFFFF,   32'hFFFFFFFF,   5'd26, "MULHU"); // MaxU x MaxU corner
        run_test(3'b011, 32'h40000000,   32'h40000000,   5'd27, "MULHU"); // lower half
        run_test(3'b011, 32'h90000000,   32'h90000000,   5'd28, "MULHU"); // upper half
        run_test(3'b011, 32'd10,         32'd10,         5'd29, "MULHU"); // upper zero

        // ---------------------------------------------------------------------
        // 5. cg_div: Full Bin Exercise (including all corner cases)
        // ---------------------------------------------------------------------
        run_test(3'b100, 32'd42,         32'd0,          5'd30, "DIV"); // DIV-BY-ZERO
        run_test(3'b100, 32'h80000000,   32'hFFFFFFFF,   5'd31, "DIV"); // SIGNED OVERFLOW
        run_test(3'b100, 32'h80000000,   32'd2,          5'd31, "DIV"); // rs1=80000000 / 2
        run_test(3'b100, 32'd1,          32'd1,          5'd1,  "DIV"); // rs1=1
        run_test(3'b100, -32'd1,         32'd1,          5'd1,  "DIV"); // rs1=-1
        run_test(3'b100, 32'd50,         32'hFFFFFFFF,   5'd1,  "DIV"); // 50 / -1
        run_test(3'b100, 32'd50,         32'd50,         5'd1,  "DIV"); // SELF DIV (A/A=1)
        run_test(3'b100, 32'd2,          32'd50,         5'd2,  "DIV"); // A < B (Q=0)
        run_test(3'b100, 32'd100,        32'd1,          5'd3,  "DIV"); // Identity (A/1=A)
        run_test(3'b100, 32'd64,         32'd8,          5'd4,  "DIV"); // Power of 2
        run_test(3'b100, 32'd100,        32'd5,          5'd5,  "DIV"); // + / +
        run_test(3'b100, 32'd100,        -32'd5,         5'd6,  "DIV"); // + / -
        run_test(3'b100, -32'd100,       32'd5,          5'd7,  "DIV"); // - / +
        run_test(3'b100, -32'd100,       -32'd5,         5'd8,  "DIV"); // - / -
        run_test(3'b100, 32'd0,          32'd10,         5'd9,  "DIV"); // 0 / B = 0
        run_test(3'b100, 32'h7FFFFFFF,   32'd2,          5'd10, "DIV"); // MaxPos

        // ---------------------------------------------------------------------
        // 6. cg_divu: Full Bin Exercise
        // ---------------------------------------------------------------------
        run_test(3'b101, 32'd0,          32'd50,         5'd11, "DIVU"); // rs1=0
        run_test(3'b101, 32'd1,          32'd1,          5'd11, "DIVU"); // rs1=1
        run_test(3'b101, 32'd42,         32'd0,          5'd11, "DIVU"); // Unsigned DIV-BY-ZERO
        run_test(3'b101, 32'd10,         32'd10,         5'd12, "DIVU"); // Self div
        run_test(3'b101, 32'd5,          32'd100,        5'd13, "DIVU"); // A < B (Q=0)
        run_test(3'b101, 32'hFFFFFFFF,   32'd2,          5'd14, "DIVU"); // High bit set
        run_test(3'b101, 32'd100,        32'd1,          5'd15, "DIVU"); // Identity (rs2=1)
        run_test(3'b101, 32'd256,        32'd16,         5'd16, "DIVU"); // Power of 2
        run_test(3'b101, 32'h90000000,   32'h80000000,   5'd17, "DIVU"); // High bit on both

        // ---------------------------------------------------------------------
        // 7. cg_rem: Full Bin Exercise
        // ---------------------------------------------------------------------
        run_test(3'b110, 32'd42,         32'd0,          5'd18, "REM"); // REM-BY-ZERO (x%0=x)
        run_test(3'b110, 32'h80000000,   32'hFFFFFFFF,   5'd19, "REM"); // OVERFLOW REM (-2^31 % -1 = 0)
        run_test(3'b110, 32'hFFFFFFFF,   32'd5,          5'd19, "REM"); // rs1=-1
        run_test(3'b110, 32'd5,          32'hFFFFFFFF,   5'd19, "REM"); // rs2=-1 (5 % -1 = 0)
        run_test(3'b110, 32'd5,          32'd1,          5'd19, "REM"); // rs2=1 (5 % 1 = 0)
        run_test(3'b110, 32'd100,        32'd10,         5'd20, "REM"); // Exact div (Rem=0)
        run_test(3'b110, 32'd25,         32'd4,          5'd21, "REM"); // Pos div / Pos divisor -> Pos rem (+1)
        run_test(3'b110, 32'd25,         -32'd4,         5'd22, "REM"); // Pos div / Neg divisor -> Pos rem (+1)
        run_test(3'b110, -32'd25,        32'd4,          5'd23, "REM"); // Neg div / Pos divisor -> Neg rem (-1)
        run_test(3'b110, -32'd25,        -32'd4,         5'd24, "REM"); // Neg div / Neg divisor -> Neg rem (-1)
        run_test(3'b110, 32'h7FFFFFFF,   32'd10,         5'd25, "REM"); // MaxPos
        run_test(3'b110, 32'd0,          32'd5,          5'd26, "REM"); // 0 % B = 0

        // ---------------------------------------------------------------------
        // 8. cg_remu: Full Bin Exercise
        // ---------------------------------------------------------------------
        run_test(3'b111, 32'd0,          32'd5,          5'd27, "REMU"); // rs1=0
        run_test(3'b111, 32'd42,         32'd0,          5'd27, "REMU"); // Rem-by-zero
        run_test(3'b111, 32'd100,        32'd1,          5'd28, "REMU"); // rs2=1
        run_test(3'b111, 32'd100,        32'd10,         5'd28, "REMU"); // Exact div (Rem=0)
        run_test(3'b111, 32'd5,          32'd20,         5'd29, "REMU"); // A < B -> R = A
        run_test(3'b111, 32'd5,          32'hFFFFFFFF,   5'd29, "REMU"); // rs2=FFFFFFFF
        run_test(3'b111, 32'hFFFFFFFF,   32'd10,         5'd30, "REMU"); // High bit set dividend
        run_test(3'b111, 32'hFFFFFFFF,   32'h80000000,   5'd31, "REMU"); // High bit set divisor
        run_test(3'b111, 32'hFFFFFFFF,   32'd0,          5'd1,  "REMU"); // Max remu return

        $display("\n==================================================================");
        $display("                   VERIFICATION SUMMARY                           ");
        $display("==================================================================");
        $display(" Total Tests Executed: %0d", test_num);
        $display(" Passed:              %0d", pass_count);
        $display(" Failed:              %0d", fail_count);
        if (fail_count == 0)
            $display(" >>> [STATUS: ALL TESTS PASSED SUCCESSFULLY] <<<");
        else
            $display(" >>> [STATUS: TEST FAILURES DETECTED: %0d] <<<", fail_count);
        $display("==================================================================\n");
        $finish;
    end

endmodule
