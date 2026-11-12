`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_register_file
// Signoff Item: 4.3 - Unit TB for register file (Register_File.v)
// Criteria: x0-write and same-cycle read/write tests pass (VCS / Verdi)
////////////////////////////////////////////////////////////////////////////////

module tb_register_file;

    reg         clk;
    reg         rst;
    reg         WE3;
    reg  [4:0]  A1, A2, A3;
    reg  [31:0] WD3;
    wire [31:0] RD1, RD2;

    // Golden architectural register mirror
    reg  [31:0] ref_regs [0:31];

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    Register_File dut (
        .clk (clk),
        .rst (rst),
        .WE3 (WE3),
        .WD3 (WD3),
        .A1  (A1),
        .A2  (A2),
        .A3  (A3),
        .RD1 (RD1),
        .RD2 (RD2)
    );

    // 100 MHz clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

`ifndef NO_COVERGROUP
    covergroup cg_rf @(posedge clk);
        option.per_instance = 1;
        cp_rst      : coverpoint rst;
        cp_we3      : coverpoint WE3;
        cp_a3_zero  : coverpoint (A3 == 5'd0);
        cp_fwd_rd1  : coverpoint (rst && WE3 && (A1 == A3) && (A3 != 5'd0));
        cp_fwd_rd2  : coverpoint (rst && WE3 && (A2 == A3) && (A3 != 5'd0));
        cp_a3_all   : coverpoint A3 { bins regs[] = {[0:31]}; }
        cx_x0_write : cross cp_rst, cp_we3, cp_a3_zero;
        cx_fwd      : cross cp_fwd_rd1, cp_fwd_rd2;
    endgroup
    cg_rf cg_inst = new();
`endif

    // Golden combinational expectation matching Register_File.v spec
    function automatic [31:0] exp_read(input [4:0] addr);
        begin
            if (rst == 1'b0)
                exp_read = 32'd0;
            else if (addr == 5'd0)
                exp_read = 32'd0;
            else if (WE3 && (addr == A3))
                exp_read = WD3;
            else
                exp_read = ref_regs[addr];
        end
    endfunction

    task automatic check_reads(input string msg);
        reg [31:0] exp1, exp2;
        begin
            #1;
            exp1 = exp_read(A1);
            exp2 = exp_read(A2);
            if (RD1 !== exp1 || RD2 !== exp2) begin
                $display("[FAIL] %0t | %s | A1=%0d RD1=0x%08h (exp 0x%08h) | A2=%0d RD2=0x%08h (exp 0x%08h)",
                         $time, msg, A1, RD1, exp1, A2, RD2, exp2);
                fail_cnt = fail_cnt + 1;
            end else begin
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    task automatic write_reg(input [4:0] addr, input [31:0] data, input en);
        begin
            @(negedge clk);
            WE3 = en;
            A3  = addr;
            WD3 = data;
            @(posedge clk);
            if (en && addr != 5'd0)
                ref_regs[addr] = data;
            #1;
        end
    endtask

    initial begin
`ifdef FSDB
        $fsdbDumpfile("tb_register_file.fsdb");
        $fsdbDumpvars(0, tb_register_file);
`elsif SHM
        $shm_open("tb_register_file.shm");
        $shm_probe("AS");
`elsif VCD
        $dumpfile("tb_register_file.vcd");
        $dumpvars(0, tb_register_file);
`endif

        for (int i = 0; i < 32; i = i + 1)
            ref_regs[i] = 32'd0;

        rst = 1'b0;
        WE3 = 1'b0;
        A1  = 5'd0;
        A2  = 5'd0;
        A3  = 5'd0;
        WD3 = 32'd0;

        // -----------------------------------------------------------------
        // Test 1: Reset forces RD1 and RD2 to 0 even when WE3=1
        // -----------------------------------------------------------------
        #1;
        check_reads("Reset baseline A1=0 A2=0");

        A1  = 5'd5;
        A2  = 5'd10;
        A3  = 5'd5;
        WD3 = 32'hDEAD_BEEF;
        WE3 = 1'b1;
        check_reads("Reset masks forwarding on RD1/RD2");

        // Release reset, keep WE3=0 first
        @(negedge clk);
        rst = 1'b1;
        WE3 = 1'b0;
        A3  = 5'd0;
        WD3 = 32'd0;

        // -----------------------------------------------------------------
        // Test 2: x0 hard-wired to zero (write attempts & no forwarding)
        // -----------------------------------------------------------------
        begin
            reg [31:0] x0_patterns [0:3];
            x0_patterns[0] = 32'hDEAD_BEEF;
            x0_patterns[1] = 32'hFFFF_FFFF;
            x0_patterns[2] = 32'h0000_0001;
            x0_patterns[3] = 32'h8000_0000;

            for (int p = 0; p < 4; p = p + 1) begin
                @(negedge clk);
                WE3 = 1'b1;
                A3  = 5'd0;
                WD3 = x0_patterns[p];
                A1  = 5'd0;
                A2  = 5'd0;
                // Same-cycle check: must NOT forward WD3 to x0
                check_reads($sformatf("x0 same-cycle write no-forward pattern %0d", p));

                @(posedge clk);
                #1;
                check_reads($sformatf("x0 post-posedge still 0 pattern %0d (WE3=1)", p));

                @(negedge clk);
                WE3 = 1'b0;
                check_reads($sformatf("x0 post-write read with WE3=0 pattern %0d", p));
            end
        end

        // Write x7 and confirm reading x0 on A1 while forwarding x7 on A2
        write_reg(5'd7, 32'h1122_3344, 1'b1);
        @(negedge clk);
        WE3 = 1'b1;
        A3  = 5'd7;
        WD3 = 32'h5566_7788;
        A1  = 5'd0;
        A2  = 5'd7;
        check_reads("Read x0 on RD1 while forwarding x7 on RD2");
        @(posedge clk);
        ref_regs[7] = 32'h5566_7788;

        // -----------------------------------------------------------------
        // Test 3: Same-cycle read/write forwarding tests
        // -----------------------------------------------------------------
        write_reg(5'd1, 32'h1111_1111, 1'b1);
        write_reg(5'd2, 32'h2222_2222, 1'b1);
        write_reg(5'd3, 32'h3333_3333, 1'b1);

        // 3a: Forward on RD1 only (A1 == A3, A2 != A3)
        @(negedge clk);
        WE3 = 1'b1;
        A3  = 5'd1;
        WD3 = 32'hCAFE_BABE;
        A1  = 5'd1;
        A2  = 5'd2;
        check_reads("Same-cycle forward RD1 only (before posedge)");
        @(posedge clk);
        ref_regs[1] = 32'hCAFE_BABE;

        // 3b: Forward on RD2 only (A2 == A3, A1 != A3)
        @(negedge clk);
        WE3 = 1'b1;
        A3  = 5'd2;
        WD3 = 32'hBEEF_F00D;
        A1  = 5'd1;
        A2  = 5'd2;
        check_reads("Same-cycle forward RD2 only (before posedge)");
        @(posedge clk);
        ref_regs[2] = 32'hBEEF_F00D;

        // 3c: Forward on BOTH RD1 and RD2 simultaneously (A1 == A2 == A3)
        @(negedge clk);
        WE3 = 1'b1;
        A3  = 5'd3;
        WD3 = 32'hFACE_B00C;
        A1  = 5'd3;
        A2  = 5'd3;
        check_reads("Same-cycle forward both RD1 and RD2 (before posedge)");

        // 3d: Dynamic WD3 update mid-cycle tracks combinationally before posedge
        #2;
        WD3 = 32'hA5A5_5A5A;
        check_reads("Mid-cycle WD3 change updates RD1/RD2 combinationally");
        @(posedge clk);
        ref_regs[3] = 32'hA5A5_5A5A;

        // 3e: Verify committed value persists after WE3 deasserts
        @(negedge clk);
        WE3 = 1'b0;
        WD3 = 32'h9999_9999; // Must NOT forward when WE3=0
        A1  = 5'd3;
        A2  = 5'd3;
        check_reads("WE3=0 disables forwarding and reads committed x3");
        @(posedge clk); #1;
        check_reads("WE3=0 preserves x3 across posedge");

        // 3f: Back-to-back writes to same register with continuous read
        for (int k = 0; k < 4; k = k + 1) begin
            @(negedge clk);
            WE3 = 1'b1;
            A3  = 5'd15;
            A1  = 5'd15;
            A2  = 5'd1;
            WD3 = 32'hF000_0000 + k;
            check_reads($sformatf("Back-to-back write/forward x15 iter %0d", k));
            @(posedge clk);
            ref_regs[15] = 32'hF000_0000 + k;
        end

        // -----------------------------------------------------------------
        // Test 4: Reset gating with stored non-zero registers
        // -----------------------------------------------------------------
        @(negedge clk);
        WE3 = 1'b0;
        rst = 1'b0;
        A1  = 5'd1;
        A2  = 5'd15;
        check_reads("rst=0 gates stored register reads to 0");

        @(negedge clk);
        rst = 1'b1;
        check_reads("rst=1 restores visibility of stored registers");

        // -----------------------------------------------------------------
        // Test 5: Full 32-register write & dual-port read sweep + bit toggles
        // -----------------------------------------------------------------
        for (int r = 0; r < 32; r = r + 1) begin
            write_reg(r[4:0], 32'hA000_0000 ^ (r * 32'h0101_0101), 1'b1);
        end

        @(negedge clk);
        WE3 = 1'b0;
        for (int i = 0; i < 32; i = i + 1) begin
            for (int j = 0; j < 32; j = j + 1) begin
                A1 = i[4:0];
                A2 = j[4:0];
                check_reads($sformatf("Full sweep read A1=%0d A2=%0d", i, j));
            end
        end

        // Walking-1 and pattern toggle sweep on x31
        write_reg(5'd31, 32'h0000_0000, 1'b1);
        write_reg(5'd31, 32'hFFFF_FFFF, 1'b1);
        write_reg(5'd31, 32'hAAAA_AAAA, 1'b1);
        write_reg(5'd31, 32'h5555_5555, 1'b1);
        for (int b = 0; b < 32; b = b + 1) begin
            write_reg(5'd31, (32'h1 << b), 1'b1);
            @(negedge clk);
            WE3 = 1'b0;
            A1  = 5'd31;
            A2  = 5'd0;
            check_reads($sformatf("x31 walking-1 bit %0d", b));
        end

        // -----------------------------------------------------------------
        // Test 6: Constrained-random regression (500 cycles, forwarding & x0 biased)
        // -----------------------------------------------------------------
        for (int t = 0; t < 500; t = t + 1) begin
            int sel_a1, sel_a2, sel_a3;
            @(negedge clk);
            rst    = (($urandom() % 20) != 0); // 95% out of reset, 5% in reset
            WE3    = (($urandom() % 100) < 65);
            sel_a3 = $urandom() % 100;
            A3     = (sel_a3 < 20) ? 5'd0 : ($urandom() % 32);
            WD3    = $urandom();

            sel_a1 = $urandom() % 100;
            A1     = (sel_a1 < 30) ? A3 : ((sel_a1 < 45) ? 5'd0 : ($urandom() % 32));

            sel_a2 = $urandom() % 100;
            A2     = (sel_a2 < 30) ? A3 : ((sel_a2 < 45) ? 5'd0 : ($urandom() % 32));

            // Pre-clock combinational check (forwarding + reset gating + x0=0)
            check_reads($sformatf("Rand iter %0d pre-posedge", t));

            @(posedge clk);
            if (WE3 && A3 != 5'd0)
                ref_regs[A3] = WD3;
            check_reads($sformatf("Rand iter %0d post-posedge", t));
        end

        // Summary
        $display("============================================================");
        $display("tb_register_file SUMMARY: PASS=%0d, FAIL=%0d", pass_cnt, fail_cnt);
        $display("============================================================");
        if (fail_cnt != 0)
            $fatal(1, "tb_register_file FAILED with %0d error(s)", fail_cnt);
        $finish;
    end

endmodule
