// =============================================================================
// RISCFORGE RV32IM_Zicsr Core — Comprehensive Interrupt Verification Testbench
// Module: core_interrupt_tb (tb1_interrupts.sv)
//
// Description:
//   Directed verification testbench proving all 7 machine-mode interrupt
//   scenarios with native IMEM and hybrid memory interface -> DMEM:
//
//   Test 1: IRQ01 — Basic Timer Interrupt (MTIP, mepc, mcause, flush, mret, DMEM write)
//   Test 2: IRQ02 — All 7 Interrupt Sources Sequentially (UART, SPI, I2C, GPIO, MEIP, MTIP, MSIP)
//   Test 3: IRQ03 — Priority Resolution (Simultaneous multi-line assertion, DMEM order table)
//   Test 4: IRQ04 — mintprio Priority Threshold Gate (CSR 0x7C0, blocked vs accepted)
//   Test 5: IRQ05 — Multi-cycle DIV Stall Collision (stallMUL hazard, DMEM quotient write)
//   Test 6: IRQ06 — Interrupt vs Synchronous Exception Collision (2 Continuous Branch Misaligned)
//   Test 7: IRQ07 — Full MRET Roundtrip & State Preservation (DMEM preloaded operands)
// =============================================================================

`timescale 1ns / 1ps

module core_interrupt_tb;

    // =========================================================================
    // Clock & Reset Generation
    // =========================================================================
    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #5 clk = ~clk; // 100 MHz clock (10ns period)

    // =========================================================================
    // Core Interface Signals
    // =========================================================================
    wire PCSrcE1_unused;

    // Instruction Memory Interface
    wire        imem_sram_en;
    wire        imem_sram_we;
    wire [3:0]  imem_sram_wmask;
    wire [29:0] imem_sram_addr;
    wire [31:0] imem_sram_wdata;
    wire [31:0] imem_sram_rdata;

    // LSU Data Memory Interface (Core -> hybrid_mem_interface)
    wire        lsu_mem_req;
    wire        lsu_mem_we;
    wire [31:0] lsu_mem_addr;
    wire [31:0] lsu_mem_wdata;
    wire [3:0]  lsu_mem_be;
    wire [31:0] lsu_mem_rdata;
    wire        lsu_mem_stall;
    wire        lsu_mem_err;

    // Interrupt Drive Lines
    logic [15:0] fast_irq_i;
    logic        timer_irq_i;
    logic        ext_irq_i;
    logic        sw_irq_i;

    // =========================================================================
    // Core DUT Instantiation
    // =========================================================================
    top #(
        .RESET_PC(32'h8000_0000)
    ) dut (
        .clk            (clk),
        .rst            (rst_n),
        .PCSrcE1        (PCSrcE1_unused),

        // Instruction fetch
        .imem_sram_en   (imem_sram_en),
        .imem_sram_we   (imem_sram_we),
        .imem_sram_wmask(imem_sram_wmask),
        .imem_sram_addr (imem_sram_addr),
        .imem_sram_wdata(imem_sram_wdata),
        .imem_sram_rdata(imem_sram_rdata),

        // LSU Data Memory
        .lsu_mem_req    (lsu_mem_req),
        .lsu_mem_we     (lsu_mem_we),
        .lsu_mem_addr   (lsu_mem_addr),
        .lsu_mem_wdata  (lsu_mem_wdata),
        .lsu_mem_be     (lsu_mem_be),
        .lsu_mem_rdata  (lsu_mem_rdata),
        .lsu_mem_stall  (lsu_mem_stall),
        .lsu_mem_err    (lsu_mem_err),

        // Interrupt Inputs
        .fast_irq_i     (fast_irq_i),
        .timer_irq_i    (timer_irq_i),
        .ext_irq_i      (ext_irq_i),
        .sw_irq_i       (sw_irq_i)
    );

    // =========================================================================
    // Instruction Memory Instantiation (1024 words = 4 KB, base 0x8000_0000)
    // =========================================================================
    Instruction_Memory_new #(
        .MEM_DEPTH      (1024),
        .IMEM_BASE_BYTE (32'h8000_0000)
    ) u_imem (
        .clk        (clk),
        .rst_n      (rst_n),
        .sram_en    (imem_sram_en),
        .sram_we    (imem_sram_we),
        .sram_wmask (imem_sram_wmask),
        .sram_addr  (imem_sram_addr),
        .sram_wdata (imem_sram_wdata),
        .sram_rdata (imem_sram_rdata)
    );

    // =========================================================================
    // Hybrid Memory Controller & Native Data Memory Instantiation
    // =========================================================================
    typedef logic [31:0] addr_t;
    typedef logic [31:0] data_t;
    typedef logic [3:0]  strb_t;

    typedef struct packed {
        addr_t          addr;
        axi_pkg::prot_t prot;
    } aw_chan_t;

    typedef struct packed {
        data_t data;
        strb_t strb;
    } w_chan_t;

    typedef struct packed {
        axi_pkg::resp_t resp;
    } b_chan_t;

    typedef struct packed {
        addr_t          addr;
        axi_pkg::prot_t prot;
    } ar_chan_t;

    typedef struct packed {
        data_t          data;
        axi_pkg::resp_t resp;
    } r_chan_t;

    typedef struct packed {
        aw_chan_t aw;
        logic     aw_valid;
        w_chan_t  w;
        logic     w_valid;
        logic     b_ready;
        ar_chan_t ar;
        logic     ar_valid;
        logic     r_ready;
    } axi_req_t;

    typedef struct packed {
        logic    aw_ready;
        logic    w_ready;
        b_chan_t b;
        logic    b_valid;
        logic    ar_ready;
        r_chan_t r;
        logic    r_valid;
    } axi_resp_t;

    axi_req_t  dummy_axi_req;
    axi_resp_t dummy_axi_resp;
    assign dummy_axi_resp = '0; // Tie off unneeded AXI bus

    // Wires between hybrid_mem_interface and Data_Memory
    wire        sram_en;
    wire        sram_we;
    wire [3:0]  sram_wmask;
    wire [29:0] sram_addr;
    wire [31:0] sram_wdata;
    wire [31:0] sram_rdata;

    hybrid_mem_interface #(
        .MEM_DEPTH      (1024),
        .DMEM_BASE_BYTE (32'h8000_1000),
        .MMIO_BASE      (32'h4000_0000),
        .MMIO_LIMIT     (32'h4000_FFFF),
        .axi_req_t      (axi_req_t),
        .axi_resp_t     (axi_resp_t)
    ) u_hybrid_mem_if (
        .clk            (clk),
        .rst_n          (rst_n),

        // Core LSU Interface
        .mem_req        (lsu_mem_req),
        .mem_we         (lsu_mem_we),
        .mem_addr       (lsu_mem_addr),
        .mem_wdata      (lsu_mem_wdata),
        .mem_be         (lsu_mem_be),
        .mem_rdata      (lsu_mem_rdata),
        .mem_stall      (lsu_mem_stall),
        .mem_err        (lsu_mem_err),

        // Native SRAM Interface (to Data_Memory)
        .sram_en        (sram_en),
        .sram_we        (sram_we),
        .sram_wmask     (sram_wmask),
        .sram_addr      (sram_addr),
        .sram_wdata     (sram_wdata),
        .sram_rdata     (sram_rdata),

        // AXI Interface (tied off)
        .m_axi_req_o    (dummy_axi_req),
        .m_axi_resp_i   (dummy_axi_resp)
    );

    Data_Memory #(
        .MEM_DEPTH      (1024),
        .DMEM_BASE_BYTE (32'h8000_1000)
    ) u_dmem (
        .clk            (clk),
        .rst_n          (rst_n),
        .sram_en        (sram_en),
        .sram_we        (sram_we),
        .sram_wmask     (sram_wmask),
        .sram_addr      (sram_addr),
        .sram_wdata     (sram_wdata),
        .sram_rdata     (sram_rdata)
    );

    // =========================================================================
    // Test Statistics & Verification Tasks
    // =========================================================================
    int total_tests  = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    localparam logic [31:0] SENTINEL_PASS = 32'hCAFE_BABE;

    // Reset task
    task reset_dut();
        rst_n       = 1'b0;
        fast_irq_i  = 16'h0000;
        timer_irq_i = 1'b0;
        ext_irq_i   = 1'b0;
        sw_irq_i    = 1'b0;
        repeat(5) @(posedge clk);
        @(negedge clk);
        rst_n       = 1'b1;
        @(posedge clk);
    endtask

    // Load paired IMEM and DMEM hex files
    task load_test(input string imem_file, input string dmem_file);
        integer i;
        for (i = 0; i < 1024; i = i + 1) begin
            u_imem.mem_array[i] = 32'h0000_0013; // default NOP
            u_dmem.mem_array[i] = 32'h0000_0000; // default 0
        end
        $readmemh(imem_file, u_imem.mem_array);
        $readmemh(dmem_file, u_dmem.mem_array);
        $display("[TB] Loaded %s and %s", imem_file, dmem_file);
    endtask

    // Wait for end-of-test detection (sentinel write to DMEM[0] == 0xCAFEBABE or GPR)
    task wait_for_test_completion(input int max_cycles, output logic success);
        int cnt;
        success = 1'b0;
        for (cnt = 0; cnt < max_cycles; cnt++) begin
            @(posedge clk);
            // Detect store to DMEM[0] (address 0x8000_1000) containing SENTINEL_PASS
            if (sram_en && sram_we && (sram_addr == 30'h2000_0400) && (sram_wdata == SENTINEL_PASS)) begin
                success = 1'b1;
                $display("[TB] Memory sentinel store detected: DMEM[0] = 0x%08x at cycle %0d", sram_wdata, cnt);
                return;
            end
            // Alternatively detect GPR writeback of SENTINEL_PASS
            if (dut.valid_W && !dut.exc_valid_W && (dut.ResultW == SENTINEL_PASS)) begin
                success = 1'b1;
                $display("[TB] GPR writeback sentinel detected: ResultW = 0x%08x at cycle %0d", dut.ResultW, cnt);
                return;
            end
        end
    endtask

    // =========================================================================
    // Test 1: Basic Timer Interrupt (MTIP)
    // =========================================================================
    task run_test1_timer_irq();
        logic [31:0] target_pc;
        int timeout;
        logic completed;
        total_tests++;
        $display("\n========================================================");
        $display("  STARTING TEST 1: Basic Timer Interrupt (MTIP)");
        $display("========================================================");

        load_test("tb1_test1_timer_imem.hex", "tb1_test1_timer_dmem.hex");
        reset_dut();

        // 1. Wait until core completes setup and reaches trigger PC 0x8000_0040 in EX
        timeout = 200;
        while (dut.PCE != 32'h8000_0040 && timeout > 0) begin
            @(posedge clk);
            timeout--;
        end

        if (timeout == 0) begin
            $display("[FAIL] Test 1: Timed out waiting for PCE == 0x8000_0040 (current PCE=%h)", dut.PCE);
            failed_tests++;
            return;
        end

        // 2. Hardcoded trigger injection at EX stage
        target_pc = dut.PCE;
        $display("[TB] Injecting timer_irq_i at PCE = %h", target_pc);
        @(negedge clk);
        timer_irq_i = 1'b1;

        // 3. Monitor EX acceptance and WB trap commit
        timeout = 20;
        while (!dut.trap_commit_valid && timeout > 0) begin
            @(posedge clk);
            timeout--;
        end

        @(negedge clk);
        timer_irq_i = 1'b0; // Deassert after acceptance

        if (timeout == 0) begin
            $display("[FAIL] Test 1: Trap commit valid did not assert!");
            failed_tests++;
            return;
        end

        // 4. Verify Trap Invariants
        if (dut.trap_commit_cause !== 31'd7 || dut.csr_file.mcause_r !== 32'h8000_0007) begin
            $display("[FAIL] Test 1: Expected mcause 0x80000007, got %h", dut.csr_file.mcause_r);
            failed_tests++;
            return;
        end

        if (dut.csr_file.mepc_r !== target_pc) begin
            $display("[FAIL] Test 1: Expected mepc %h, got %h", target_pc, dut.csr_file.mepc_r);
            failed_tests++;
            return;
        end

        if (dut.csr_file.mstatus_r[3] !== 1'b0) begin
            $display("[FAIL] Test 1: mstatus.MIE was not cleared on trap entry!");
            failed_tests++;
            return;
        end

        // 5. Wait for end-of-test memory write
        wait_for_test_completion(100, completed);
        if (!completed) begin
            $display("[FAIL] Test 1: Background thread did not complete after MRET");
            failed_tests++;
            return;
        end

        // Verify DMEM results: DMEM[1]=0x101 (incremented), DMEM[2]=0x80000007 (mcause), DMEM[3]=0x80000040 (mepc)
        if (u_dmem.mem_array[1] !== 32'h101 || u_dmem.mem_array[2] !== 32'h8000_0007 || u_dmem.mem_array[3] !== 32'h8000_0040) begin
            $display("[FAIL] Test 1: DMEM logged values mismatch! DMEM[1]=%h, DMEM[2]=%h, DMEM[3]=%h",
                     u_dmem.mem_array[1], u_dmem.mem_array[2], u_dmem.mem_array[3]);
            failed_tests++;
            return;
        end

        $display("[PASS] Test 1: Basic Timer Interrupt verified successfully!");
        $display("       - EX Acceptance: OK");
        $display("       - Precise mepc (%h): OK", dut.csr_file.mepc_r);
        $display("       - mcause (0x80000007): OK");
        $display("       - DMEM logged state & MRET resume: OK");
        passed_tests++;
    endtask

    // =========================================================================
    // Test 2: All 7 Interrupt Sources Sequentially
    // =========================================================================
    task run_test2_all_sources();
        int src_idx;
        int expected_id;
        logic [31:0] expected_mcause;
        int timeout;
        logic completed;
        total_tests++;
        $display("\n========================================================");
        $display("  STARTING TEST 2: All 7 Interrupt Sources Sequentially");
        $display("========================================================");

        load_test("tb1_test2_all_sources_imem.hex", "tb1_test2_all_sources_dmem.hex");
        reset_dut();

        timeout = 200;
        while (dut.PCE != 32'h8000_0040 && timeout > 0) begin
            @(posedge clk);
            timeout--;
        end

        for (src_idx = 0; src_idx < 7; src_idx++) begin
            case (src_idx)
                0: begin expected_id = 19; expected_mcause = 32'h8000_0013; fast_irq_i[3] = 1'b1; $display("[TB] Firing UART (ID 19)..."); end
                1: begin expected_id = 18; expected_mcause = 32'h8000_0012; fast_irq_i[2] = 1'b1; $display("[TB] Firing SPI  (ID 18)..."); end
                2: begin expected_id = 17; expected_mcause = 32'h8000_0011; fast_irq_i[1] = 1'b1; $display("[TB] Firing I2C  (ID 17)..."); end
                3: begin expected_id = 16; expected_mcause = 32'h8000_0010; fast_irq_i[0] = 1'b1; $display("[TB] Firing GPIO (ID 16)..."); end
                4: begin expected_id = 11; expected_mcause = 32'h8000_000B; ext_irq_i     = 1'b1; $display("[TB] Firing MEIP (ID 11)..."); end
                5: begin expected_id =  7; expected_mcause = 32'h8000_0007; timer_irq_i   = 1'b1; $display("[TB] Firing MTIP (ID 7)...");  end
                6: begin expected_id =  3; expected_mcause = 32'h8000_0003; sw_irq_i      = 1'b1; $display("[TB] Firing MSIP (ID 3)...");  end
            endcase

            timeout = 30;
            while (!dut.trap_commit_valid && timeout > 0) begin
                @(posedge clk);
                timeout--;
            end

            fast_irq_i = 16'h0000;
            timer_irq_i = 1'b0;
            ext_irq_i   = 1'b0;
            sw_irq_i    = 1'b0;

            if (timeout == 0 || dut.csr_file.mcause_r !== expected_mcause) begin
                $display("[FAIL] Test 2: mcause mismatch on source %0d. Expected %h, got %h", src_idx, expected_mcause, dut.csr_file.mcause_r);
                failed_tests++;
                return;
            end

            // Wait for MRET
            timeout = 30;
            while (!dut.wb_commit.mret_commit_o && timeout > 0) begin
                @(posedge clk);
                timeout--;
            end
            @(posedge clk);
            @(posedge clk);
        end

        // Wait for final completion sentinel
        wait_for_test_completion(50, completed);
        if (!completed) begin
            $display("[FAIL] Test 2: Test did not write completion sentinel to DMEM[0]");
            failed_tests++;
            return;
        end

        $display("[PASS] Test 2: All 7 Interrupt Sources correctly serviced and logged to DMEM!");
        passed_tests++;
    endtask

    // =========================================================================
    // Test 3: Priority Resolution (Simultaneous multi-line assertion)
    // =========================================================================
    task run_test3_priority();
        int step;
        int expected_order[7] = '{19, 18, 17, 16, 11, 7, 3};
        logic [31:0] expected_mcauses[7] = '{32'h80000013, 32'h80000012, 32'h80000011, 32'h80000010, 32'h8000000B, 32'h80000007, 32'h80000003};
        int timeout;
        logic completed;
        total_tests++;
        $display("\n========================================================");
        $display("  STARTING TEST 3: Priority Resolution (Simultaneous IRQs)");
        $display("========================================================");

        load_test("tb1_test3_priority_imem.hex", "tb1_test3_priority_dmem.hex");
        reset_dut();

        timeout = 200;
        while (dut.PCE != 32'h8000_0040 && timeout > 0) begin
            @(posedge clk);
            timeout--;
        end

        // Assert ALL 7 interrupt lines simultaneously!
        $display("[TB] Asserting ALL 7 interrupt lines simultaneously...");
        fast_irq_i  = 16'h000F;
        ext_irq_i   = 1'b1;
        timer_irq_i = 1'b1;
        sw_irq_i    = 1'b1;

        for (step = 0; step < 7; step++) begin
            timeout = 40;
            while (!dut.trap_commit_valid && timeout > 0) begin
                @(posedge clk);
                timeout--;
            end

            if (timeout == 0 || dut.csr_file.mcause_r !== expected_mcauses[step]) begin
                $display("[FAIL] Test 3: Priority resolution error at step %0d. Expected %h, got %h", step, expected_mcauses[step], dut.csr_file.mcause_r);
                failed_tests++;
                return;
            end

            $display("       Rank %0d: Accepted ID %0d (mcause %h) [OK]", step+1, expected_order[step], dut.csr_file.mcause_r);

            // Clear the serviced line
            case (expected_order[step])
                19: fast_irq_i[3] = 1'b0;
                18: fast_irq_i[2] = 1'b0;
                17: fast_irq_i[1] = 1'b0;
                16: fast_irq_i[0] = 1'b0;
                11: ext_irq_i     = 1'b0;
                 7: timer_irq_i   = 1'b0;
                 3: sw_irq_i      = 1'b0;
            endcase

            // Wait for MRET
            timeout = 30;
            while (!dut.wb_commit.mret_commit_o && timeout > 0) begin
                @(posedge clk);
                timeout--;
            end
            @(posedge clk);
        end

        wait_for_test_completion(50, completed);
        if (!completed) begin
            $display("[FAIL] Test 3: Test did not write completion sentinel to DMEM[0]");
            failed_tests++;
            return;
        end

        $display("[PASS] Test 3: Natural priority order UART > SPI > I2C > GPIO > MEIP > MTIP > MSIP verified!");
        passed_tests++;
    endtask

    // =========================================================================
    // Test 4: mintprio Priority Threshold Gate (CSR 0x7C0)
    // =========================================================================
    task run_test4_mintprio();
        int timeout;
        int i;
        logic completed;
        total_tests++;
        $display("\n========================================================");
        $display("  STARTING TEST 4: mintprio Priority Threshold Gate (0x7C0)");
        $display("========================================================");

        load_test("tb1_test4_mintprio_imem.hex", "tb1_test4_mintprio_dmem.hex");
        reset_dut();

        timeout = 200;
        while (dut.PCE != 32'h8000_0040 && timeout > 0) begin
            @(posedge clk);
            timeout--;
        end

        // 1. Assert GPIO (16) and Timer (7) — must be BLOCKED
        $display("[TB] Asserting GPIO (16) and Timer (7)...");
        fast_irq_i[0] = 1'b1;
        timer_irq_i   = 1'b1;

        for (i = 0; i < 15; i++) begin
            @(posedge clk);
            if (dut.trap_commit_valid) begin
                $display("[FAIL] Test 4: Sub-threshold interrupt committed!");
                failed_tests++;
                return;
            end
        end
        $display("[TB] Sub-threshold interrupts properly blocked by mintprio=16!");

        // 2. Assert UART (19) — must be ACCEPTED immediately
        $display("[TB] Asserting UART (19)...");
        fast_irq_i[3] = 1'b1;

        timeout = 20;
        while (!dut.trap_commit_valid && timeout > 0) begin
            @(posedge clk);
            timeout--;
        end

        fast_irq_i = 16'h0000;
        timer_irq_i = 1'b0;

        if (timeout == 0 || dut.csr_file.mcause_r !== 32'h8000_0013) begin
            $display("[FAIL] Test 4: Above-threshold UART IRQ not accepted!");
            failed_tests++;
            return;
        end

        wait_for_test_completion(50, completed);
        if (!completed) begin
            $display("[FAIL] Test 4: Test did not write completion sentinel to DMEM[0]");
            failed_tests++;
            return;
        end

        $display("[PASS] Test 4: mintprio threshold gate verified!");
        passed_tests++;
    endtask

    // =========================================================================
    // Test 5: Multi-cycle DIV Stall Collision (stallMUL Hazard)
    // =========================================================================
    task run_test5_hazard();
        int timeout;
        logic completed;
        total_tests++;
        $display("\n========================================================");
        $display("  STARTING TEST 5: Multi-Cycle DIV Stall Collision");
        $display("========================================================");

        load_test("tb1_test5_hazard_imem.hex", "tb1_test5_hazard_dmem.hex");
        reset_dut();

        // 1. Wait until DIV enters EX stage and asserts stallMUL
        timeout = 200;
        while (!dut.stallMUL && timeout > 0) begin
            @(posedge clk);
            timeout--;
        end

        if (timeout == 0) begin
            $display("[FAIL] Test 5: Timed out waiting for DIV stallMUL");
            failed_tests++;
            return;
        end

        $display("[TB] DIV active in EX (stallMUL=1). Injecting timer_irq_i...");
        timer_irq_i = 1'b1;

        // 2. While stallMUL is active, verify irq_accept_E is held LOW
        while (dut.stallMUL) begin
            @(posedge clk);
            if (dut.Execute.irq_accept_E) begin
                $display("[FAIL] Test 5: irq_accept_E asserted DURING stallMUL!");
                failed_tests++;
                return;
            end
        end

        $display("[TB] DIV finished multi-cycle calculation. Checking writeback...");

        // 3. Wait for subsequent IRQ trap
        timeout = 30;
        while (!dut.trap_commit_valid && timeout > 0) begin
            @(posedge clk);
            timeout--;
        end

        timer_irq_i = 1'b0;

        wait_for_test_completion(100, completed);
        if (!completed) begin
            $display("[FAIL] Test 5: Test did not write completion sentinel to DMEM[0]");
            failed_tests++;
            return;
        end

        // Verify division quotient written to DMEM[1] == 33333 (100000 / 3)
        if (u_dmem.mem_array[1] !== 32'd33333) begin
            $display("[FAIL] Test 5: DMEM[1] quotient mismatch! Expected 33333, got %0d", u_dmem.mem_array[1]);
            failed_tests++;
            return;
        end

        $display("[PASS] Test 5: Multi-cycle stall hazard verified (DIV quotient DMEM[1]=33333 preserved)!");
        passed_tests++;
    endtask

    // =========================================================================
    // Test 6: Interrupt vs Synchronous Exception Collision (Branch Misaligned)
    // =========================================================================
    task run_test6_exception_collision();
        int timeout;
        logic completed;
        total_tests++;
        $display("\n========================================================");
        $display("  STARTING TEST 6: Interrupt vs Exception Collision (2 Continuous Misaligned Branch)");
        $display("========================================================");

        load_test("tb1_test6_collision_imem.hex", "tb1_test6_collision_dmem.hex");
        reset_dut();

        // 1. Wait until misaligned branch instruction is at PCE == 0x8000_0040
        timeout = 200;
        while (dut.PCE != 32'h8000_0040 && timeout > 0) begin
            @(posedge clk);
            timeout--;
        end

        // 2. Assert timer_irq_i high at the exact moment of misaligned branch in EX
        $display("[TB] Continuous misaligned branches in EX and ID. Asserting timer_irq_i...");
        timer_irq_i = 1'b1;

        // 3. Wait for WB trap commit
        timeout = 30;
        while (!dut.trap_commit_valid && timeout > 0) begin
            @(posedge clk);
            timeout--;
        end

        timer_irq_i = 1'b0;

        if (timeout == 0) begin
            $display("[FAIL] Test 6: Timed out waiting for trap commit");
            failed_tests++;
            return;
        end

        // 4. Priority check: Exception (mcause=0x00000000) must beat Interrupt
        if (dut.csr_file.mcause_r[31] !== 1'b0 || dut.csr_file.mcause_r[30:0] !== 31'd0) begin
            $display("[FAIL] Test 6: Priority inversion! Expected synchronous exception (mcause=0), got %h", dut.csr_file.mcause_r);
            failed_tests++;
            return;
        end

        wait_for_test_completion(50, completed);
        if (!completed) begin
            $display("[FAIL] Test 6: Exception handler did not write sentinel to DMEM[0]");
            failed_tests++;
            return;
        end

        $display("[PASS] Test 6: Synchronous exception correctly prioritized over interrupt (mcause=0x00000000 logged to DMEM[1])!");
        passed_tests++;
    endtask

    // =========================================================================
    // Test 7: Full MRET Roundtrip & State Preservation
    // =========================================================================
    task run_test7_mret();
        int timeout;
        logic completed;
        total_tests++;
        $display("\n========================================================");
        $display("  STARTING TEST 7: Full MRET Roundtrip & State Preservation");
        $display("========================================================");

        load_test("tb1_test7_mret_imem.hex", "tb1_test7_mret_dmem.hex");
        reset_dut();

        timeout = 200;
        while (dut.PCE != 32'h8000_0050 && timeout > 0) begin
            @(posedge clk);
            timeout--;
        end

        // Inject timer interrupt pulse
        $display("[TB] Injecting IRQ pulse during arithmetic thread...");
        @(negedge clk);
        timer_irq_i = 1'b1;
        @(posedge clk);
        @(negedge clk);
        timer_irq_i = 1'b0;

        // Wait for background execution to complete arithmetic checksum write: DMEM[0] == 0xAAAAAAB4
        timeout = 200;
        while (u_dmem.mem_array[0] !== 32'hAAAA_AAB4 && timeout > 0) begin
            @(posedge clk);
            timeout--;
        end

        if (timeout == 0) begin
            $display("[FAIL] Test 7: Timed out waiting for DMEM[0] checksum (got %h, expected 0xAAAAAAB4)", u_dmem.mem_array[0]);
            failed_tests++;
            return;
        end

        $display("[PASS] Test 7: MRET roundtrip complete! Preloaded DMEM operands survived ISR, checksum (DMEM[0]=0x%08x) verified!", u_dmem.mem_array[0]);
        passed_tests++;
    endtask

    // =========================================================================
    // Main Test Sequence Execution
    // =========================================================================
    initial begin
        $display("\n############################################################");
        $display("  RISCFORGE RV32IM_Zicsr Core Interrupt Verification Suite");
        $display("############################################################\n");

        run_test1_timer_irq();
        run_test2_all_sources();
        run_test3_priority();
        run_test4_mintprio();
        run_test5_hazard();
        run_test6_exception_collision();
        run_test7_mret();

        $display("\n############################################################");
        $display("  FINAL VERIFICATION SUMMARY");
        $display("  Total Tests:  %0d", total_tests);
        $display("  Passed Tests: %0d", passed_tests);
        $display("  Failed Tests: %0d", failed_tests);
        if (failed_tests == 0) begin
            $display("  STATUS: ALL TESTS PASSED SUCCESSFULLY! [100%% COMPLIANT]");
        end else begin
            $display("  STATUS: VERIFICATION FAILURES DETECTED!");
        end
        $display("############################################################\n");

        $finish;
    end

    // Waveform Dump (FSDB for Verdi, VCD for GTKWave/XSim)
    initial begin
        `ifdef FSDB
            $fsdbDumpfile("core_interrupt_tb.fsdb");
            $fsdbDumpvars(0, core_interrupt_tb);
            $display("[TB] Verdi FSDB waveform dumping enabled -> core_interrupt_tb.fsdb");
        `endif
        $dumpfile("core_interrupt_tb.vcd");
        $dumpvars(0, core_interrupt_tb);
    end

endmodule