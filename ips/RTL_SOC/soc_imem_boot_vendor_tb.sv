// =============================================================================
// RISCFORGE 1TOPS — SoC Instruction-Memory Boot Test with Vendor SPI Flash
// =============================================================================
//
// Same end-to-end scope as soc_imem_boot_tb.sv (cold boot with SPI fetch,
// warm boot with SRAM retention, reset-sequence assertions), but the
// stimulus source is the Infineon S25FS512S vendor behavioral model
// (spi_slave_infinion/S25fs512s/model/s25fs512s.sv) instead of the
// hand-written spi_flash_bfm.
//
// Differences from the BFM version:
//   * Vendor model has a 300 us power-up delay (tdevice_PU = 300e6 ps).
//     FLASH_POWERUP_CYCLES is set to 30_000 (matches the bootloader's
//     default) so the boot FSM waits long enough before touching the SPI
//     master.
//   * Memory is preloaded via a hierarchical call to
//     u_flash.memory_features_i0.write_mem_w(byte_addr, byte_data). The
//     call is issued after the model's own initial InitMemory block has
//     finished (waited via a #1ns settle), and well before the boot FSM
//     leaves S_FLASH_WAIT.
//   * WPNeg and RESETNeg are tied HIGH (write-protect deasserted, chip
//     not held in reset).
//   * SI / SO are inout on the vendor model. The SoC drives sdo0 on IO0
//     and samples sdi1 on IO1 (per spi_master_rx.sv line 84), so:
//       u_flash.SI  ← spi_sdo0_o    (MOSI from master)
//       u_flash.SO  → spi_sdi1_i    (MISO to master, IO1)
//
// Same golden image and same set of assertions as the BFM tb, so a pass
// here proves the boot path works against real vendor timing.
// =============================================================================
`timescale 1ns/1ps

module soc_imem_boot_vendor_tb;

  import gpio_reg_pkg::GPIOCount;

  // ─── Test configuration ───────────────────────────────────────────────
  localparam int unsigned NUM_INSTR_WORDS = 8;
  localparam int unsigned NUM_DATA_WORDS  = 0;

  // Vendor model tPU = 300 us. At 100 MHz (10 ns), that's 30_000 cycles.
  localparam int unsigned FLASH_POWERUP_CYCLES = 30_000;

  // Cold boot budget: 2048 clear + 30_000 flash wait + 8 * ~700 SPI cycles.
  localparam int unsigned BOOT_TIMEOUT_CYCLES = 80_000;

  localparam time CLK_PERIOD = 10ns;

  // ─── Golden instruction image (RV32I ADDI) ────────────────────────────
  logic [31:0] golden_instr [0:NUM_INSTR_WORDS-1];
  initial begin
    golden_instr[0] = 32'h00100093;
    golden_instr[1] = 32'h00200113;
    golden_instr[2] = 32'h00300193;
    golden_instr[3] = 32'h00400213;
    golden_instr[4] = 32'h00500293;
    golden_instr[5] = 32'h00600313;
    golden_instr[6] = 32'h00700393;
    golden_instr[7] = 32'h00800413;
  end

  // ─── Clock & Reset ────────────────────────────────────────────────────
  logic clk;
  logic hard_rst_ni;
  logic soft_rst_ni;
  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // ─── SoC external interface signals ───────────────────────────────────
  logic boot_done;

  logic i2c_scl_i, i2c_scl_o, i2c_scl_oen_o;
  logic i2c_sda_i, i2c_sda_o, i2c_sda_oen_o;
  logic i2c_interrupt_o;

  logic [3:0] timer_irq;

  logic uart_sin_i, uart_sout_o, uart_int_o;
  logic uart_out1n_o, uart_out2n_o, uart_rtsn_o, uart_dtrn_o;
  logic uart_ctsn_i, uart_dsrn_i, uart_dcdn_i, uart_rin_i;

  localparam int unsigned NR_GPIOS = GPIOCount;
  logic [NR_GPIOS-1:0] gpio_in_i, gpio_out_o, gpio_tx_en_o, gpio_in_sync_o;
  logic gpio_global_interrupt_o;
  logic [NR_GPIOS-1:0] gpio_pin_level_interrupts_o;

  logic spi_clk_o;
  logic spi_csn0_o, spi_csn1_o, spi_csn2_o, spi_csn3_o;
  logic [1:0] spi_mode_o;
  logic spi_sdo0_o, spi_sdo1_o, spi_sdo2_o, spi_sdo3_o;
  logic spi_sdi0_i, spi_sdi1_i, spi_sdi2_i, spi_sdi3_i;
  logic [1:0] spi_events_o;

  logic [255:0] clic_intr_src_i;
  logic         clic_irq_valid_o;
  logic [7:0]   clic_irq_id_o;
  logic [7:0]   clic_irq_level_o;
  logic         clic_irq_shv_o;
  logic [1:0]   clic_irq_priv_o;
  logic         clic_irq_kill_req_o;

  // ─── Tie-offs ─────────────────────────────────────────────────────────
  initial begin
    i2c_scl_i       = 1'b1;
    i2c_sda_i       = 1'b1;
    uart_sin_i      = 1'b1;
    uart_ctsn_i     = 1'b1;
    uart_dsrn_i     = 1'b1;
    uart_dcdn_i     = 1'b1;
    uart_rin_i      = 1'b1;
    gpio_in_i       = '0;
    clic_intr_src_i = '0;
    spi_sdi0_i      = 1'b0;    // IO0 sampling not used by std-SPI reads
    spi_sdi2_i      = 1'b0;
    spi_sdi3_i      = 1'b0;
  end

  // ─── Vendor SPI flash model (Infineon S25FS512S) ──────────────────────
  // SI / SO are inout. In standard SPI mode:
  //   * The SoC drives sdo0 (MOSI) → connect to SI.
  //   * The flash drives SO → connect to sdi1 (MISO; the master samples IO1
  //     in std mode, per spi_master_rx.sv line 84).
  // Route sdo0/sdi1 through explicit wires so the vendor inout net sees a
  // proper driver / sampler with no direction ambiguity.
  wire flash_si;
  wire flash_so;
  wire flash_wpn;
  wire flash_resetn;

  assign flash_si    = spi_sdo0_o;   // MOSI from master
  assign spi_sdi1_i  = flash_so;     // MISO into master (IO1)
  assign flash_wpn   = 1'b1;         // Write protect deasserted
  assign flash_resetn= 1'b1;         // Chip not held in reset

  s25fs512s u_flash (
    .SI       ( flash_si     ),
    .SO       ( flash_so     ),
    .SCK      ( spi_clk_o    ),
    .CSNeg    ( spi_csn0_o   ),
    .WPNeg    ( flash_wpn    ),
    .RESETNeg ( flash_resetn )
  );

  // ─── DUT: riscforge_soc_subsystem ─────────────────────────────────────
  riscforge_soc_subsystem #(
    .CLIC_N_SOURCE        ( 256                  ),
    .CLIC_INTCTLBITS      ( 8                    ),
    .TIMER_CNT            ( 2                    ),
    .SPI_BUFFER_DEPTH     ( 10                   ),
    .NUM_INSTR_WORDS      ( NUM_INSTR_WORDS      ),
    .NUM_DATA_WORDS       ( NUM_DATA_WORDS       ),
    .FLASH_POWERUP_CYCLES ( FLASH_POWERUP_CYCLES )
  ) dut (
    .clk_i                    ( clk              ),
    .hard_rst_ni              ( hard_rst_ni       ),
    .soft_rst_ni              ( soft_rst_ni       ),
    .test_mode_i              ( 1'b0              ),

    .fetch_enable_i           ( 1'b0              ),
    .boot_addr_i              ( 32'h0000_0000     ),

    .boot_done_o              ( boot_done         ),

    .i2c_scl_i                ( i2c_scl_i         ),
    .i2c_scl_o                ( i2c_scl_o         ),
    .i2c_scl_oen_o            ( i2c_scl_oen_o     ),
    .i2c_sda_i                ( i2c_sda_i         ),
    .i2c_sda_o                ( i2c_sda_o         ),
    .i2c_sda_oen_o            ( i2c_sda_oen_o     ),
    .i2c_interrupt_o          ( i2c_interrupt_o    ),

    .timer_irq_o              ( timer_irq          ),

    .uart_sin_i               ( uart_sin_i         ),
    .uart_sout_o              ( uart_sout_o        ),
    .uart_int_o               ( uart_int_o         ),
    .uart_out1n_o             ( uart_out1n_o       ),
    .uart_out2n_o             ( uart_out2n_o       ),
    .uart_rtsn_o              ( uart_rtsn_o        ),
    .uart_dtrn_o              ( uart_dtrn_o        ),
    .uart_ctsn_i              ( uart_ctsn_i        ),
    .uart_dsrn_i              ( uart_dsrn_i        ),
    .uart_dcdn_i              ( uart_dcdn_i        ),
    .uart_rin_i               ( uart_rin_i         ),

    .gpio_in_i                ( gpio_in_i          ),
    .gpio_out_o               ( gpio_out_o         ),
    .gpio_tx_en_o             ( gpio_tx_en_o       ),
    .gpio_in_sync_o           ( gpio_in_sync_o     ),
    .gpio_global_interrupt_o  ( gpio_global_interrupt_o ),
    .gpio_pin_level_interrupts_o ( gpio_pin_level_interrupts_o ),

    .spi_clk_o                ( spi_clk_o          ),
    .spi_csn0_o               ( spi_csn0_o         ),
    .spi_csn1_o               ( spi_csn1_o         ),
    .spi_csn2_o               ( spi_csn2_o         ),
    .spi_csn3_o               ( spi_csn3_o         ),
    .spi_mode_o               ( spi_mode_o         ),
    .spi_sdo0_o               ( spi_sdo0_o         ),
    .spi_sdo1_o               ( spi_sdo1_o         ),
    .spi_sdo2_o               ( spi_sdo2_o         ),
    .spi_sdo3_o               ( spi_sdo3_o         ),
    .spi_sdi0_i               ( spi_sdi0_i         ),
    .spi_sdi1_i               ( spi_sdi1_i         ),
    .spi_sdi2_i               ( spi_sdi2_i         ),
    .spi_sdi3_i               ( spi_sdi3_i         ),
    .spi_events_o             ( spi_events_o       ),

    .clic_intr_src_i          ( clic_intr_src_i    ),
    .clic_irq_valid_o         ( clic_irq_valid_o   ),
    .clic_irq_id_o            ( clic_irq_id_o      ),
    .clic_irq_level_o         ( clic_irq_level_o   ),
    .clic_irq_shv_o           ( clic_irq_shv_o     ),
    .clic_irq_priv_o          ( clic_irq_priv_o    ),
    .clic_irq_kill_req_o      ( clic_irq_kill_req_o)
  );

  // ─── Cycle counter ────────────────────────────────────────────────────
  longint unsigned cyc_cnt;
  always_ff @(posedge clk) cyc_cnt <= cyc_cnt + 1;

  // ─── Bootloader FSM state monitor ─────────────────────────────────────
  always @(dut.i_bootloader.state_q) begin
    $display("[TB] @%0t (cycle %0d) Bootloader FSM -> %s",
             $time, cyc_cnt, dut.i_bootloader.state_q.name());
  end

  // ─── Heartbeat ────────────────────────────────────────────────────────
  always @(posedge clk) begin
    if (cyc_cnt > 0 && cyc_cnt % 10000 == 0 && !boot_done) begin
      $display("[TB] Heartbeat @cycle %0d: state=%s clear_cnt=%0d word_cnt=%0d",
               cyc_cnt,
               dut.i_bootloader.state_q.name(),
               dut.i_bootloader.clear_cnt_q,
               dut.i_bootloader.word_cnt_q);
    end
  end

  // ─── Reset-signal observation (hierarchical) ──────────────────────────
  wire core_rst_n_obs   = dut.core_rst_n;
  wire periph_rst_n_obs = dut.periph_rst_n;
  wire spi_rst_n_obs    = dut.spi_rst_n;

  int unsigned cold_spi_release_cyc;
  int unsigned cold_core_release_cyc;
  int unsigned cold_periph_release_cyc;
  bit          cold_saw_spi_activity;
  bit          warm_saw_spi_activity;
  bit          scoring_cold;
  bit          scoring_warm;

  always @(posedge clk) begin
    if (scoring_cold) begin
      if (spi_rst_n_obs    === 1'b1 && cold_spi_release_cyc    == 0) cold_spi_release_cyc    = cyc_cnt;
      if (core_rst_n_obs   === 1'b1 && cold_core_release_cyc   == 0) cold_core_release_cyc   = cyc_cnt;
      if (periph_rst_n_obs === 1'b1 && cold_periph_release_cyc == 0) cold_periph_release_cyc = cyc_cnt;
    end
  end

  always @(negedge spi_csn0_o) begin
    if (scoring_cold) cold_saw_spi_activity = 1'b1;
    if (scoring_warm) warm_saw_spi_activity = 1'b1;
  end

  // ─── Flash preload task ───────────────────────────────────────────────
  // Vendor model is byte-addressed. Same little-endian-in-flash layout the
  // BFM uses: byte 0 = LSB of the RISC-V word, byte 3 = MSB. Combined with
  // the bootloader's byte-swap on RX FIFO capture, this produces the
  // correct 32-bit instruction in SRAM.
  task automatic flash_preload_word(input int unsigned word_addr, input logic [31:0] data);
    int byte_base;
    byte_base = word_addr * 4;
    u_flash.memory_features_i0.write_mem_w(byte_base + 0, int'(data[ 7: 0]));
    u_flash.memory_features_i0.write_mem_w(byte_base + 1, int'(data[15: 8]));
    u_flash.memory_features_i0.write_mem_w(byte_base + 2, int'(data[23:16]));
    u_flash.memory_features_i0.write_mem_w(byte_base + 3, int'(data[31:24]));
  endtask

  task automatic flash_overwrite_poison(input int unsigned n_words, input logic [31:0] pattern);
    for (int i = 0; i < n_words; i++) flash_preload_word(i, pattern);
  endtask

  // ─── Bookkeeping ──────────────────────────────────────────────────────
  int unsigned pass_cnt;
  int unsigned fail_cnt;

  task automatic check(input string label, input bit cond);
    if (cond) begin
      $display("[TB]   PASS: %s", label);
      pass_cnt++;
    end else begin
      $error  ("[TB]   FAIL: %s", label);
      fail_cnt++;
    end
  endtask

  // ─── Main sequence ────────────────────────────────────────────────────
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    cold_spi_release_cyc    = 0;
    cold_core_release_cyc   = 0;
    cold_periph_release_cyc = 0;
    cold_saw_spi_activity   = 1'b0;
    warm_saw_spi_activity   = 1'b0;
    scoring_cold            = 1'b0;
    scoring_warm            = 1'b0;

    // Let the vendor model's InitMemory initial run first, then backdoor
    // the golden image in. This happens well before FLASH_POWERUP_CYCLES
    // has elapsed, so the boot FSM will find valid data when it starts
    // reading.
    #1ns;
    for (int i = 0; i < NUM_INSTR_WORDS; i++) begin
      flash_preload_word(i, golden_instr[i]);
    end
    $display("[TB] Preloaded %0d instruction words into S25FS512S vendor flash",
             NUM_INSTR_WORDS);

    `ifdef XCELIUM
      $shm_open("soc_imem_boot_vendor_tb.shm");
      $shm_probe(soc_imem_boot_vendor_tb, "ASMC");
    `else
      `ifdef VCS
        $vcdpluson;
      `else
        $dumpfile("soc_imem_boot_vendor_tb.vcd");
        $dumpvars(0, soc_imem_boot_vendor_tb);
      `endif
    `endif

    // ══════════════════════════════════════════════════════════════════
    //  TEST 1 — COLD BOOT
    // ══════════════════════════════════════════════════════════════════
    hard_rst_ni = 1'b0;
    soft_rst_ni = 1'b1;
    repeat (10) @(posedge clk);

    $display("[TB] ============================================================");
    $display("[TB]  RISCFORGE SoC + S25FS512S vendor flash — Boot Testbench");
    $display("[TB] ============================================================");
    $display("[TB]  TEST 1: COLD BOOT (real vendor flash timing, tPU=300us)");
    $display("[TB] ============================================================");

    check("cold: core_rst_n LOW during hard reset",   core_rst_n_obs   === 1'b0);
    check("cold: periph_rst_n LOW during hard reset", periph_rst_n_obs === 1'b0);
    check("cold: spi_rst_n LOW during hard reset",    spi_rst_n_obs    === 1'b0);

    $display("[TB] Releasing hard_rst_ni (cold boot) @cycle %0d", cyc_cnt);
    scoring_cold = 1'b1;
    hard_rst_ni  = 1'b1;

    begin : cold_wait
      longint unsigned wcnt;
      wcnt = 0;
      while (!boot_done && wcnt < BOOT_TIMEOUT_CYCLES) begin
        @(posedge clk);
        wcnt++;
      end
      if (!boot_done) begin
        $error("[TB] TIMEOUT: boot_done not asserted after %0d cycles!",
               BOOT_TIMEOUT_CYCLES);
        $error("[TB]  stuck in state=%s clear_cnt=%0d word_cnt=%0d",
               dut.i_bootloader.state_q.name(),
               dut.i_bootloader.clear_cnt_q,
               dut.i_bootloader.word_cnt_q);
        $finish;
      end
    end

    scoring_cold = 1'b0;
    $display("[TB] Cold boot completed at cycle %0d", cyc_cnt);
    repeat (10) @(posedge clk);

    // Verify ISRAM
    $display("[TB] ------------------------------------------------------------");
    $display("[TB]  Verifying ISRAM contents");
    $display("[TB] ------------------------------------------------------------");
    for (int i = 0; i < NUM_INSTR_WORDS; i++) begin
      logic [31:0] actual;
      actual = dut.i_isram.u_imem.mem_array[i];
      if (actual === golden_instr[i]) begin
        $display("[TB]   ISRAM[%0d] = 0x%08h  MATCH", i, actual);
        pass_cnt++;
      end else begin
        $error("[TB]   ISRAM[%0d] = 0x%08h  MISMATCH (expected 0x%08h)",
               i, actual, golden_instr[i]);
        fail_cnt++;
      end
    end

    // Verify cleared spot
    $display("[TB] ------------------------------------------------------------");
    $display("[TB]  Verifying ISRAM cleared locations");
    $display("[TB] ------------------------------------------------------------");
    for (int i = NUM_INSTR_WORDS; i < NUM_INSTR_WORDS + 4; i++) begin
      logic [31:0] actual;
      actual = dut.i_isram.u_imem.mem_array[i];
      if (actual === 32'h0000_0000) begin
        $display("[TB]   ISRAM[%0d] = 0x%08h  CLEARED OK", i, actual);
        pass_cnt++;
      end else begin
        $error("[TB]   ISRAM[%0d] = 0x%08h  NOT CLEARED", i, actual);
        fail_cnt++;
      end
    end

    // Cold-boot reset sequence
    $display("[TB] ------------------------------------------------------------");
    $display("[TB]  Cold-boot reset sequence");
    $display("[TB] ------------------------------------------------------------");
    check("cold: spi_rst_n released during boot",
          cold_spi_release_cyc != 0);
    check("cold: core_rst_n released by end of boot",
          cold_core_release_cyc != 0);
    check("cold: periph_rst_n released by end of boot",
          cold_periph_release_cyc != 0);
    check("cold: spi_rst_n released BEFORE core_rst_n",
          cold_spi_release_cyc != 0 && cold_core_release_cyc != 0 &&
          cold_spi_release_cyc < cold_core_release_cyc);
    check("cold: core & periph released together",
          cold_core_release_cyc == cold_periph_release_cyc);
    check("cold: SPI activity occurred during cold boot",
          cold_saw_spi_activity === 1'b1);
    check("cold: all three resets HIGH at boot_done",
          core_rst_n_obs === 1'b1 && periph_rst_n_obs === 1'b1 && spi_rst_n_obs === 1'b1);
    check("cold: FSM parked in S_DONE",
          dut.i_bootloader.state_q.name() == "S_DONE");
    $display("[TB]   (spi rel @cyc %0d, core rel @cyc %0d, periph rel @cyc %0d)",
             cold_spi_release_cyc, cold_core_release_cyc, cold_periph_release_cyc);

    // ══════════════════════════════════════════════════════════════════
    //  TEST 2 — WARM BOOT (retain SRAM, skip SPI fetch)
    // ══════════════════════════════════════════════════════════════════
    $display("[TB] ============================================================");
    $display("[TB]  TEST 2: WARM BOOT (soft_rst_ni pulse)");
    $display("[TB] ============================================================");

    // Poison the flash so any spurious SPI read during warm boot would
    // corrupt SRAM and be immediately visible.
    flash_overwrite_poison(NUM_INSTR_WORDS, 32'hDEAD_BEEF);
    $display("[TB] Vendor flash overwritten with 0xDEADBEEF poison pattern");

    begin
      logic [31:0] pre_warm [0:NUM_INSTR_WORDS-1];
      for (int i = 0; i < NUM_INSTR_WORDS; i++)
        pre_warm[i] = dut.i_isram.u_imem.mem_array[i];

      warm_saw_spi_activity = 1'b0;
      scoring_warm          = 1'b1;
      soft_rst_ni           = 1'b0;
      repeat (5) @(posedge clk);
      soft_rst_ni           = 1'b1;
      $display("[TB] Released soft_rst_ni @cycle %0d — awaiting warm boot_done", cyc_cnt);

      begin : warm_wait
        int wcnt;
        wcnt = 0;
        @(posedge clk); // let boot_done drop
        while (!boot_done && wcnt < 200) begin
          @(posedge clk);
          wcnt++;
        end
        $display("[TB] warm boot loop exited after %0d cycles (boot_done=%b)",
                 wcnt, boot_done);
      end
      scoring_warm = 1'b0;
      repeat (10) @(posedge clk); // settling

      check("warm: boot_done reasserted", boot_done === 1'b1);
      check("warm: no SPI activity during warm boot",
            warm_saw_spi_activity === 1'b0);
      check("warm: warm_boot_q flag set",
            dut.i_bootloader.warm_boot_q === 1'b1);
      check("warm: FSM parked in S_DONE",
            dut.i_bootloader.state_q.name() == "S_DONE");
      check("warm: all three resets HIGH after warm boot",
            core_rst_n_obs === 1'b1 && periph_rst_n_obs === 1'b1 && spi_rst_n_obs === 1'b1);

      $display("[TB] ------------------------------------------------------------");
      $display("[TB]  Warm-boot SRAM retention");
      $display("[TB] ------------------------------------------------------------");
      for (int i = 0; i < NUM_INSTR_WORDS; i++) begin
        logic [31:0] actual;
        actual = dut.i_isram.u_imem.mem_array[i];
        if (actual === pre_warm[i] && actual === golden_instr[i]) begin
          $display("[TB]   ISRAM[%0d] = 0x%08h  RETAINED", i, actual);
          pass_cnt++;
        end else begin
          $error("[TB]   ISRAM[%0d] = 0x%08h  CORRUPTED (pre=0x%08h golden=0x%08h)",
                 i, actual, pre_warm[i], golden_instr[i]);
          fail_cnt++;
        end
      end
    end

    // Summary
    $display("[TB] ============================================================");
    if (fail_cnt == 0)
      $display("[TB]  *** ALL %0d CHECKS PASSED ***", pass_cnt);
    else
      $display("[TB]  *** %0d PASSED, %0d FAILED ***", pass_cnt, fail_cnt);
    $display("[TB] ============================================================");

    repeat (10) @(posedge clk);
    $finish;
  end

  // ─── Global timeout ───────────────────────────────────────────────────
  // 5 ms is enough: 300 us power-up + boot + margin.
  initial begin
    #5ms;
    $error("[TB] GLOBAL TIMEOUT — simulation exceeded 5ms");
    $finish;
  end

endmodule : soc_imem_boot_vendor_tb
