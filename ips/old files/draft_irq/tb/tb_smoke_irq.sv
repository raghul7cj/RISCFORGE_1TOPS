`timescale 1ns / 1ps

module tb_smoke_irq;

    reg clk;
    reg rst_n;
    integer pass_count = 0;
    integer fail_count = 0;

    // Clock generation (100 MHz -> 10ns period)
    always #5 clk = ~clk;

    // =========================================================================
    // SECTION 1: Unit Test — irq_gateway
    // =========================================================================
    reg  [5:0] gw_raw;
    reg  [5:0] gw_edge_mode;
    reg  [5:0] gw_clear;
    wire [5:0] gw_pend;

    irq_gateway u_gw_unit (
        .clk_i       (clk),
        .rst_ni      (rst_n),
        .irq_raw_i   (gw_raw),
        .edge_mode_i (gw_edge_mode),
        .clear_i     (gw_clear),
        .pend_o      (gw_pend)
    );

    // =========================================================================
    // SECTION 2: Unit Test — irq_arbiter
    // =========================================================================
    reg  [5:0]  arb_pend;
    reg  [31:0] arb_mie;
    reg         arb_mstatus_mie;
    reg  [1:0]  arb_cur_class;
    reg  [1:0]  arb_nest_depth;
    reg         arb_wb_commit;
    reg  [4:0]  arb_wb_trap_cause;
    wire        arb_pending;
    wire [4:0]  arb_id;
    wire [1:0]  arb_class;

    irq_arbiter u_arb_unit (
        .clk_i           (clk),
        .rst_ni          (rst_n),
        .pend_i          (arb_pend),
        .mie_i           (arb_mie),
        .mstatus_mie_i   (arb_mstatus_mie),
        .cur_class_i     (arb_cur_class),
        .nest_depth_i    (arb_nest_depth),
        .wb_commit_i     (arb_wb_commit),
        .wb_trap_cause_i (arb_wb_trap_cause),
        .irq_pending_o   (arb_pending),
        .irq_id_o        (arb_id),
        .irq_class_o     (arb_class)
    );

    // =========================================================================
    // SECTION 3: Divider Abort Test — rv32m_div
    // =========================================================================
    reg         div_valid_in;
    reg         div_abort_in;
    reg  [31:0] div_rs1;
    reg  [31:0] div_rs2;
    wire        div_stall;
    wire        div_valid_out;
    wire [31:0] div_result;

    rv32m_div u_div_unit (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (div_valid_in),
        .abort_i   (div_abort_in),
        .stall     (div_stall),
        .valid_out (div_valid_out),
        .rs1       (div_rs1),
        .rs2       (div_rs2),
        .funct3    (3'b100), // DIV
        .rd_in     (5'd1),
        .result    (div_result),
        .rd_out    ()
    );

    // =========================================================================
    // SECTION 4: Top-Level Core Integration
    // =========================================================================
    reg  [15:0] core_fast_irq;
    reg         core_timer_irq;
    reg         core_ext_irq;
    reg         core_sw_irq;

    wire        imem_sram_en;
    wire        imem_sram_we;
    wire [3:0]  imem_sram_wmask;
    wire [29:0] imem_sram_addr;
    wire [31:0] imem_sram_wdata;
    reg  [31:0] imem_sram_rdata;

    wire        lsu_mem_req;
    wire        lsu_mem_we;
    wire [31:0] lsu_mem_addr;
    wire [31:0] lsu_mem_wdata;
    wire [3:0]  lsu_mem_be;
    reg  [31:0] lsu_mem_rdata;

    top #(
        .RESET_PC(32'h0000_0000)
    ) u_core_top (
        .clk             (clk),
        .rst             (rst_n),
        .PCSrcE1         (),
        .imem_sram_en    (imem_sram_en),
        .imem_sram_we    (imem_sram_we),
        .imem_sram_wmask (imem_sram_wmask),
        .imem_sram_addr  (imem_sram_addr),
        .imem_sram_wdata (imem_sram_wdata),
        .imem_sram_rdata (imem_sram_rdata),
        .lsu_mem_req     (lsu_mem_req),
        .lsu_mem_we      (lsu_mem_we),
        .lsu_mem_addr    (lsu_mem_addr),
        .lsu_mem_wdata   (lsu_mem_wdata),
        .lsu_mem_be      (lsu_mem_be),
        .lsu_mem_rdata   (lsu_mem_rdata),
        .lsu_mem_stall   (1'b0),
        .lsu_mem_err     (1'b0),
        .fast_irq_i      (core_fast_irq),
        .timer_irq_i     (core_timer_irq),
        .ext_irq_i       (core_ext_irq),
        .sw_irq_i        (core_sw_irq)
    );

    // Simple Instruction ROM
    reg [31:0] imem [0:1023];
    always @(posedge clk) begin
        if (imem_sram_en) begin
            imem_sram_rdata <= imem[imem_sram_addr[9:0]];
        end
    end

    // =========================================================================
    // Test Tasks & Assertions
    // =========================================================================
    task check_condition(input bit cond, input string name);
        if (cond) begin
            $display("[PASS] %s", name);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] %s", name);
            fail_count = fail_count + 1;
        end
    endtask

    // =========================================================================
    // Main Test Stimulus
    // =========================================================================
    initial begin
        $display("================================================================");
        $display("RISCFORGE Two-Level Priority Class Interrupt Architecture Verification");
        $display("================================================================");

        clk = 0;
        rst_n = 0;
        gw_raw = 6'b0;
        gw_edge_mode = 6'b110101; // WD(5)=1, T0(4)=1, UART(3)=0, SPI(2)=1, I2C(1)=0, GPIO(0)=1
        gw_clear = 6'b0;

        arb_pend = 6'b0;
        arb_mie = 32'hFFFFFFFF;
        arb_mstatus_mie = 1'b1;
        arb_cur_class = 2'b00;
        arb_nest_depth = 2'b00;
        arb_wb_commit = 1'b0;
        arb_wb_trap_cause = 5'd0;

        div_valid_in = 0;
        div_abort_in = 0;
        div_rs1 = 32'd1000;
        div_rs2 = 32'd7;

        core_fast_irq = 16'h0;
        core_timer_irq = 1'b0;
        core_ext_irq = 1'b0;
        core_sw_irq = 1'b0;
        lsu_mem_rdata = 32'h0;

        // Populate instruction memory with NOPs
        for (int i = 0; i < 1024; i = i + 1) begin
            imem[i] = 32'h00000013; // nop (addi x0, x0, 0)
        end

        #20;
        rst_n = 1;
        @(posedge clk);
        #1;

        // ---------------------------------------------------------------------
        // TEST 1: Gateway Pulse Capture & Clear Precedence (T-01, T-03, T-04)
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 1] Gateway Pulse Capture & Pulse-Wins Precedence ---");
        
        // 1.1 Single-cycle pulse on edge line (Timer 0: bit 4)
        gw_raw[4] = 1'b1;
        @(posedge clk); #1;
        gw_raw[4] = 1'b0;
        @(posedge clk); #1;
        check_condition(gw_pend[4] == 1'b1, "T-01: Timer0 single-cycle pulse captured and held sticky");

        // 1.2 Clear strobe on Timer 0
        gw_clear[4] = 1'b1;
        @(posedge clk); #1;
        gw_clear[4] = 1'b0;
        @(posedge clk); #1;
        check_condition(gw_pend[4] == 1'b0, "T-01b: Timer0 pending cleared by clear_i[4]");

        // 1.3 Level line pass-through (UART: bit 3)
        gw_raw[3] = 1'b1;
        #1;
        check_condition(gw_pend[3] == 1'b1, "T-01c: Level mode UART passes through combinationally");
        gw_raw[3] = 1'b0;
        #1;
        check_condition(gw_pend[3] == 1'b0, "T-01d: Level mode UART de-asserts immediately when raw drops");

        // 1.4 Simultaneous pulse vs clear race (Pulse strictly wins)
        gw_raw[0] = 1'b1; // Rising edge on GPIO
        gw_clear[0] = 1'b1; // Simultaneous clear
        @(posedge clk); #1;
        gw_raw[0] = 1'b0;
        gw_clear[0] = 1'b0;
        @(posedge clk); #1;
        check_condition(gw_pend[0] == 1'b1, "T-04: Pulse-wins race condition resolved in favor of new pulse");
        gw_clear[0] = 1'b1;
        @(posedge clk); #1;
        gw_clear[0] = 1'b0;

        // ---------------------------------------------------------------------
        // TEST 2: Arbiter Inter-Class Strict Priority (T-07)
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 2] Arbiter Inter-Class Strict Priority ---");
        // Assert Class 0 (GPIO, mcause 16), Class 1 (UART, mcause 19), Class 2 (Timer0, mcause 7)
        arb_pend = 6'b011001; // Timer0 (4), UART (3), GPIO (0)
        #1;
        check_condition((arb_pending == 1'b1) && (arb_id == 5'd7) && (arb_class == 2'd2),
                        "T-07a: Class 2 (Timer0, id=7) strictly preempts Class 1 and Class 0");

        // Remove Class 2 -> Class 1 must win
        arb_pend = 6'b001001; // UART (3), GPIO (0)
        #1;
        check_condition((arb_pending == 1'b1) && (arb_id == 5'd19) && (arb_class == 2'd1),
                        "T-07b: Class 1 (UART, id=19) strictly preempts Class 0 (GPIO)");

        // Remove Class 1 -> Class 0 must win
        arb_pend = 6'b000001; // GPIO (0)
        #1;
        check_condition((arb_pending == 1'b1) && (arb_id == 5'd16) && (arb_class == 2'd0),
                        "T-07c: Class 0 (GPIO, id=16) selected when Class 2 and 1 are silent");

        // ---------------------------------------------------------------------
        // TEST 3: Intra-Class Round-Robin Fairness Under Contention (T-08, T-09)
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 3] Intra-Class Round-Robin Fairness (UART vs SPI) ---");
        arb_pend = 6'b001100; // Both UART (bit 3) and SPI (bit 2) active
        #1;
        check_condition(arb_id == 5'd19, "T-08a: Initial winner is UART (id=19)");

        // Commit UART -> pointer toggles to SPI
        arb_wb_commit = 1'b1;
        arb_wb_trap_cause = 5'd19;
        @(posedge clk); #1;
        arb_wb_commit = 1'b0;
        check_condition(arb_id == 5'd18, "T-08b: After UART commit, SPI (id=18) is selected next");

        // Commit SPI -> pointer toggles back to UART
        arb_wb_commit = 1'b1;
        arb_wb_trap_cause = 5'd18;
        @(posedge clk); #1;
        arb_wb_commit = 1'b0;
        check_condition(arb_id == 5'd19, "T-08c: After SPI commit, UART (id=19) is selected again (Fair Round-Robin)");

        // Class 0 Round-Robin (I2C vs GPIO)
        arb_pend = 6'b000011; // Both I2C (bit 1) and GPIO (bit 0) active
        #1;
        check_condition(arb_id == 5'd17, "T-09a: Initial Class 0 winner is I2C (id=17)");
        arb_wb_commit = 1'b1;
        arb_wb_trap_cause = 5'd17;
        @(posedge clk); #1;
        arb_wb_commit = 1'b0;
        check_condition(arb_id == 5'd16, "T-09b: After I2C commit, GPIO (id=16) is selected next");

        // ---------------------------------------------------------------------
        // TEST 4: Hardware Preemption Gating (No Equal-Class Preemption)
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 4] Preemption Gating & Threshold ---");
        arb_cur_class = 2'd1; // CPU is currently executing Class 1 ISR
        arb_nest_depth = 2'd1;
        arb_pend = 6'b001100; // Another Class 1 (UART/SPI) asserts
        #1;
        check_condition(arb_pending == 1'b0, "G4.1: Equal-class interrupt (Class 1) blocked during Class 1 ISR");

        // Class 2 (Timer0) arrives -> MUST pass
        arb_pend[4] = 1'b1;
        #1;
        check_condition((arb_pending == 1'b1) && (arb_id == 5'd7) && (arb_class == 2'd2),
                        "G4.1b: Higher class (Class 2 Timer0) successfully passes preemption threshold");
        arb_cur_class = 2'd0;
        arb_nest_depth = 2'd0;
        arb_pend = 6'b0;

        // ---------------------------------------------------------------------
        // TEST 5: Iterative Divider Abortion & Recovery (T-05, G4.2, G4.3)
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 5] Iterative Divider Abortion & Quick Recovery ---");
        // Start division
        @(posedge clk); #1;
        div_valid_in = 1'b1;
        @(posedge clk); #1;
        div_valid_in = 1'b0;

        // Wait 5 cycles into computation (while stall is active)
        repeat (5) @(posedge clk); #1;
        check_condition(div_stall == 1'b1, "T-05a: Divider computation active (stall=1)");

        // Assert abort strobe (simulating irq_accept_E & stallMUL)
        div_abort_in = 1'b1;
        @(posedge clk); #1;
        div_abort_in = 1'b0;
        @(posedge clk); #1;
        check_condition((div_stall == 1'b0) && (div_valid_out == 1'b0),
                        "T-05b: Divider immediately aborted to IDLE within 1 cycle, stall dropped");

        // Verify clean restart of division after abort
        div_valid_in = 1'b1;
        div_rs1 = 32'd84;
        div_rs2 = 32'd7;
        @(posedge clk); #1;
        div_valid_in = 1'b0;
        // Wait until completion
        while (!div_valid_out) @(posedge clk);
        #1;
        check_condition((div_result == 32'd12), "T-05c: Restarted division completed with exact correct quotient (84 / 7 = 12)");

        // ---------------------------------------------------------------------
        // TEST 6: Hardware Shadow Stack 2-Deep Nested Preemption (T-11)
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 6] 2-Deep Hardware Shadow Stack Push/Pop Verification ---");
        // Verify CSR shadow stack state using csr_file in core
        check_condition(u_core_top.csr_file.nest_depth == 2'd0, "T-11a: Initial nest_depth is 0 (Main Thread)");

        // Step 1: Simulate Trap commit for Class 0 (GPIO, PC = 0x1000)
        force u_core_top.csr_file.trap_valid_i = 1'b1;
        force u_core_top.csr_file.trap_is_interrupt_i = 1'b1;
        force u_core_top.csr_file.trap_cause_i = 31'd16;
        force u_core_top.csr_file.trap_class_i = 2'd0;
        force u_core_top.csr_file.trap_pc_i = 32'h0000_1000;
        @(posedge clk); #1;
        release u_core_top.csr_file.trap_valid_i;
        release u_core_top.csr_file.trap_is_interrupt_i;
        release u_core_top.csr_file.trap_cause_i;
        release u_core_top.csr_file.trap_class_i;
        release u_core_top.csr_file.trap_pc_i;

        check_condition((u_core_top.csr_file.nest_depth == 2'd1) &&
                        (u_core_top.csr_file.mepc_r == 32'h0000_1000) &&
                        (u_core_top.csr_file.cur_class_r == 2'd0),
                        "T-11b: Level 1 trap pushed to stack: mepc=0x1000, nest_depth=1, cur_class=0");

        // Step 2: Nested Preemption by Class 1 (UART, PC = 0x2050)
        force u_core_top.csr_file.trap_valid_i = 1'b1;
        force u_core_top.csr_file.trap_is_interrupt_i = 1'b1;
        force u_core_top.csr_file.trap_cause_i = 31'd19;
        force u_core_top.csr_file.trap_class_i = 2'd1;
        force u_core_top.csr_file.trap_pc_i = 32'h0000_2050;
        @(posedge clk); #1;
        release u_core_top.csr_file.trap_valid_i;
        release u_core_top.csr_file.trap_is_interrupt_i;
        release u_core_top.csr_file.trap_cause_i;
        release u_core_top.csr_file.trap_class_i;
        release u_core_top.csr_file.trap_pc_i;

        check_condition((u_core_top.csr_file.nest_depth == 2'd2) &&
                        (u_core_top.csr_file.mepc_r == 32'h0000_2050) &&
                        (u_core_top.csr_file.cur_class_r == 2'd1),
                        "T-11c: Level 2 trap pushed to stack: mepc=0x2050, nest_depth=2, cur_class=1");

        // Step 3: MRET commit from Level 2 -> returns to Level 1
        force u_core_top.csr_file.mret_commit_i = 1'b1;
        @(posedge clk); #1;
        release u_core_top.csr_file.mret_commit_i;

        check_condition((u_core_top.csr_file.nest_depth == 2'd1) &&
                        (u_core_top.csr_file.mepc_r == 32'h0000_1000) &&
                        (u_core_top.csr_file.cur_class_r == 2'd0),
                        "T-11d: MRET from Level 2 popped stack: mepc restored to 0x1000, cur_class restored to 0");

        // Step 4: MRET commit from Level 1 -> returns to Main Thread
        force u_core_top.csr_file.mret_commit_i = 1'b1;
        @(posedge clk); #1;
        release u_core_top.csr_file.mret_commit_i;

        check_condition((u_core_top.csr_file.nest_depth == 2'd0) &&
                        (u_core_top.csr_file.cur_class_r == 2'd0),
                        "T-11e: MRET from Level 1 popped stack: returned to Main Thread (nest_depth=0)");

        // =====================================================================
        // Final Summary
        // =====================================================================
        $display("\n================================================================");
        $display("VERIFICATION SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL TESTS PASSED SUCCESSFULLY! <<<\n");
        end else begin
            $display(">>> SOME TESTS FAILED! <<<\n");
        end

        $finish;
    end

endmodule
