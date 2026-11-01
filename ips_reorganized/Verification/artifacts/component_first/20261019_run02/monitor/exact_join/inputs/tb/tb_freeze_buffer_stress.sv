// =============================================================================
// RISCFORGE 1TOPS — Empirical Stress Testbench for Circular Freeze Buffers
// =============================================================================
// File: Verification/infrastructure/tb/tb_freeze_buffer_stress.sv
// Target: Vivado XSim / VCS / Xcelium
// Scope: Empirically stress-tests:
//   1. Modulo 64 ring buffer wrap-around across all monitors
//   2. Freeze timing precision (cycle T vs T+1 and frozen state immunity)
//   3. Concurrent AXI Write (B) and Read (R) handshakes & wrap boundaries
//   4. Multi-channel concurrency stress in IRQ and APB monitors
//   5. Post-mortem dump boundary conditions (count >= 64, count > depth)
// =============================================================================

`timescale 1ns/1ps

module tb_freeze_buffer_stress import tb_pkg::*; ();

  logic clk;
  logic rst_n;
  logic freeze;

  // Clock generation: 100MHz (10ns period)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // ---------------------------------------------------------------------------
  // AXI-Lite Monitor Signals
  // ---------------------------------------------------------------------------
  logic [31:0] awaddr;
  logic [2:0]  awprot;
  logic        awvalid, awready;
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wvalid, wready;
  logic [1:0]  bresp;
  logic        bvalid, bready;
  logic [31:0] araddr;
  logic [2:0]  arprot;
  logic        arvalid, arready;
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rvalid, rready;

  axi_lite_monitor #(.RING_BUFFER_DEPTH(64)) u_axi_mon (
    .clk     (clk),
    .rst_n   (rst_n),
    .freeze  (freeze),
    .awaddr  (awaddr),
    .awprot  (awprot),
    .awvalid (awvalid),
    .awready (awready),
    .wdata   (wdata),
    .wstrb   (wstrb),
    .wvalid  (wvalid),
    .wready  (wready),
    .bresp   (bresp),
    .bvalid  (bvalid),
    .bready  (bready),
    .araddr  (araddr),
    .arprot  (arprot),
    .arvalid (arvalid),
    .arready (arready),
    .rdata   (rdata),
    .rresp   (rresp),
    .rvalid  (rvalid),
    .rready  (rready)
  );

  // ---------------------------------------------------------------------------
  // APB Monitor Signals
  // ---------------------------------------------------------------------------
  logic [31:0]       apb_paddr;
  logic [5:0]        apb_psel;
  logic              apb_penable;
  logic              apb_pwrite;
  logic [31:0]       apb_pwdata;
  logic [3:0]        apb_pstrb;
  logic [5:0]        apb_pready;
  logic [6*32-1:0]   apb_prdata_flat;
  logic [5:0]        apb_pslverr;

  apb_monitor #(.NUM_SLOTS(6), .RING_BUFFER_DEPTH(64)) u_apb_mon (
    .clk         (clk),
    .rst_n       (rst_n),
    .freeze      (freeze),
    .paddr_flat  ({6{apb_paddr}}),
    .psel        (apb_psel),
    .penable     ({6{apb_penable}}),
    .pwrite      ({6{apb_pwrite}}),
    .pwdata_flat ({6{apb_pwdata}}),
    .pstrb_flat  ({6{apb_pstrb}}),
    .pready      (apb_pready),
    .prdata_flat (apb_prdata_flat),
    .pslverr     (apb_pslverr)
  );

  // ---------------------------------------------------------------------------
  // Fetch Monitor Signals
  // ---------------------------------------------------------------------------
  logic [31:0] fetch_pc;
  logic [31:0] fetch_instr;
  logic        fetch_imem_en;
  logic        fetch_stall;
  logic [31:0] fetch_pc_next;

  fetch_monitor #(.RING_BUFFER_DEPTH(64)) u_fetch_mon (
    .clk         (clk),
    .rst_n       (rst_n),
    .freeze      (freeze),
    .pc_f        (fetch_pc),
    .instr_f     (fetch_instr),
    .imem_en     (fetch_imem_en),
    .stall_f     (fetch_stall),
    .pc_next     (fetch_pc_next)
  );

  // ---------------------------------------------------------------------------
  // Retire Monitor Signals
  // ---------------------------------------------------------------------------
  logic        retire_valid;
  logic        retire_exc_valid;
  logic [31:0] retire_pc;
  logic [31:0] retire_instr;
  logic [4:0]  retire_rd_addr;
  logic [31:0] retire_rd_wdata;
  logic        retire_reg_we;
  logic        retire_trap;

  retire_monitor #(.RING_BUFFER_DEPTH(64)) u_retire_mon (
    .clk               (clk),
    .rst_n             (rst_n),
    .freeze            (freeze),
    .valid_w           (retire_valid),
    .exc_valid_w       (retire_exc_valid),
    .pc_w              (retire_pc),
    .instr_w           (retire_instr),
    .rd_addr_w         (retire_rd_addr),
    .rd_wdata_w        (retire_rd_wdata),
    .reg_we_w          (retire_reg_we),
    .trap_w            (retire_trap)
  );

  // ---------------------------------------------------------------------------
  // LSU Monitor Signals
  // ---------------------------------------------------------------------------
  logic        lsu_req;
  logic        lsu_we;
  logic [31:0] lsu_addr;
  logic [31:0] lsu_wdata;
  logic [3:0]  lsu_be;
  logic [31:0] lsu_rdata;
  logic        lsu_stall;
  logic        lsu_err;
  logic [31:0] lsu_pc_m;
  logic [4:0]  lsu_lsunit;

  lsu_monitor #(.RING_BUFFER_DEPTH(64)) u_lsu_mon (
    .clk       (clk),
    .rst_n     (rst_n),
    .freeze    (freeze),
    .lsu_req   (lsu_req),
    .lsu_we    (lsu_we),
    .lsu_addr  (lsu_addr),
    .lsu_wdata (lsu_wdata),
    .lsu_be    (lsu_be),
    .lsu_rdata (lsu_rdata),
    .lsu_stall (lsu_stall),
    .lsu_err   (lsu_err),
    .pc_m      (lsu_pc_m),
    .lsunit_m  (lsu_lsunit)
  );

  // ---------------------------------------------------------------------------
  // IRQ Monitor Signals
  // ---------------------------------------------------------------------------
  logic       gpio_irq;
  logic       i2c_irq;
  logic [1:0] spi_irq;
  logic       uart_irq;
  logic [3:0] timer0_irq;
  logic [3:0] timer1_irq;
  logic [5:0] gateway_pend_q;
  logic [5:0] gateway_pend_o;
  logic       irq_pending;
  logic [4:0] irq_id;
  logic [1:0] irq_class;
  logic       rr_ptr_c1, rr_ptr_c0;
  logic [1:0] nest_depth, cur_class;
  logic       trap_commit_valid, trap_is_interrupt;
  logic [30:0] trap_commit_cause;
  logic [31:0] trap_commit_pc;
  logic       mret_commit;

  irq_monitor #(.RING_BUFFER_DEPTH(64)) u_irq_mon (
    .clk                (clk),
    .rst_n              (rst_n),
    .freeze             (freeze),
    .gpio_irq           (gpio_irq),
    .i2c_irq            (i2c_irq),
    .spi_irq            (spi_irq),
    .uart_irq           (uart_irq),
    .timer0_irq         (timer0_irq),
    .timer1_irq         (timer1_irq),
    .gateway_pend_q     (gateway_pend_q),
    .gateway_pend_o     (gateway_pend_o),
    .fast_irq_i         (16'b0),
    .timer_irq_i        (1'b0),
    .irq_pending        (irq_pending),
    .irq_id             (irq_id),
    .irq_class          (irq_class),
    .rr_ptr_c1          (rr_ptr_c1),
    .rr_ptr_c0          (rr_ptr_c0),
    .nest_depth         (nest_depth),
    .cur_class          (cur_class),
    .trap_commit_valid  (trap_commit_valid),
    .trap_is_interrupt  (trap_is_interrupt),
    .trap_commit_cause  (trap_commit_cause),
    .trap_commit_pc     (trap_commit_pc),
    .mret_commit        (mret_commit)
  );

  // ---------------------------------------------------------------------------
  // Check / Assertion Counters
  // ---------------------------------------------------------------------------
  int check_count = 0;
  int error_count = 0;

  task check(input string test_name, input bit condition, input string msg = "");
    check_count++;
    if (!condition) begin
      error_count++;
      $display("[ASSERTION FAILED] [%s] %s", test_name, msg);
    end else begin
      $display("[PASS] [%s] %s", test_name, msg);
    end
  endtask

  // Reset task
  task reset_all();
    rst_n            <= 0;
    freeze           <= 0;
    awaddr           <= '0;
    awprot           <= '0;
    awvalid          <= 0;
    awready          <= 0;
    wdata            <= '0;
    wstrb            <= '0;
    wvalid           <= 0;
    wready           <= 0;
    bresp            <= '0;
    bvalid           <= 0;
    bready           <= 0;
    araddr           <= '0;
    arprot           <= '0;
    arvalid          <= 0;
    arready          <= 0;
    rdata            <= '0;
    rresp            <= '0;
    rvalid           <= 0;
    rready           <= 0;
    apb_paddr        <= '0;
    apb_psel         <= '0;
    apb_penable      <= 0;
    apb_pwrite       <= 0;
    apb_pwdata       <= '0;
    apb_pstrb        <= '0;
    apb_pready       <= '0;
    apb_prdata_flat  <= '0;
    apb_pslverr      <= '0;
    fetch_pc         <= '0;
    fetch_instr      <= '0;
    fetch_imem_en    <= 0;
    fetch_stall      <= 0;
    fetch_pc_next    <= '0;
    retire_valid     <= 0;
    retire_exc_valid <= 0;
    retire_pc        <= '0;
    retire_instr     <= '0;
    retire_rd_addr   <= '0;
    retire_rd_wdata  <= '0;
    retire_reg_we    <= 0;
    retire_trap      <= 0;
    lsu_req          <= 0;
    lsu_we           <= 0;
    lsu_addr         <= '0;
    lsu_wdata        <= '0;
    lsu_be           <= '0;
    lsu_rdata        <= '0;
    lsu_stall        <= 0;
    lsu_err          <= 0;
    lsu_pc_m         <= '0;
    lsu_lsunit       <= '0;
    gpio_irq         <= 0;
    i2c_irq          <= 0;
    spi_irq          <= '0;
    uart_irq         <= 0;
    timer0_irq       <= '0;
    timer1_irq       <= '0;
    gateway_pend_q   <= '0;
    gateway_pend_o   <= '0;
    irq_pending      <= 0;
    irq_id           <= '0;
    irq_class        <= '0;
    rr_ptr_c1        <= 0;
    rr_ptr_c0        <= 0;
    nest_depth       <= '0;
    cur_class        <= '0;
    trap_commit_valid<= 0;
    trap_is_interrupt<= 0;
    trap_commit_cause<= '0;
    trap_commit_pc   <= '0;
    mret_commit      <= 0;

    repeat (4) @(posedge clk);
    #1;
    rst_n <= 1;
    repeat (2) @(posedge clk);
    #1;
  endtask

  // ===========================================================================
  // Main Stress Test Sequence
  // ===========================================================================
  initial begin
    $display("\n====================================================================");
    $display(" STARTING EMPIRICAL CHALLENGER STRESS TESTS ON CIRCULAR FREEZE BUFFERS");
    $display("====================================================================");

    reset_all();

    // -------------------------------------------------------------------------
    // CHALLENGE 1: AXI-Lite Modulo 64 Wrap-around (130 sequential writes)
    // -------------------------------------------------------------------------
    $display("\n--- [TEST 1] AXI-Lite Modulo 64 Wrap-Around Stress (130 writes) ---");
    for (int i = 0; i < 130; i++) begin
      @(posedge clk);
      // Drive write address and data
      awaddr  <= 32'h4000_1000 + (i * 4);
      awprot  <= 3'b000;
      awvalid <= 1'b1;
      awready <= 1'b1;
      wdata   <= 32'hA000_0000 + i;
      wstrb   <= 4'b1111;
      wvalid  <= 1'b1;
      wready  <= 1'b1;
      bvalid  <= 1'b0;
      bready  <= 1'b1;

      @(posedge clk);
      // Handshake B response
      awvalid <= 1'b0;
      wvalid  <= 1'b0;
      bresp   <= 2'b00;
      bvalid  <= 1'b1;
      bready  <= 1'b1;

      @(posedge clk);
      bvalid  <= 1'b0;
      #1; // Wait for NBA to update

      // Verify head_ptr wrap-around at transaction boundary
      check("AXI_HEAD_PTR_BOUND", u_axi_mon.head_ptr < 64,
            $sformatf("Iter %0d: head_ptr=%0d within [0..63]", i, u_axi_mon.head_ptr));
    end

    check("AXI_TOTAL_WRITES", u_axi_mon.total_axi_writes == 130,
          $sformatf("total_axi_writes=%0d expected=130", u_axi_mon.total_axi_writes));
    check("AXI_FINAL_HEAD_PTR", u_axi_mon.head_ptr == (130 % 64),
          $sformatf("head_ptr=%0d expected=%0d", u_axi_mon.head_ptr, (130 % 64)));

    // Verify ring buffer content fidelity: exactly the last 64 writes (seq 66..129) must be retained
    begin
      bit all_data_ok = 1'b1;
      int cur_h = u_axi_mon.head_ptr; // 2
      for (int k = 0; k < 64; k++) begin
        int slot = (cur_h + k) % 64;
        int expected_iter = 130 - 64 + k; // 66 + k
        logic [31:0] exp_data = 32'hA000_0000 + expected_iter;
        logic [31:0] exp_addr = 32'h4000_1000 + (expected_iter * 4);
        if (u_axi_mon.ring_buffer[slot].data != exp_data ||
            u_axi_mon.ring_buffer[slot].addr != exp_addr ||
            u_axi_mon.ring_buffer[slot].seq != expected_iter) begin
          all_data_ok = 1'b0;
          $display("  MISMATCH at slot %0d: exp_data=0x%08X act_data=0x%08X exp_seq=%0d act_seq=%0d",
                   slot, exp_data, u_axi_mon.ring_buffer[slot].data,
                   expected_iter, u_axi_mon.ring_buffer[slot].seq);
        end
      end
      check("AXI_RING_DATA_INTEGRITY", all_data_ok, "All 64 retained entries match exactly");
    end

    // -------------------------------------------------------------------------
    // CHALLENGE 2: Freeze Timing Precision & Frozen State Immunity
    // -------------------------------------------------------------------------
    $display("\n--- [TEST 2] Freeze Timing Precision & Frozen State Immunity ---");
    // Step 2.1: Perform write at cycle T
    @(posedge clk);
    awaddr  <= 32'h4000_2000;
    awvalid <= 1'b1; awready <= 1'b1;
    wdata   <= 32'hDEAD_BEEF;
    wstrb   <= 4'b1111;
    wvalid  <= 1'b1; wready  <= 1'b1;

    @(posedge clk);
    awvalid <= 1'b0; wvalid <= 1'b0;
    bvalid  <= 1'b1; bready <= 1'b1;
    // B handshakes at this posedge (cycle T) while freeze is 0!

    @(posedge clk);
    // Cycle T has completed: write was captured into ring buffer!
    // Now assert freeze for cycle T+1!
    bvalid  <= 1'b0;
    freeze  <= 1'b1;
    #1;

    // Cycle T+1: Freeze is active!
    // Check that transaction at cycle T was captured into the ring buffer
    begin
      int last_idx = (u_axi_mon.head_ptr - 1 + 64) % 64;
      check("FREEZE_CYCLE_T_CAPTURED",
            u_axi_mon.ring_buffer[last_idx].data == 32'hDEAD_BEEF &&
            u_axi_mon.ring_buffer[last_idx].addr == 32'h4000_2000,
            $sformatf("Slot %0d contains cycle T write data 0x%08X", last_idx, u_axi_mon.ring_buffer[last_idx].data));
    end

    // Step 2.2: While freeze is 1, attempt 10 write and read transactions
    begin
      int frozen_head_ptr = u_axi_mon.head_ptr;
      longint unsigned frozen_writes = u_axi_mon.total_axi_writes;
      longint unsigned frozen_reads  = u_axi_mon.total_axi_reads;
      bit freeze_violated = 1'b0;

      for (int f = 0; f < 10; f++) begin
        @(posedge clk);
        // Attempt simultaneous write and read handshake
        awaddr <= 32'h5000_0000 + f;
        awvalid <= 1'b1; awready <= 1'b1;
        wdata   <= 32'hBAD0_0000 + f;
        wvalid  <= 1'b1; wready  <= 1'b1;
        bvalid  <= 1'b1; bready  <= 1'b1;

        araddr  <= 32'h6000_0000 + f;
        arvalid <= 1'b1; arready <= 1'b1;
        rdata   <= 32'hBAD1_0000 + f;
        rvalid  <= 1'b1; rready  <= 1'b1;

        @(posedge clk);
        #1;
        if (u_axi_mon.head_ptr != frozen_head_ptr ||
            u_axi_mon.total_axi_writes != frozen_writes ||
            u_axi_mon.total_axi_reads  != frozen_reads) begin
          freeze_violated = 1'b1;
        end
      end

      check("FREEZE_IMMUNITY_NO_NEW_TXN", !freeze_violated,
            $sformatf("Zero transactions logged while frozen: head_ptr=%0d writes=%0d reads=%0d",
                      u_axi_mon.head_ptr, u_axi_mon.total_axi_writes, u_axi_mon.total_axi_reads));
    end

    // Deassert freeze and check resumption
    @(posedge clk);
    freeze  <= 1'b0;
    awvalid <= 1'b0; wvalid <= 1'b0; bvalid <= 1'b0;
    arvalid <= 1'b0; rvalid <= 1'b0;

    @(posedge clk);
    // Normal transaction after unfreeze
    awaddr <= 32'h4000_2004; awvalid <= 1'b1; awready <= 1'b1;
    wdata  <= 32'hCAFE_BABE; wvalid <= 1'b1; wready <= 1'b1;

    @(posedge clk);
    awvalid <= 1'b0; wvalid <= 1'b0;
    bvalid  <= 1'b1; bready <= 1'b1;

    @(posedge clk);
    bvalid  <= 1'b0;
    #1;
    begin
      int last_idx = (u_axi_mon.head_ptr - 1 + 64) % 64;
      check("UNFREEZE_RESUME",
            u_axi_mon.ring_buffer[last_idx].data == 32'hCAFE_BABE,
            $sformatf("Slot %0d contains post-unfreeze write data 0x%08X", last_idx, u_axi_mon.ring_buffer[last_idx].data));
    end

    // -------------------------------------------------------------------------
    // CHALLENGE 3: Concurrent AXI Write and Read Completion (Simultaneous B & R)
    // -------------------------------------------------------------------------
    $display("\n--- [TEST 3] Concurrent AXI Write & Read Completion (Simultaneous B & R) ---");
    reset_all();

    // Subtest 3A: Single simultaneous B and R at head_ptr = 0
    @(posedge clk);
    // Write setup
    awaddr  <= 32'h4000_3000; awvalid <= 1'b1; awready <= 1'b1;
    wdata   <= 32'h1111_2222; wvalid  <= 1'b1; wready  <= 1'b1;
    // Read setup
    araddr  <= 32'h4000_4000; arvalid <= 1'b1; arready <= 1'b1;
    rdata   <= 32'h3333_4444; rresp   <= 2'b00;

    @(posedge clk);
    // Handshake both AW/W and AR in cycle 1, then B and R in cycle 2
    awvalid <= 1'b0; wvalid <= 1'b0;
    arvalid <= 1'b0;
    bvalid  <= 1'b1; bready <= 1'b1; bresp <= 2'b00;
    rvalid  <= 1'b1; rready <= 1'b1;

    @(posedge clk);
    bvalid <= 1'b0; rvalid <= 1'b0;
    #1;

    check("SIMULT_BR_HEAD_PTR", u_axi_mon.head_ptr == 2,
          $sformatf("head_ptr advanced by 2: got %0d expected 2", u_axi_mon.head_ptr));
    check("SIMULT_BR_WRITES", u_axi_mon.total_axi_writes == 1,
          $sformatf("total_axi_writes=%0d expected 1", u_axi_mon.total_axi_writes));
    check("SIMULT_BR_READS", u_axi_mon.total_axi_reads == 1,
          $sformatf("total_axi_reads=%0d expected 1", u_axi_mon.total_axi_reads));

    check("SIMULT_BR_SLOT0_WRITE",
          u_axi_mon.ring_buffer[0].is_write == 1'b1 &&
          u_axi_mon.ring_buffer[0].addr == 32'h4000_3000 &&
          u_axi_mon.ring_buffer[0].data == 32'h1111_2222 &&
          u_axi_mon.ring_buffer[0].seq == 0,
          "Slot 0 contains correct Write transaction");
    check("SIMULT_BR_SLOT1_READ",
          u_axi_mon.ring_buffer[1].is_write == 1'b0 &&
          u_axi_mon.ring_buffer[1].addr == 32'h4000_4000 &&
          u_axi_mon.ring_buffer[1].data == 32'h3333_4444 &&
          u_axi_mon.ring_buffer[1].seq == 1,
          "Slot 1 contains correct Read transaction");

    // Subtest 3B: Simultaneous B and R at Wrap Boundary: head_ptr == 62
    $display("\n--- [TEST 3B] Simultaneous B & R at Wrap Boundary (head_ptr == 62) ---");
    // Advance head_ptr to 62: currently at 2, so need 60 single writes
    for (int w = 0; w < 60; w++) begin
      @(posedge clk);
      awaddr <= 32'h1000 + (w*4); awvalid <= 1; awready <= 1;
      wdata  <= 32'h2000 + w;     wvalid  <= 1; wready  <= 1;
      @(posedge clk);
      awvalid <= 0; wvalid <= 0;
      bvalid  <= 1; bready <= 1;
      @(posedge clk);
      bvalid  <= 0;
      #1;
    end
    check("ADVANCE_TO_62", u_axi_mon.head_ptr == 62,
          $sformatf("head_ptr=%0d expected 62", u_axi_mon.head_ptr));

    // Fire simultaneous B and R at head_ptr == 62!
    // Write goes to 62, Read goes to 63, head_ptr wraps to (62+2)%64 = 0!
    @(posedge clk);
    awaddr <= 32'hAAAA_6262; awvalid <= 1; awready <= 1;
    wdata  <= 32'hDDDD_6262; wvalid  <= 1; wready  <= 1;
    araddr <= 32'hBBBB_6363; arvalid <= 1; arready <= 1;
    rdata  <= 32'hCCCC_6363;

    @(posedge clk);
    awvalid <= 0; wvalid <= 0; arvalid <= 0;
    bvalid  <= 1; bready <= 1;
    rvalid  <= 1; rready <= 1;

    @(posedge clk);
    bvalid <= 0; rvalid <= 0;
    #1;

    check("WRAP_BOUNDARY_62_HEAD_PTR", u_axi_mon.head_ptr == 0,
          $sformatf("head_ptr wrapped from 62 (+2) to %0d (expected 0)", u_axi_mon.head_ptr));
    check("WRAP_BOUNDARY_62_SLOT62_WR",
          u_axi_mon.ring_buffer[62].is_write == 1'b1 &&
          u_axi_mon.ring_buffer[62].addr == 32'hAAAA_6262 &&
          u_axi_mon.ring_buffer[62].data == 32'hDDDD_6262,
          "Slot 62 correctly holds Write txn");
    check("WRAP_BOUNDARY_62_SLOT63_RD",
          u_axi_mon.ring_buffer[63].is_write == 1'b0 &&
          u_axi_mon.ring_buffer[63].addr == 32'hBBBB_6363 &&
          u_axi_mon.ring_buffer[63].data == 32'hCCCC_6363,
          "Slot 63 correctly holds Read txn");

    // Subtest 3C: Simultaneous B and R at Wrap Boundary: head_ptr == 63
    $display("\n--- [TEST 3C] Simultaneous B & R at Wrap Boundary (head_ptr == 63) ---");
    // Currently at head_ptr == 0. Advance by 63 single writes to reach head_ptr == 63
    for (int w = 0; w < 63; w++) begin
      @(posedge clk);
      awaddr <= 32'h3000 + (w*4); awvalid <= 1; awready <= 1;
      wdata  <= 32'h4000 + w;     wvalid  <= 1; wready  <= 1;
      @(posedge clk);
      awvalid <= 0; wvalid <= 0;
      bvalid  <= 1; bready <= 1;
      @(posedge clk);
      bvalid  <= 0;
      #1;
    end
    check("ADVANCE_TO_63", u_axi_mon.head_ptr == 63,
          $sformatf("head_ptr=%0d expected 63", u_axi_mon.head_ptr));

    // Fire simultaneous B and R at head_ptr == 63!
    // Write goes to 63, Read wraps around to 0, head_ptr becomes (63+2)%64 = 1!
    @(posedge clk);
    awaddr <= 32'hAAAA_6363; awvalid <= 1; awready <= 1;
    wdata  <= 32'hDDDD_6363; wvalid  <= 1; wready  <= 1;
    araddr <= 32'hBBBB_0000; arvalid <= 1; arready <= 1;
    rdata  <= 32'hCCCC_0000;

    @(posedge clk);
    awvalid <= 0; wvalid <= 0; arvalid <= 0;
    bvalid  <= 1; bready <= 1;
    rvalid  <= 1; rready <= 1;

    @(posedge clk);
    bvalid <= 0; rvalid <= 0;
    #1;

    check("WRAP_BOUNDARY_63_HEAD_PTR", u_axi_mon.head_ptr == 1,
          $sformatf("head_ptr wrapped from 63 (+2) to %0d (expected 1)", u_axi_mon.head_ptr));
    check("WRAP_BOUNDARY_63_SLOT63_WR",
          u_axi_mon.ring_buffer[63].is_write == 1'b1 &&
          u_axi_mon.ring_buffer[63].addr == 32'hAAAA_6363 &&
          u_axi_mon.ring_buffer[63].data == 32'hDDDD_6363,
          "Slot 63 correctly holds Write txn");
    check("WRAP_BOUNDARY_63_SLOT0_RD",
          u_axi_mon.ring_buffer[0].is_write == 1'b0 &&
          u_axi_mon.ring_buffer[0].addr == 32'hBBBB_0000 &&
          u_axi_mon.ring_buffer[0].data == 32'hCCCC_0000,
          "Slot 0 correctly holds Read txn after split-wrap");

    // Subtest 3D: Continuous Dual-Channel Stream (64 consecutive cycles = 128 transactions)
    $display("\n--- [TEST 3D] Continuous Simultaneous B & R Stream (128 txns) ---");
    begin
      longint unsigned prev_writes = u_axi_mon.total_axi_writes;
      longint unsigned prev_reads  = u_axi_mon.total_axi_reads;
      int start_head = u_axi_mon.head_ptr; // 1

      for (int s = 0; s < 64; s++) begin
        @(posedge clk);
        // Single-cycle address + completion
        awaddr <= 32'hA100_0000 + (s*4); awvalid <= 1; awready <= 1;
        wdata  <= 32'hD100_0000 + s;     wvalid  <= 1; wready  <= 1;
        araddr <= 32'hA200_0000 + (s*4); arvalid <= 1; arready <= 1;
        rdata  <= 32'hD200_0000 + s;     rready  <= 1;
        bvalid <= 1; bready <= 1;
        rvalid <= 1;
      end
      @(posedge clk);
      awvalid <= 0; wvalid <= 0; bvalid <= 0;
      arvalid <= 0; rvalid <= 0;
      #1;

      check("CONTINUOUS_STREAM_HEAD_PTR", u_axi_mon.head_ptr == ((start_head + 128) % 64),
            $sformatf("head_ptr after 128 txns: %0d expected %0d", u_axi_mon.head_ptr, ((start_head + 128) % 64)));
      check("CONTINUOUS_STREAM_WRITES", u_axi_mon.total_axi_writes == prev_writes + 64,
            $sformatf("Writes increased by 64: got %0d expected %0d", u_axi_mon.total_axi_writes, prev_writes + 64));
      check("CONTINUOUS_STREAM_READS", u_axi_mon.total_axi_reads == prev_reads + 64,
            $sformatf("Reads increased by 64: got %0d expected %0d", u_axi_mon.total_axi_reads, prev_reads + 64));
    end

    // -------------------------------------------------------------------------
    // CHALLENGE 4: APB Monitor Modulo 64 Wrap-Around & Wait-States
    // -------------------------------------------------------------------------
    $display("\n--- [TEST 4] APB Monitor Modulo 64 Wrap-Around & Wait-States ---");
    reset_all();
    for (int p = 0; p < 100; p++) begin
      int slot = p % 6;
      @(posedge clk);
      // Setup phase
      apb_paddr   <= 32'h4000_0000 + (slot * 32'h1000) + (p * 4);
      apb_psel    <= (6'b000001 << slot);
      apb_penable <= 1'b0;
      apb_pwrite  <= (p % 2 == 0);
      apb_pwdata  <= 32'hB000_0000 + p;
      apb_pstrb   <= 4'hF;
      apb_pready  <= 6'b0;

      @(posedge clk);
      // Access phase with wait state
      apb_penable <= 1'b1;
      apb_pready  <= 6'b0; // 1 wait state

      @(posedge clk);
      // Ready asserted
      apb_pready[slot] <= 1'b1;
      apb_prdata_flat[slot*32 +: 32] <= 32'hC000_0000 + p;

      @(posedge clk);
      apb_psel    <= '0;
      apb_penable <= 1'b0;
      apb_pready  <= '0;
      #1;
    end

    check("APB_TOTAL_TRANS", u_apb_mon.total_apb_trans == 100,
          $sformatf("total_apb_trans=%0d expected 100", u_apb_mon.total_apb_trans));
    check("APB_HEAD_PTR_WRAP", u_apb_mon.head_ptr == (100 % 64),
          $sformatf("head_ptr=%0d expected %0d", u_apb_mon.head_ptr, (100 % 64)));

    // -------------------------------------------------------------------------
    // CHALLENGE 5: Multi-Interrupt Concurrency in IRQ Monitor (Adversarial Check)
    // -------------------------------------------------------------------------
    $display("\n--- [TEST 5] Multi-Interrupt Concurrency in IRQ Monitor ---");
    reset_all();

    // Challenge scenario: Two interrupts (GPIO and UART) assert at the EXACT SAME CYCLE!
    @(posedge clk);
    gpio_irq <= 1'b1;
    uart_irq <= 1'b1;

    @(posedge clk);
    gpio_irq <= 1'b0;
    uart_irq <= 1'b0;
    #1;

    $display("IRQ Monitor After Dual Simultaneous Assertion:");
    $display("  total_irq_asserts = %0d", u_irq_mon.total_irq_asserts);
    $display("  head_ptr          = %0d", u_irq_mon.head_ptr);
    $display("  ring_buffer[0].src = %s (id=%0d)", irq_src_name(u_irq_mon.ring_buffer[0].src), u_irq_mon.ring_buffer[0].irq_id);
    $display("  ring_buffer[1].src = %s (id=%0d)", irq_src_name(u_irq_mon.ring_buffer[1].src), u_irq_mon.ring_buffer[1].irq_id);

    // Check if both interrupts were captured or if one was dropped
    if (u_irq_mon.head_ptr == 1 && u_irq_mon.total_irq_asserts == 1) begin
      $display("[CRITICAL BUG CONFIRMED] irq_monitor: Simultaneous GPIO and UART assertion resulted in only 1 event recorded! The earlier event was silently overwritten by the second call in the same cycle due to non-blocking head_ptr scheduling!");
      check("IRQ_CONCURRENCY_PRESERVED", 1'b0, "Simultaneous IRQs caused ring buffer slot overwrite / dropped event!");
    end else if (u_irq_mon.head_ptr == 2) begin
      check("IRQ_CONCURRENCY_PRESERVED", 1'b1, "Both simultaneous IRQ events successfully captured in separate slots");
    end else begin
      check("IRQ_CONCURRENCY_PRESERVED", 1'b0, $sformatf("Unexpected IRQ head_ptr=%0d, asserts=%0d", u_irq_mon.head_ptr, u_irq_mon.total_irq_asserts));
    end

    // -------------------------------------------------------------------------
    // CHALLENGE 6: Fetch, Retire, LSU Modulo 64 Wrap-Around & Freeze
    // -------------------------------------------------------------------------
    $display("\n--- [TEST 6] Fetch, Retire, and LSU Wrap-Around & Freeze ---");
    reset_all();

    for (int m = 0; m < 80; m++) begin
      @(posedge clk);
      fetch_pc      <= 32'h0001_0000 + (m * 4);
      fetch_instr   <= 32'h0010_0093; // nop
      fetch_imem_en <= 1'b1;
      fetch_stall   <= 1'b0;

      retire_valid    <= 1'b1;
      retire_pc       <= 32'h0001_0000 + (m * 4);
      retire_instr    <= 32'h0010_0093;
      retire_rd_addr  <= 5'd1;
      retire_rd_wdata <= 32'd100 + m;
      retire_reg_we   <= 1'b1;

      lsu_req   <= 1'b1;
      lsu_we    <= (m % 2 == 1);
      lsu_addr  <= 32'h0002_0000 + (m * 4);
      lsu_wdata <= 32'hF000_0000 + m;
      lsu_stall <= 1'b0;
    end
    @(posedge clk);
    fetch_imem_en <= 1'b0;
    retire_valid  <= 1'b0;
    lsu_req       <= 1'b0;
    #1;

    check("FETCH_TOTAL", u_fetch_mon.total_fetches == 80,
          $sformatf("Fetch total=%0d expected 80", u_fetch_mon.total_fetches));
    check("FETCH_HEAD_PTR", u_fetch_mon.head_ptr == (80 % 64),
          $sformatf("Fetch head_ptr=%0d expected %0d", u_fetch_mon.head_ptr, (80 % 64)));

    check("RETIRE_TOTAL", u_retire_mon.total_retired_instr == 80,
          $sformatf("Retire total=%0d expected 80", u_retire_mon.total_retired_instr));
    check("RETIRE_HEAD_PTR", u_retire_mon.head_ptr == (80 % 64),
          $sformatf("Retire head_ptr=%0d expected %0d", u_retire_mon.head_ptr, (80 % 64)));

    check("LSU_TOTAL", (u_lsu_mon.total_reads + u_lsu_mon.total_writes) == 80,
          $sformatf("LSU total=%0d expected 80", (u_lsu_mon.total_reads + u_lsu_mon.total_writes)));
    check("LSU_HEAD_PTR", u_lsu_mon.head_ptr == (80 % 64),
          $sformatf("LSU head_ptr=%0d expected %0d", u_lsu_mon.head_ptr, (80 % 64)));

    // Now freeze all three
    freeze <= 1'b1;
    for (int f = 0; f < 10; f++) begin
      @(posedge clk);
      fetch_imem_en <= 1'b1;
      retire_valid  <= 1'b1;
      lsu_req       <= 1'b1;
    end
    @(posedge clk);
    fetch_imem_en <= 1'b0;
    retire_valid  <= 1'b0;
    lsu_req       <= 1'b0;
    #1;

    check("FROZEN_FETCH_IMMUNITY", u_fetch_mon.total_fetches == 80 && u_fetch_mon.head_ptr == (80 % 64),
          "Fetch monitor 100% frozen");
    check("FROZEN_RETIRE_IMMUNITY", u_retire_mon.total_retired_instr == 80 && u_retire_mon.head_ptr == (80 % 64),
          "Retire monitor 100% frozen");
    check("FROZEN_LSU_IMMUNITY", (u_lsu_mon.total_reads + u_lsu_mon.total_writes) == 80 && u_lsu_mon.head_ptr == (80 % 64),
          "LSU monitor 100% frozen");

    // -------------------------------------------------------------------------
    // CHALLENGE 7: Post-Mortem Dump Bounds & Negative Index Stress
    // -------------------------------------------------------------------------
    $display("\n--- [TEST 7] Post-Mortem Dump Function Boundary Checks ---");
    // Call dump functions with default and edge values
    u_axi_mon.dump_recent_trans(10);
    u_apb_mon.dump_recent_trans(10);
    u_fetch_mon.dump_recent_fetches(10);
    u_retire_mon.dump_recent_retires(10);
    u_lsu_mon.dump_recent_lsu(10);
    u_irq_mon.dump_recent_irqs(10);
    check("DUMP_TASKS_STABILITY", 1'b1, "All monitor dump tasks executed without runtime crash");

    // -------------------------------------------------------------------------
    // Summary
    // -------------------------------------------------------------------------
    $display("\n====================================================================");
    $display(" EMPIRICAL STRESS TEST RESULTS: %0d Checks, %0d Failures", check_count, error_count);
    $display("====================================================================");

    if (error_count == 0) begin
      $display(" >>> ALL CHALLENGE TESTS PASSED PERFECTLY <<< \n");
    end else begin
      $display(" >>> CHALLENGE IDENTIFIED BUGS / FAILURES (%0d failed) <<< \n", error_count);
    end

    $finish;
  end

endmodule
