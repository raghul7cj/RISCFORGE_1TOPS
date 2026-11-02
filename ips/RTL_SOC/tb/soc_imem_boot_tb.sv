// =============================================================================
// RISCFORGE 1TOPS — SoC Instruction Memory Boot-Loading Testbench
// =============================================================================
//
// Verifies that the bootloader correctly loads instruction words into the
// Instruction_Memory_new IP through the full SoC data path:
//
//   SPI Flash (behavioral model)
//     ↓  (SPI protocol on spi_sdo0/spi_sdi0/spi_clk/spi_csn0)
//   apb_spi_master (inside SoC)
//     ↓  (APB: bootloader FSM reads RX FIFO)
//   bootloader (AXI-Lite master)
//     ↓  (AXI crossbar SLV[1] → MST[0])
//   axi_lite_sram_if
//     ↓  (req/gnt to sram_mux port 1)
//   sram_mux (arbitrates core port 0 vs AXI port 1)
//     ↓  (SRAM interface)
//   imem_sram_wrapper → Instruction_Memory_new
//
// Test strategy:
//   1. Instantiate full riscforge_soc_subsystem
//   2. Connect a lightweight SPI flash behavioral model on SPI bus
//   3. Apply cold-boot reset sequence
//   4. Wait for boot_done_o
//   5. Verify Instruction_Memory_new internal mem_array via hierarchical ref
//   6. Report per-word match/mismatch and overall pass/fail
//
// =============================================================================
`timescale 1ns/1ps

// =============================================================================
// Lightweight SPI NOR Flash Behavioral Model
// =============================================================================
// Responds to Standard Read (opcode 0x03):
//   Master sends: [8-bit cmd] [24-bit addr] → flash returns [32-bit data]
// Data is stored in an internal memory array, preloaded by the testbench
// via backdoor write (write_word task).
//
// SPI Mode 0: CPOL=0, CPHA=0 — data sampled on rising edge, shifted on falling.
//   - Flash samples SI on rising edge of SCK (receives cmd+addr)
//   - Flash drives SO on falling edge of SCK (sends data back)
//
// This model has no power-up delay (immediate operation).
// =============================================================================

module spi_flash_bfm #(
  parameter int unsigned MEM_WORDS = 256    // 32-bit words
)(
  input  logic  spi_clk,
  input  logic  spi_csn,     // Active low chip select
  input  logic  spi_si,      // Master → Flash (MOSI)
  output logic  spi_so       // Flash → Master (MISO)
);

  // Internal memory array (32-bit words, byte-addressable via SPI)
  logic [7:0] mem [0:MEM_WORDS*4-1];

  // Task for testbench backdoor: load a 32-bit word at word-aligned address
  task automatic write_word(input int unsigned word_addr, input logic [31:0] data);
    // Little-endian-in-flash: byte 0 holds LSB of the RISC-V word.
    // The SPI master shifts each byte MSB-first, and the bootloader byte-swaps
    // the resulting 32-bit RX FIFO word before writing to SRAM. Storing LSB at
    // the lowest byte address produces the correct instruction after that swap.
    mem[word_addr*4 + 0] = data[ 7: 0];
    mem[word_addr*4 + 1] = data[15: 8];
    mem[word_addr*4 + 2] = data[23:16];
    mem[word_addr*4 + 3] = data[31:24];
  endtask

  // SPI protocol state machine
  logic [7:0]  cmd_reg;
  logic [23:0] addr_reg;
  logic [31:0] shift_out_reg;
  int          bit_cnt;

  typedef enum {S_CMD, S_ADDR, S_DATA} flash_state_e;
  flash_state_e fstate;

  // Drive SO (active only when CS is low)
  logic so_bit;
  assign spi_so = spi_csn ? 1'bz : so_bit;

  // Initialize
  initial begin
    so_bit   = 1'b0;
    cmd_reg  = '0;
    addr_reg = '0;
    fstate   = S_CMD;
    bit_cnt  = 0;
    shift_out_reg = '0;
    // Initialize memory to zeros
    for (int i = 0; i < MEM_WORDS*4; i++) mem[i] = 8'h00;
  end

  // Reset state on CS deassertion
  always @(posedge spi_csn) begin
    fstate   = S_CMD;
    bit_cnt  = 0;
    cmd_reg  = '0;
    addr_reg = '0;
    so_bit   = 1'b0;
  end

  // Sample input on rising edge (receive cmd + addr from master)
  always @(posedge spi_clk) begin
    if (!spi_csn) begin
      case (fstate)
        S_CMD: begin
          cmd_reg = {cmd_reg[6:0], spi_si};
          bit_cnt = bit_cnt + 1;
          if (bit_cnt == 8) begin
            bit_cnt = 0;
            if (cmd_reg == 8'h03) begin
              fstate = S_ADDR;
            end else begin
              // Unsupported command — stay idle
              fstate = S_CMD;
              $display("[FLASH BFM] WARNING: Unsupported cmd 0x%02h at time %0t",
                       cmd_reg, $time);
            end
          end
        end

        S_ADDR: begin
          addr_reg = {addr_reg[22:0], spi_si};
          bit_cnt = bit_cnt + 1;
          if (bit_cnt == 24) begin
            bit_cnt = 0;
            fstate = S_DATA;
            // Prepare first data byte from the resolved address
            // SPI NOR flash is byte-addressed; we read 4 consecutive bytes
            shift_out_reg = {mem[addr_reg],
                             mem[addr_reg + 1],
                             mem[addr_reg + 2],
                             mem[addr_reg + 3]};
          end
        end

        S_DATA: begin
          bit_cnt = bit_cnt + 1;
          if (bit_cnt == 32) begin
            // In continuous read mode, flash would auto-increment address.
            // The bootloader issues one 32-bit transaction per word, then
            // deasserts CS, so we don't need to handle auto-increment.
            bit_cnt = 0;
          end
        end
      endcase
    end
  end

  // Shift out data on falling edge of SPI clock
  always @(negedge spi_clk) begin
    if (!spi_csn && fstate == S_DATA) begin
      so_bit = shift_out_reg[31];
      shift_out_reg = {shift_out_reg[30:0], 1'b0};
    end
  end

endmodule : spi_flash_bfm


// =============================================================================
// Top-Level SoC Boot Testbench
// =============================================================================

module soc_imem_boot_tb;

  import gpio_reg_pkg::GPIOCount;

  // ─── Test configuration ───────────────────────────────────────────────
  localparam int unsigned NUM_INSTR_WORDS = 8;
  localparam int unsigned NUM_DATA_WORDS  = 0;

  // Reduce flash power-up wait for faster simulation
  localparam int unsigned FLASH_POWERUP_CYCLES = 10;

  // Boot timeout (generous: SRAM clear + SPI fetch)
  // 2048 clear words × ~2 cyc + 10 flash wait + 8 words × ~300 cyc ≈ 7000 cycles
  localparam int unsigned BOOT_TIMEOUT_CYCLES = 50_000;

  localparam time CLK_PERIOD = 10ns;

  // ─── Golden instruction image (RISC-V RV32I ADDI instructions) ────────
  // These are the expected instructions that should end up in ISRAM
  logic [31:0] golden_instr [0:NUM_INSTR_WORDS-1];

  initial begin
    golden_instr[0] = 32'h00100093;  // ADDI x1,  x0, 1
    golden_instr[1] = 32'h00200113;  // ADDI x2,  x0, 2
    golden_instr[2] = 32'h00300193;  // ADDI x3,  x0, 3
    golden_instr[3] = 32'h00400213;  // ADDI x4,  x0, 4
    golden_instr[4] = 32'h00500293;  // ADDI x5,  x0, 5
    golden_instr[5] = 32'h00600313;  // ADDI x6,  x0, 6
    golden_instr[6] = 32'h00700393;  // ADDI x7,  x0, 7
    golden_instr[7] = 32'h00800413;  // ADDI x8,  x0, 8
  end

  // ─── Clock & Reset ────────────────────────────────────────────────────
  logic clk;
  logic hard_rst_ni;
  logic soft_rst_ni;

  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // ─── SoC external interface signals ───────────────────────────────────
  logic boot_done;

  // I2C (unused — tie off)
  logic i2c_scl_i, i2c_scl_o, i2c_scl_oen_o;
  logic i2c_sda_i, i2c_sda_o, i2c_sda_oen_o;
  logic i2c_interrupt_o;

  // Timer
  logic [3:0] timer_irq;

  // UART (unused — tie off)
  logic uart_sin_i, uart_sout_o, uart_int_o;
  logic uart_out1n_o, uart_out2n_o, uart_rtsn_o, uart_dtrn_o;
  logic uart_ctsn_i, uart_dsrn_i, uart_dcdn_i, uart_rin_i;

  // GPIO (unused — tie off)
  localparam int unsigned NR_GPIOS = GPIOCount;
  logic [NR_GPIOS-1:0] gpio_in_i, gpio_out_o, gpio_tx_en_o, gpio_in_sync_o;
  logic gpio_global_interrupt_o;
  logic [NR_GPIOS-1:0] gpio_pin_level_interrupts_o;

  // SPI (directly connected to flash BFM)
  logic spi_clk_o;
  logic spi_csn0_o, spi_csn1_o, spi_csn2_o, spi_csn3_o;
  logic [1:0] spi_mode_o;
  logic spi_sdo0_o, spi_sdo1_o, spi_sdo2_o, spi_sdo3_o;
  logic spi_sdi0_i, spi_sdi1_i, spi_sdi2_i, spi_sdi3_i;
  logic [1:0] spi_events_o;

  // CLIC (unused — tie off)
  logic [255:0] clic_intr_src_i;
  logic         clic_irq_valid_o;
  logic [7:0]   clic_irq_id_o;
  logic [7:0]   clic_irq_level_o;
  logic         clic_irq_shv_o;
  logic [1:0]   clic_irq_priv_o;
  logic         clic_irq_kill_req_o;

  // ─── Tie-off unused inputs ────────────────────────────────────────────
  initial begin
    i2c_scl_i      = 1'b1;
    i2c_sda_i      = 1'b1;
    uart_sin_i     = 1'b1;
    uart_ctsn_i    = 1'b1;
    uart_dsrn_i    = 1'b1;
    uart_dcdn_i    = 1'b1;
    uart_rin_i     = 1'b1;
    gpio_in_i      = '0;
    clic_intr_src_i = '0;
    spi_sdi0_i     = 1'b0;    // Unused in std SPI (MISO is on IO1); driven only if enabled
    spi_sdi2_i     = 1'b0;
    spi_sdi3_i     = 1'b0;
  end

  // ─── SPI Flash BFM ────────────────────────────────────────────────────
  spi_flash_bfm #(
    .MEM_WORDS ( 256 )   // 256 × 4 = 1 KB flash
  ) u_spi_flash (
    .spi_clk ( spi_clk_o   ),
    .spi_csn ( spi_csn0_o  ),
    .spi_si  ( spi_sdo0_o  ),    // Master IO0 (SDO0 = MOSI in std SPI) → Flash SI
    .spi_so  ( spi_sdi1_i  )     // Flash SO → Master IO1 (SDI1 = MISO in std SPI, per spi_master_rx.sv)
  );

  // ─── DUT: riscforge_soc_subsystem ─────────────────────────────────────
  riscforge_soc_subsystem #(
    .CLIC_N_SOURCE        ( 256                  ),
    .CLIC_INTCTLBITS      ( 8                    ),
    .TIMER_CNT            ( 2                    ),
    .SPI_BUFFER_DEPTH     ( 10                   ),
    .NUM_INSTR_WORDS      ( NUM_INSTR_WORDS      ),
    .NUM_DATA_WORDS       ( NUM_DATA_WORDS        ),
    .FLASH_POWERUP_CYCLES ( FLASH_POWERUP_CYCLES )
  ) dut (
    .clk_i                    ( clk              ),
    .hard_rst_ni              ( hard_rst_ni       ),
    .soft_rst_ni              ( soft_rst_ni       ),
    .test_mode_i              ( 1'b0              ),

    .fetch_enable_i           ( 1'b0              ),  // Core stays idle
    .boot_addr_i              ( 32'h0000_0000     ),

    .boot_done_o              ( boot_done         ),

    // I2C
    .i2c_scl_i                ( i2c_scl_i         ),
    .i2c_scl_o                ( i2c_scl_o         ),
    .i2c_scl_oen_o            ( i2c_scl_oen_o     ),
    .i2c_sda_i                ( i2c_sda_i         ),
    .i2c_sda_o                ( i2c_sda_o         ),
    .i2c_sda_oen_o            ( i2c_sda_oen_o     ),
    .i2c_interrupt_o          ( i2c_interrupt_o    ),

    // Timer
    .timer_irq_o              ( timer_irq          ),

    // UART
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

    // GPIO
    .gpio_in_i                ( gpio_in_i          ),
    .gpio_out_o               ( gpio_out_o         ),
    .gpio_tx_en_o             ( gpio_tx_en_o       ),
    .gpio_in_sync_o           ( gpio_in_sync_o     ),
    .gpio_global_interrupt_o  ( gpio_global_interrupt_o  ),
    .gpio_pin_level_interrupts_o ( gpio_pin_level_interrupts_o ),

    // SPI
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

    // CLIC
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

  // ─── Bootloader FSM state monitor (debug aid) ─────────────────────────
  // Prints every FSM state transition to the console
  always @(dut.i_bootloader.state_q) begin
    $display("[TB] @%0t (cycle %0d) Bootloader FSM → %s",
             $time, cyc_cnt, dut.i_bootloader.state_q.name());
  end

  // ─── Heartbeat monitor ────────────────────────────────────────────────
  always @(posedge clk) begin
    if (cyc_cnt > 0 && cyc_cnt % 5000 == 0 && !boot_done) begin
      $display("[TB] Heartbeat @cycle %0d: state=%s clear_cnt=%0d word_cnt=%0d",
               cyc_cnt,
               dut.i_bootloader.state_q.name(),
               dut.i_bootloader.clear_cnt_q,
               dut.i_bootloader.word_cnt_q);
    end
  end

  // ─── Reset output aliases (hierarchical — not on SoC top ports) ───────
  wire core_rst_n_obs   = dut.core_rst_n;
  wire periph_rst_n_obs = dut.periph_rst_n;
  wire spi_rst_n_obs    = dut.spi_rst_n;

  // ─── Reset-sequence event capture ─────────────────────────────────────
  // Latch first-observed transitions so we can score them after boot completes.
  int unsigned cold_spi_release_cyc;    // cycle when spi_rst_n first went HIGH after cold boot
  int unsigned cold_core_release_cyc;   // cycle when core_rst_n first went HIGH after cold boot
  int unsigned cold_periph_release_cyc; // cycle when periph_rst_n first went HIGH after cold boot
  bit          cold_saw_spi_activity;   // any SPI CS0 falling edge during cold boot
  bit          warm_saw_spi_activity;   // any SPI CS0 falling edge during warm boot
  bit          scoring_cold;
  bit          scoring_warm;

  // Detect first LOW→HIGH edge on each reset while the corresponding
  // scoring flag is asserted.
  always @(posedge clk) begin
    if (scoring_cold) begin
      if (spi_rst_n_obs    === 1'b1 && cold_spi_release_cyc    == 0) cold_spi_release_cyc    = cyc_cnt;
      if (core_rst_n_obs   === 1'b1 && cold_core_release_cyc   == 0) cold_core_release_cyc   = cyc_cnt;
      if (periph_rst_n_obs === 1'b1 && cold_periph_release_cyc == 0) cold_periph_release_cyc = cyc_cnt;
    end
  end

  // Detect any SPI chip-select assertion (falling edge on spi_csn0_o) while
  // one of the scoring flags is set.
  always @(negedge spi_csn0_o) begin
    if (scoring_cold) cold_saw_spi_activity = 1'b1;
    if (scoring_warm) warm_saw_spi_activity = 1'b1;
  end

  // ─── Main test sequence ───────────────────────────────────────────────
  int unsigned pass_cnt;
  int unsigned fail_cnt;

  // Tiny helper for pass/fail bookkeeping with uniform log format.
  task automatic check(input string label, input bit cond);
    if (cond) begin
      $display("[TB]   PASS: %s", label);
      pass_cnt++;
    end else begin
      $error  ("[TB]   FAIL: %s", label);
      fail_cnt++;
    end
  endtask

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

    // ── Preload flash BFM with golden instruction image ──
    // The bootloader reads from flash starting at FLASH_START_ADDR = 0x000000.
    // The SPI flash BFM is byte-addressed. We write 32-bit words at consecutive
    // word addresses (0, 1, 2, ...), which map to byte addresses (0, 4, 8, ...).
    for (int i = 0; i < NUM_INSTR_WORDS; i++) begin
      u_spi_flash.write_word(i, golden_instr[i]);
    end
    $display("[TB] Preloaded %0d instruction words into SPI flash BFM", NUM_INSTR_WORDS);

    // ── Waveform dump ──
    `ifdef XCELIUM
      $shm_open("soc_imem_boot_tb.shm");
      $shm_probe(soc_imem_boot_tb, "ASMC");
    `else
      `ifdef VCS
        $vcdpluson;
      `else
        $dumpfile("soc_imem_boot_tb.vcd");
        $dumpvars(0, soc_imem_boot_tb);
      `endif
    `endif

    // ══════════════════════════════════════════════════════════════════
    //  TEST 1 — COLD BOOT: SPI fetch + AXI-lite path + reset sequence
    // ══════════════════════════════════════════════════════════════════
    hard_rst_ni = 1'b0;
    soft_rst_ni = 1'b1;
    repeat (10) @(posedge clk);

    $display("[TB] ═══════════════════════════════════════════════════════");
    $display("[TB]  RISCFORGE SoC — Boot & Reset-Sequence Testbench");
    $display("[TB] ═══════════════════════════════════════════════════════");
    $display("[TB]  TEST 1: COLD BOOT");
    $display("[TB] ═══════════════════════════════════════════════════════");

    // Confirm all three resets are held LOW while hard_rst_ni is asserted.
    check("cold: core_rst_n asserted LOW during hard reset",   core_rst_n_obs   === 1'b0);
    check("cold: periph_rst_n asserted LOW during hard reset", periph_rst_n_obs === 1'b0);
    check("cold: spi_rst_n asserted LOW during hard reset",    spi_rst_n_obs    === 1'b0);

    $display("[TB] Releasing hard_rst_ni (cold boot) @cycle %0d", cyc_cnt);
    scoring_cold = 1'b1;
    hard_rst_ni  = 1'b1;

    // ── Wait for boot completion ──
    begin
      static longint unsigned start_c = cyc_cnt;
      while (!boot_done && (cyc_cnt - start_c) < BOOT_TIMEOUT_CYCLES) begin
        @(posedge clk);
      end
      if (!boot_done) begin
        $error("[TB] TIMEOUT: boot_done_o not asserted after %0d cycles!",
               BOOT_TIMEOUT_CYCLES);
        $error("[TB] Bootloader stuck in state: %s (clear_cnt=%0d, word_cnt=%0d)",
               dut.i_bootloader.state_q.name(),
               dut.i_bootloader.clear_cnt_q,
               dut.i_bootloader.word_cnt_q);
        $finish;
      end
    end

    scoring_cold = 1'b0;
    $display("[TB] ✓ Boot completed at cycle %0d", cyc_cnt);

    // ── Let the system settle for a few clocks after boot_done ──
    repeat (10) @(posedge clk);

    // ── Verify instruction memory contents via hierarchical reference ──
    $display("[TB] ───────────────────────────────────────────────────────");
    $display("[TB]  Verifying ISRAM contents (Instruction_Memory_new)");
    $display("[TB] ───────────────────────────────────────────────────────");

    for (int i = 0; i < NUM_INSTR_WORDS; i++) begin
      logic [31:0] actual;
      // Hierarchical path to Instruction_Memory_new's internal memory array:
      //   dut.i_isram (imem_sram_wrapper)
      //     .u_imem (Instruction_Memory_new)
      //       .mem_array[i]
      actual = dut.i_isram.u_imem.mem_array[i];

      if (actual === golden_instr[i]) begin
        $display("[TB]   ISRAM[%0d] = 0x%08h — MATCH", i, actual);
        pass_cnt++;
      end else begin
        $error("[TB]   ISRAM[%0d] = 0x%08h — MISMATCH (expected 0x%08h)",
               i, actual, golden_instr[i]);
        fail_cnt++;
      end
    end

    // ── Also verify that non-loaded locations are zero (SRAM was cleared) ──
    $display("[TB] ───────────────────────────────────────────────────────");
    $display("[TB]  Verifying ISRAM cleared locations (spot check)");
    $display("[TB] ───────────────────────────────────────────────────────");

    for (int i = NUM_INSTR_WORDS; i < NUM_INSTR_WORDS + 4; i++) begin
      logic [31:0] actual;
      actual = dut.i_isram.u_imem.mem_array[i];
      if (actual === 32'h0000_0000) begin
        $display("[TB]   ISRAM[%0d] = 0x%08h — CLEARED OK", i, actual);
        pass_cnt++;
      end else begin
        $error("[TB]   ISRAM[%0d] = 0x%08h — NOT CLEARED (expected 0x00000000)",
               i, actual);
        fail_cnt++;
      end
    end

    // ── Cold-boot reset-sequence checks ──
    $display("[TB] ───────────────────────────────────────────────────────");
    $display("[TB]  Cold-boot reset sequence");
    $display("[TB] ───────────────────────────────────────────────────────");
    check("cold: spi_rst_n was released HIGH during boot",
          cold_spi_release_cyc != 0);
    check("cold: core_rst_n was released HIGH by end of boot",
          cold_core_release_cyc != 0);
    check("cold: periph_rst_n was released HIGH by end of boot",
          cold_periph_release_cyc != 0);
    check("cold: spi_rst_n released BEFORE core_rst_n (SPI needed for fetch)",
          cold_spi_release_cyc != 0 && cold_core_release_cyc != 0 &&
          cold_spi_release_cyc < cold_core_release_cyc);
    check("cold: core & periph released together (clean-slate pulse)",
          cold_core_release_cyc == cold_periph_release_cyc);
    check("cold: SPI activity occurred during cold boot (CS0 asserted)",
          cold_saw_spi_activity === 1'b1);
    check("cold: all three resets HIGH at boot_done",
          core_rst_n_obs === 1'b1 && periph_rst_n_obs === 1'b1 && spi_rst_n_obs === 1'b1);
    check("cold: FSM parked in S_DONE",
          dut.i_bootloader.state_q.name() == "S_DONE");
    $display("[TB]   (spi release @cyc %0d, core release @cyc %0d, periph release @cyc %0d)",
             cold_spi_release_cyc, cold_core_release_cyc, cold_periph_release_cyc);

    // ══════════════════════════════════════════════════════════════════
    //  TEST 2 — WARM BOOT: skip SPI fetch, retain SRAM, run clean-slate
    // ══════════════════════════════════════════════════════════════════
    $display("[TB] ═══════════════════════════════════════════════════════");
    $display("[TB]  TEST 2: WARM BOOT (soft_rst_ni pulse)");
    $display("[TB] ═══════════════════════════════════════════════════════");

    // Wipe the flash BFM so any accidental SPI read during warm boot would
    // clearly corrupt SRAM — proving the SRAM contents were retained, not
    // reloaded.
    for (int i = 0; i < NUM_INSTR_WORDS; i++) begin
      u_spi_flash.write_word(i, 32'hDEAD_BEEF);
    end
    $display("[TB] Flash BFM overwritten with 0xDEADBEEF as poison pattern");

    // Snapshot SRAM before warm reset for a retention check afterwards.
    begin
      logic [31:0] pre_warm [0:NUM_INSTR_WORDS-1];
      for (int i = 0; i < NUM_INSTR_WORDS; i++)
        pre_warm[i] = dut.i_isram.u_imem.mem_array[i];

      // Pulse soft reset. hard_rst_ni stays HIGH throughout.
      warm_saw_spi_activity = 1'b0;
      scoring_warm          = 1'b1;
      soft_rst_ni           = 1'b0;
      // Must exceed the SoC soft-reset filter (2-FF sync + SoftRstFiltCycles=16).
      repeat (40) @(posedge clk);
      soft_rst_ni           = 1'b1;
      $display("[TB] Released soft_rst_ni @cycle %0d — awaiting warm boot_done", cyc_cnt);

      // Wait for boot_done to reassert. Warm path is short: RESET → CLEAN_ASSERT
      // → CLEAN_HOLD → CLEAN_RELEASE → DONE, so a small budget is enough.
      // NOTE: use non-static so the initializer re-runs on each simulation entry.
      begin : warm_wait
        longint unsigned wstart;
        int              wcnt;
        wstart = cyc_cnt;
        wcnt   = 0;
        // boot_done was HIGH from cold boot; wait one cycle for the async
        // reset to drop it LOW, then wait for it to reassert HIGH.
        @(posedge clk);
        while (!boot_done && wcnt < 200) begin
          @(posedge clk);
          wcnt++;
        end
        $display("[TB] warm boot loop exited after %0d cycles (boot_done=%b)",
                 wcnt, boot_done);
      end
      // Let the reset outputs settle and any transitional X drivers on the
      // SRAM control lines quiesce before sampling mem_array.
      repeat (10) @(posedge clk);
      scoring_warm = 1'b0;

      check("warm: boot_done reasserted after soft reset", boot_done === 1'b1);
      check("warm: no SPI activity during warm boot (SPI fetch skipped)",
            warm_saw_spi_activity === 1'b0);
      check("warm: warm_boot_q flag was set by soft reset",
            dut.i_bootloader.warm_boot_q === 1'b1);
      check("warm: FSM parked in S_DONE",
            dut.i_bootloader.state_q.name() == "S_DONE");
      check("warm: all three resets HIGH after warm boot completes",
            core_rst_n_obs === 1'b1 && periph_rst_n_obs === 1'b1 && spi_rst_n_obs === 1'b1);

      // SRAM retention: warm boot must NOT clear or overwrite the image.
      $display("[TB] ───────────────────────────────────────────────────────");
      $display("[TB]  Warm-boot SRAM retention (must equal pre-warm snapshot)");
      $display("[TB] ───────────────────────────────────────────────────────");
      for (int i = 0; i < NUM_INSTR_WORDS; i++) begin
        logic [31:0] actual;
        actual = dut.i_isram.u_imem.mem_array[i];
        if (actual === pre_warm[i] && actual === golden_instr[i]) begin
          $display("[TB]   ISRAM[%0d] = 0x%08h — RETAINED", i, actual);
          pass_cnt++;
        end else begin
          $error("[TB]   ISRAM[%0d] = 0x%08h — CORRUPTED (pre-warm=0x%08h, golden=0x%08h)",
                 i, actual, pre_warm[i], golden_instr[i]);
          fail_cnt++;
        end
      end
    end

    // ── Summary ──
    $display("[TB] ═══════════════════════════════════════════════════════");
    if (fail_cnt == 0) begin
      $display("[TB]  ✓✓✓ ALL %0d CHECKS PASSED — TEST PASSED ✓✓✓", pass_cnt);
    end else begin
      $display("[TB]  ✗✗✗ %0d PASSED, %0d FAILED — TEST FAILED ✗✗✗",
               pass_cnt, fail_cnt);
    end
    $display("[TB] ═══════════════════════════════════════════════════════");

    repeat (10) @(posedge clk);
    $finish;
  end

  // ─── Global timeout watchdog ──────────────────────────────────────────
  initial begin
    #5ms;
    $error("[TB] GLOBAL TIMEOUT — simulation exceeded 5ms");
    $finish;
  end

  // ─── X/Z propagation checker ──────────────────────────────────────────
  always @(posedge clk) begin
    if (cyc_cnt > 15) begin // Skip initial reset phase
      if ($isunknown(boot_done)) begin
        $warning("[TB] X/Z detected on boot_done_o at time %0t", $time);
      end
    end
  end

endmodule : soc_imem_boot_tb
