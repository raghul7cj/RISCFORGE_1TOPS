`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_pc_unit
// Signoff Item: 4.1 - Unit TB for PC unit (PC.v + PC_Adder.v)
// Criteria: All directed tests pass; code coverage reviewed (VCS / Verdi)
////////////////////////////////////////////////////////////////////////////////

module tb_pc_unit;

    localparam [31:0] DEFAULT_RESET_PC = 32'h8000_0000;
    localparam [31:0] CUSTOM_RESET_PC  = 32'h0001_0000;

    reg         clk;
    reg         rst;
    reg         StallF;
    reg  [31:0] PC_Next;
    wire [31:0] pc_def;
    wire [31:0] pc_cust;

    reg  [31:0] adder_a;
    reg  [31:0] adder_b;
    wire [31:0] adder_c;
    wire [31:0] pc_plus4;

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // Default-parameterized PC DUT
    PC #(
        .RESET_PC(DEFAULT_RESET_PC)
    ) dut_pc_default (
        .clk     (clk),
        .rst     (rst),
        .PC      (pc_def),
        .PC_Next (PC_Next),
        .StallF  (StallF)
    );

    // Custom-parameterized PC DUT (verifies RESET_PC parameter override)
    PC #(
        .RESET_PC(CUSTOM_RESET_PC)
    ) dut_pc_custom (
        .clk     (clk),
        .rst     (rst),
        .PC      (pc_cust),
        .PC_Next (PC_Next),
        .StallF  (StallF)
    );

    // PC + 4 feedback adder instance
    PC_Adder dut_pc_plus4 (
        .a (pc_def),
        .b (32'h0000_0004),
        .c (pc_plus4)
    );

    // Standalone PC_Adder DUT for arbitrary offset / overflow tests
    PC_Adder dut_adder (
        .a (adder_a),
        .b (adder_b),
        .c (adder_c)
    );

    // 100 MHz clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

`ifndef NO_COVERGROUP
    covergroup cg_pc @(posedge clk);
        option.per_instance = 1;
        cp_rst   : coverpoint rst;
        cp_stall : coverpoint StallF;
        cp_cross : cross cp_rst, cp_stall;
    endgroup
    cg_pc cg_inst = new();
`endif

    task automatic check_pc(
        input [31:0] exp_def,
        input [31:0] exp_cust,
        input string msg
    );
        begin
            if (pc_def !== exp_def || pc_cust !== exp_cust) begin
                $display("[FAIL] %0t | %s | def=0x%08h (exp 0x%08h), cust=0x%08h (exp 0x%08h)",
                         $time, msg, pc_def, exp_def, pc_cust, exp_cust);
                fail_cnt = fail_cnt + 1;
            end else begin
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    task automatic check_adder(
        input [31:0] a_val,
        input [31:0] b_val,
        input string msg
    );
        reg [31:0] exp_sum;
        begin
            adder_a = a_val;
            adder_b = b_val;
            #1;
            exp_sum = a_val + b_val;
            if (adder_c !== exp_sum) begin
                $display("[FAIL] %0t | %s | 0x%08h + 0x%08h = 0x%08h (exp 0x%08h)",
                         $time, msg, a_val, b_val, adder_c, exp_sum);
                fail_cnt = fail_cnt + 1;
            end else begin
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    initial begin
`ifdef FSDB
        $fsdbDumpfile("tb_pc_unit.fsdb");
        $fsdbDumpvars(0, tb_pc_unit);
`elsif SHM
        $shm_open("tb_pc_unit.shm");
        $shm_probe("AS");
`elsif VCD
        $dumpfile("tb_pc_unit.vcd");
        $dumpvars(0, tb_pc_unit);
`endif

        // Initialize inputs
        rst     = 1'b0;
        StallF  = 1'b0;
        PC_Next = 32'h0000_0000;
        adder_a = 32'h0000_0000;
        adder_b = 32'h0000_0000;

        // -----------------------------------------------------------------
        // Test 1: Async reset at startup (before first posedge clk)
        // -----------------------------------------------------------------
        #1;
        check_pc(DEFAULT_RESET_PC, CUSTOM_RESET_PC, "Initial async reset");

        // -----------------------------------------------------------------
        // Test 2: Reset overrides PC_Next and StallF across clock edges
        // -----------------------------------------------------------------
        @(negedge clk);
        PC_Next = 32'h1234_5678;
        StallF  = 1'b0;
        @(posedge clk); #1;
        check_pc(DEFAULT_RESET_PC, CUSTOM_RESET_PC, "Reset held with StallF=0");

        @(negedge clk);
        StallF = 1'b1;
        @(posedge clk); #1;
        check_pc(DEFAULT_RESET_PC, CUSTOM_RESET_PC, "Reset held with StallF=1");

        // -----------------------------------------------------------------
        // Test 3: Release reset and verify sequential PC + 4 stepping
        // -----------------------------------------------------------------
        @(negedge clk);
        rst    = 1'b1;
        StallF = 1'b0;
        for (int i = 0; i < 6; i = i + 1) begin
            PC_Next = pc_plus4;
            @(posedge clk); #1;
            check_pc(DEFAULT_RESET_PC + (i + 1) * 4,
                     DEFAULT_RESET_PC + (i + 1) * 4,
                     $sformatf("Sequential PC+4 step %0d", i + 1));
        end

        // -----------------------------------------------------------------
        // Test 4: StallF freezes PC across changing PC_Next, then resumes
        // -----------------------------------------------------------------
        begin
            reg [31:0] held_pc;
            held_pc = pc_def;

            @(negedge clk);
            StallF  = 1'b1;
            PC_Next = 32'hDEAD_0000;
            @(posedge clk); #1;
            check_pc(held_pc, held_pc, "Stall cycle 1 holds PC");

            @(negedge clk);
            PC_Next = 32'hDEAD_0004;
            @(posedge clk); #1;
            check_pc(held_pc, held_pc, "Stall cycle 2 holds PC");

            @(negedge clk);
            PC_Next = 32'hDEAD_0008;
            @(posedge clk); #1;
            check_pc(held_pc, held_pc, "Stall cycle 3 holds PC");

            // Deassert stall -> captures current PC_Next
            @(negedge clk);
            StallF = 1'b0;
            @(posedge clk); #1;
            check_pc(32'hDEAD_0008, 32'hDEAD_0008, "Stall release captures PC_Next");
        end

        // -----------------------------------------------------------------
        // Test 5: Back-to-back single-cycle StallF toggling
        // -----------------------------------------------------------------
        @(negedge clk);
        StallF  = 1'b1;
        PC_Next = 32'hCAFE_0000;
        @(posedge clk); #1;
        check_pc(32'hDEAD_0008, 32'hDEAD_0008, "Toggle stall=1 holds");

        @(negedge clk);
        StallF  = 1'b0;
        PC_Next = 32'hCAFE_0004;
        @(posedge clk); #1;
        check_pc(32'hCAFE_0004, 32'hCAFE_0004, "Toggle stall=0 updates");

        @(negedge clk);
        StallF  = 1'b1;
        PC_Next = 32'hCAFE_0008;
        @(posedge clk); #1;
        check_pc(32'hCAFE_0004, 32'hCAFE_0004, "Toggle stall=1 holds again");

        // -----------------------------------------------------------------
        // Test 6: Asynchronous reset mid-cycle while stalled
        // -----------------------------------------------------------------
        @(posedge clk);
        #2; // Away from clock edges
        rst = 1'b0;
        #1;
        check_pc(DEFAULT_RESET_PC, CUSTOM_RESET_PC, "Async reset mid-cycle while stalled");

        @(negedge clk);
        rst    = 1'b1;
        StallF = 1'b0;

        // -----------------------------------------------------------------
        // Test 7: Corner patterns & full 32-bit toggle coverage on PC / PC_Next
        // -----------------------------------------------------------------
        begin
            reg [31:0] corner_pcs [0:7];
            corner_pcs[0] = 32'h0000_0000;
            corner_pcs[1] = 32'hFFFF_FFFF;
            corner_pcs[2] = 32'hAAAA_AAAA;
            corner_pcs[3] = 32'h5555_5555;
            corner_pcs[4] = 32'hFFFF_FFFC;
            corner_pcs[5] = 32'h7FFF_FFFC;
            corner_pcs[6] = 32'h8000_0000;
            corner_pcs[7] = 32'h0000_0004;

            for (int i = 0; i < 8; i = i + 1) begin
                @(negedge clk);
                PC_Next = corner_pcs[i];
                @(posedge clk); #1;
                check_pc(corner_pcs[i], corner_pcs[i], $sformatf("Corner PC 0x%08h", corner_pcs[i]));
            end

            // Walking-1 across all 32 bits
            for (int b = 0; b < 32; b = b + 1) begin
                @(negedge clk);
                PC_Next = (32'h1 << b);
                @(posedge clk); #1;
                check_pc((32'h1 << b), (32'h1 << b), $sformatf("Walking-1 bit %0d", b));
            end
        end

        // -----------------------------------------------------------------
        // Test 8: PC_Adder directed & wrap-around tests
        // -----------------------------------------------------------------
        check_adder(32'h0000_0000, 32'h0000_0004, "Adder 0 + 4");
        check_adder(32'h8000_0000, 32'h0000_0004, "Adder RESET_PC + 4");
        check_adder(32'h8000_0100, 32'hFFFF_FFF0, "Adder negative branch offset (-16)");
        check_adder(32'hFFFF_FFFC, 32'h0000_0004, "Adder 32-bit wrap-around to 0");
        check_adder(32'hFFFF_FFF0, 32'h0000_0020, "Adder overflow wrap-around");
        check_adder(32'hAAAA_AAAA, 32'h5555_5555, "Adder alternating bit patterns");
        check_adder(32'hFFFF_FFFF, 32'hFFFF_FFFF, "Adder max + max");

        // -----------------------------------------------------------------
        // Test 9: Constrained-random regression (200 cycles)
        // -----------------------------------------------------------------
        begin
            reg [31:0] exp_def, exp_cust;
            int        rand_mode;

            @(negedge clk);
            rst = 1'b0;
            #1;
            exp_def  = DEFAULT_RESET_PC;
            exp_cust = CUSTOM_RESET_PC;
            check_pc(exp_def, exp_cust, "Random phase initial reset");

            for (int t = 0; t < 200; t = t + 1) begin
                @(negedge clk);
                rst       = (($urandom() % 10) != 0); // 90% active run, 10% reset
                StallF    = (($urandom() % 10) < 3);  // 30% stall
                rand_mode = $urandom() % 4;
                if (rand_mode == 0)
                    PC_Next = pc_plus4;
                else if (rand_mode <= 2)
                    PC_Next = {$urandom() >> 2, 2'b00};
                else
                    PC_Next = $urandom();

                if (!rst) begin
                    #1;
                    exp_def  = DEFAULT_RESET_PC;
                    exp_cust = CUSTOM_RESET_PC;
                    check_pc(exp_def, exp_cust, $sformatf("Rand iter %0d async reset", t));
                end

                @(posedge clk); #1;
                if (!rst) begin
                    exp_def  = DEFAULT_RESET_PC;
                    exp_cust = CUSTOM_RESET_PC;
                end else if (!StallF) begin
                    exp_def  = PC_Next;
                    exp_cust = PC_Next;
                end
                check_pc(exp_def, exp_cust, $sformatf("Rand iter %0d posedge", t));
                check_adder($urandom(), $urandom(), $sformatf("Rand adder %0d", t));
            end
        end

        // Summary
        $display("============================================================");
        $display("tb_pc_unit SUMMARY: PASS=%0d, FAIL=%0d", pass_cnt, fail_cnt);
        $display("============================================================");
        if (fail_cnt != 0)
            $fatal(1, "tb_pc_unit FAILED with %0d error(s)", fail_cnt);
        $finish;
    end

endmodule
