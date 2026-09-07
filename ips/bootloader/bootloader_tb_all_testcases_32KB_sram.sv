// =============================================================================
// bootloader_tb_all_testcases_32KB_sram.sv
//
// 32 KB SRAM variant of bootloader_tb_all_testcases.sv, targeting the chunked
// SPI burst bootloader.
//
// Differences from the original testbench:
//   - ISRAM / DSRAM sized to 8192 words each (32 KB + 32 KB), matching
//     riscforge_soc_subsystem.sv:454-455 rather than the original 512/2048.
//   - MAX_CHUNK_WORDS is passed explicitly so the burst size is visible here.
//   - The SPI protocol monitor understands CHUNKED bursts: one chip-select
//     assertion now carries CMD(8) + ADDR(24) + N*32 data bits, where N is the
//     chunk size, instead of exactly one 32-bit word.
//   - Full cycle accounting: every FSM state is counted, grouped into boot
//     phases, and reported with absolute time.
//   - SPI/AXI overlap analysis, to show how much of the AXI write cost is
//     hidden underneath the SPI shift rather than added to it.
//
// Verifies (same coverage as the original):
//   - Cold boot: full firmware (ebreak_combined.mem) fetch via SPI into
//     ISRAM (instructions) / DSRAM (data), backdoor-checked against golden.
//   - Warm boot: SRAM retention, SPI fetch skipped.
//   - Reset phasing (core/periph/spi resets).
//   - APB passthrough after boot_done.
//   - SPI protocol correctness (opcode / per-chunk address / word data).
//   - Parametric SRAM boundary (ISRAM->DSRAM crossover).
//
// Firmware image: ebreak_combined.mem
//   Instruction image : 1500 bytes = 375  words -> ISRAM
//   Data image        : 4656 bytes = 1164 words -> DSRAM
//   Combined image    : 6156 bytes = 1539 words
//   At MAX_CHUNK_WORDS = 1024 that is 2 SPI bursts: 1024 + 515 words.
//
// Compile order requirement: axi_pkg.sv must be compiled ahead of
// bootloader.sv (bootloader.sv references axi_pkg::prot_t for the AXI-Lite
// AW channel's `prot` field).
//
// NOTE: this file re-declares tb_bus_pkg and axi_lite_mem exactly as the
// original testbench does, so the two testbenches must not be compiled into
// the same simulation snapshot. Use a separate filelist / -top.
// =============================================================================
`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Console-mirroring log macros
// -----------------------------------------------------------------------------
`define TB_INFO(msg_args) \
  begin \
    $display msg_args; \
    if (g_log_fd) $fwrite(g_log_fd, "%s\n", $sformatf msg_args); \
  end

`define TB_ERROR(msg_args) \
  begin \
    if (g_log_fd) $fwrite(g_log_fd, "ERROR: %s\n", $sformatf msg_args); \
    $error msg_args; \
  end

// -----------------------------------------------------------------------------
// Minimal AXI-Lite / APB struct typedefs
// -----------------------------------------------------------------------------
package tb_bus_pkg;

  typedef struct packed {
    logic [31:0] addr;
    logic [2:0]  prot;
  } aw_chan_t;

  typedef struct packed {
    logic [31:0] data;
    logic [3:0]  strb;
  } w_chan_t;

  typedef struct packed {
    logic [1:0] resp;
  } b_chan_t;

  typedef struct packed {
    logic [31:0] addr;
    logic [2:0]  prot;
  } ar_chan_t;

  typedef struct packed {
    logic [31:0] data;
    logic [1:0]  resp;
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
  } axi_lite_req_t;

  typedef struct packed {
    logic     aw_ready;
    logic     w_ready;
    b_chan_t  b;
    logic     b_valid;
    logic     ar_ready;
    r_chan_t  r;
    logic     r_valid;
  } axi_lite_resp_t;

  typedef struct packed {
    logic [31:0] paddr;
    logic [2:0]  pprot;
    logic        psel;
    logic        penable;
    logic        pwrite;
    logic [31:0] pwdata;
    logic [3:0]  pstrb;
  } apb_req_t;

  typedef struct packed {
    logic        pready;
    logic [31:0] prdata;
    logic        pslverr;
  } apb_resp_t;

endpackage : tb_bus_pkg


// -----------------------------------------------------------------------------
// Simple AXI-Lite backing memory
// -----------------------------------------------------------------------------
module axi_lite_mem
  import tb_bus_pkg::*;
#(
  parameter int unsigned MEM_WORDS = 4096
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  axi_lite_req_t  req_i,
  output axi_lite_resp_t resp_o
);

  logic [31:0] mem [MEM_WORDS];

  logic aw_hs, w_hs;
  assign resp_o.aw_ready = req_i.aw_valid;
  assign resp_o.w_ready  = req_i.w_valid;
  assign aw_hs = req_i.aw_valid & resp_o.aw_ready;
  assign w_hs  = req_i.w_valid  & resp_o.w_ready;

  logic b_valid_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      b_valid_q <= 1'b0;
      for (int i=0; i<MEM_WORDS; i++) begin
        mem[i] <= 32'h0;
      end
    end else begin
      if (aw_hs && w_hs) begin
        mem[req_i.aw.addr[$clog2(MEM_WORDS)+1:2]] <= req_i.w.data;
        b_valid_q <= 1'b1;
      end else if (req_i.b_ready) begin
        b_valid_q <= 1'b0;
      end
    end
  end
  assign resp_o.b_valid  = b_valid_q;
  assign resp_o.b.resp   = 2'b00;

  assign resp_o.ar_ready = req_i.ar_valid;
  logic r_valid_q;
  logic [31:0] r_data_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      r_valid_q <= 1'b0;
      r_data_q  <= '0;
    end else begin
      if (req_i.ar_valid && resp_o.ar_ready) begin
        r_data_q  <= mem[req_i.ar.addr[$clog2(MEM_WORDS)+1:2]];
        r_valid_q <= 1'b1;
      end else if (req_i.r_ready) begin
        r_valid_q <= 1'b0;
      end
    end
  end
  assign resp_o.r_valid = r_valid_q;
  assign resp_o.r.data  = r_data_q;
  assign resp_o.r.resp  = 2'b00;

  function automatic logic [31:0] backdoor_read(int unsigned word_idx);
    return mem[word_idx];
  endfunction

endmodule : axi_lite_mem


// -----------------------------------------------------------------------------
// Top-level testbench
// -----------------------------------------------------------------------------
module bootloader_spi_32KB_sram_tb;

  import tb_bus_pkg::*;

  integer g_log_fd;

  localparam int unsigned NUM_INSTR_WORDS_TB = 375;
  localparam int unsigned NUM_DATA_WORDS_TB  = 1164;
  localparam int unsigned TOTAL_WORDS_TB     = NUM_INSTR_WORDS_TB + NUM_DATA_WORDS_TB;
  localparam int unsigned IMAGE_BYTES        = 6156;

  // 32 KB each, matching riscforge_soc_subsystem.sv:454-455
  localparam int unsigned ISRAM_NUM_WORDS_TB = 8192;
  localparam int unsigned DSRAM_NUM_WORDS_TB = 8192;
  localparam int unsigned CLEAR_WORDS_TB     = ISRAM_NUM_WORDS_TB + DSRAM_NUM_WORDS_TB;

  // Words per SPI burst. Ceiling is 2047 (16-bit SPILEN at 32 bits/word).
  localparam int unsigned MAX_CHUNK_WORDS_TB = 1024;
  localparam int unsigned EXP_CHUNKS         =
      (TOTAL_WORDS_TB + MAX_CHUNK_WORDS_TB - 1) / MAX_CHUNK_WORDS_TB;

  localparam logic [31:0] ISRAM_BASE = 32'h0000_0000;
  localparam logic [31:0] DSRAM_BASE = 32'h0001_0000;

  // Backing memory must span DSRAM_BASE + DSRAM size.
  localparam int unsigned AXI_MEM_WORDS = 32768;

  // TB specific parameter for SPI clock division
  localparam logic [7:0] SPI_CLK_DIV_TB = 8'd4;

  localparam time CLK_PERIOD = 10ns;
  localparam real CLK_NS     = 10.0;

  // ---------------------------------------------------------------------
  // Bootloader FSM state encoding (mirrors the enum in bootloader.sv:245-262)
  // ---------------------------------------------------------------------
  localparam int ST_RESET         = 0;
  localparam int ST_CLEAR_SRAM    = 1;
  localparam int ST_FLASH_WAIT    = 2;
  localparam int ST_INIT_CLKDIV   = 3;
  localparam int ST_INIT_SPICMD   = 4;
  localparam int ST_INIT_SPILEN   = 5;
  localparam int ST_INIT_SPIDUM   = 6;
  localparam int ST_CFG_SPIADR    = 7;
  localparam int ST_TRIGGER       = 8;
  localparam int ST_READ_FIFO     = 9;
  localparam int ST_WRITE_SRAM    = 10;
  localparam int ST_CHECK_DONE    = 11;
  localparam int ST_CLEAN_ASSERT  = 12;
  localparam int ST_CLEAN_HOLD    = 13;
  localparam int ST_CLEAN_RELEASE = 14;
  localparam int ST_DONE          = 15;

  string st_name [0:15] = '{
    "S_RESET", "S_CLEAR_SRAM", "S_FLASH_WAIT", "S_INIT_CLKDIV",
    "S_INIT_SPICMD", "S_INIT_SPILEN", "S_INIT_SPIDUM", "S_CFG_SPIADR",
    "S_TRIGGER", "S_READ_FIFO", "S_WRITE_SRAM", "S_CHECK_DONE",
    "S_CLEAN_ASSERT", "S_CLEAN_HOLD", "S_CLEAN_RELEASE", "S_DONE"
  };

  logic clk;
  logic hard_rst_ni;
  logic soft_rst_ni;

  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  axi_lite_req_t  axi_req;
  axi_lite_resp_t axi_resp;

  apb_req_t  apb_slv_req;
  apb_resp_t apb_slv_resp;
  apb_req_t  apb_mst_req;
  apb_resp_t apb_mst_resp;

  logic core_rst_ni, periph_rst_ni, spi_rst_ni;
  logic boot_done;

  wire spi_clk_w;
  wire spi_csn0_w, spi_csn1_w, spi_csn2_w, spi_csn3_w;
  wire [1:0] spi_mode_w;
  wire spi_sdo0_w, spi_sdo1_w, spi_sdo2_w, spi_sdo3_w;
  wire spi_sdi0_w, spi_sdi1_w, spi_sdi2_w, spi_sdi3_w;
  logic [1:0] spi_events;

  wire flash_SI, flash_SO, flash_SCK, flash_CSNeg;
  wire flash_WPNeg, flash_RESETNeg;

  assign flash_SCK      = spi_clk_w;
  assign flash_CSNeg    = spi_csn0_w;
  assign flash_SI       = spi_sdo0_w;

  assign spi_sdi1_w     = flash_SO;
  assign spi_sdi0_w     = 1'b0;
  assign spi_sdi2_w     = 1'b0;
  assign spi_sdi3_w     = 1'b0;

  assign flash_WPNeg    = 1'b1;
  assign flash_RESETNeg = 1'b1;

  // ---------------------------------------------------------------------
  // DUT: bootloader
  // ---------------------------------------------------------------------
  bootloader #(
    .axi_req_t        ( axi_lite_req_t      ),
    .axi_resp_t       ( axi_lite_resp_t     ),
    .apb_req_t        ( apb_req_t           ),
    .apb_resp_t       ( apb_resp_t          ),
    .AXI_ADDR_WIDTH   ( 32                  ),
    .AXI_DATA_WIDTH   ( 32                  ),
    .ISRAM_BASE_ADDR  ( ISRAM_BASE          ),
    .DSRAM_BASE_ADDR  ( DSRAM_BASE          ),
    .ISRAM_NUM_WORDS  ( ISRAM_NUM_WORDS_TB  ),
    .DSRAM_NUM_WORDS  ( DSRAM_NUM_WORDS_TB  ),
    .NUM_INSTR_WORDS  ( NUM_INSTR_WORDS_TB  ),
    .NUM_DATA_WORDS   ( NUM_DATA_WORDS_TB   ),
    .FLASH_START_ADDR ( 24'h00_0000         ),
    .FLASH_READ_CMD   ( 8'h03               ),
    .CMD_LEN_BITS     ( 6'd8                ),
    .ADDR_LEN_BITS    ( 6'd24               ),
    .DATA_LEN_BITS    ( 16'd32              ),
    .MAX_CHUNK_WORDS  ( MAX_CHUNK_WORDS_TB  ),
    .SPI_CLK_DIV      ( SPI_CLK_DIV_TB      ),
    .CS_FLASH         ( 4'b0001             ),
    .RESET_HOLD_CYCLES( 4                   )
  ) dut_bootloader (
    .clk_i           ( clk           ),
    .hard_rst_ni     ( hard_rst_ni   ),
    .soft_rst_ni     ( soft_rst_ni   ),
    .axi_req_o       ( axi_req       ),
    .axi_resp_i      ( axi_resp      ),
    .apb_slv_req_i   ( apb_slv_req   ),
    .apb_slv_resp_o  ( apb_slv_resp  ),
    .apb_mst_req_o   ( apb_mst_req   ),
    .apb_mst_resp_i  ( apb_mst_resp  ),
    .core_rst_ni_o   ( core_rst_ni   ),
    .periph_rst_ni_o ( periph_rst_ni ),
    .spi_rst_ni_o    ( spi_rst_ni    ),
    .boot_done_o     ( boot_done     )
  );

  // ---------------------------------------------------------------------
  // DUT: apb_spi_master
  // ---------------------------------------------------------------------
  apb_spi_master #(
    .BUFFER_DEPTH   ( 10 ),
    .APB_ADDR_WIDTH ( 12 )
  ) dut_apb_spi_master (
    .HCLK      ( clk           ),
    .HRESETn   ( spi_rst_ni    ),
    .PADDR     ( apb_mst_req.paddr[11:0] ),
    .PWDATA    ( apb_mst_req.pwdata      ),
    .PWRITE    ( apb_mst_req.pwrite      ),
    .PSEL      ( apb_mst_req.psel        ),
    .PENABLE   ( apb_mst_req.penable     ),
    .PRDATA    ( apb_mst_resp.prdata     ),
    .PREADY    ( apb_mst_resp.pready     ),
    .PSLVERR   ( apb_mst_resp.pslverr    ),
    .events_o  ( spi_events    ),
    .spi_clk   ( spi_clk_w     ),
    .spi_csn0  ( spi_csn0_w    ),
    .spi_csn1  ( spi_csn1_w    ),
    .spi_csn2  ( spi_csn2_w    ),
    .spi_csn3  ( spi_csn3_w    ),
    .spi_mode  ( spi_mode_w    ),
    .spi_sdo0  ( spi_sdo0_w    ),
    .spi_sdo1  ( spi_sdo1_w    ),
    .spi_sdo2  ( spi_sdo2_w    ),
    .spi_sdo3  ( spi_sdo3_w    ),
    .spi_sdi0  ( spi_sdi0_w    ),
    .spi_sdi1  ( spi_sdi1_w    ),
    .spi_sdi2  ( spi_sdi2_w    ),
    .spi_sdi3  ( spi_sdi3_w    )
  );

  // ---------------------------------------------------------------------
  // DUT: s25fs512s SPI NOR flash model
  // ---------------------------------------------------------------------
  s25fs512s #(
    .UserPreload    ( 0       ),
    .mem_file_name  ( "none"  ),
    .otp_file_name  ( "none"  )
  ) u_flash (
    .SI        ( flash_SI       ),
    .SO        ( flash_SO       ),
    .SCK       ( flash_SCK      ),
    .CSNeg     ( flash_CSNeg    ),
    .WPNeg     ( flash_WPNeg    ),
    .RESETNeg  ( flash_RESETNeg )
  );

  // ---------------------------------------------------------------------
  // AXI-Lite backing memory
  // ---------------------------------------------------------------------
  axi_lite_mem #(
    .MEM_WORDS ( AXI_MEM_WORDS )
  ) u_axi_mem (
    .clk_i  ( clk      ),
    .rst_ni ( hard_rst_ni ),
    .req_i  ( axi_req  ),
    .resp_o ( axi_resp )
  );

  initial apb_slv_req = '0;

  // ---------------------------------------------------------------------
  // Golden firmware image
  // ---------------------------------------------------------------------
  byte unsigned golden_bytes [0:IMAGE_BYTES-1];
  logic [31:0]  golden_words [0:TOTAL_WORDS_TB-1];

  string mem_file_path = "../spi_slave_infinion/S25fs512s/model/ebreak_combined.mem";

  initial begin
    void'($value$plusargs("MEMFILE=%s", mem_file_path));
    `TB_INFO(("[TB] Loading firmware image from: %s", mem_file_path));
    $readmemh(mem_file_path, golden_bytes);
  end

  task automatic build_golden_words();
    int w;
    for (w = 0; w < TOTAL_WORDS_TB; w++) begin
      golden_words[w] = { golden_bytes[w*4+3], golden_bytes[w*4+2],
                          golden_bytes[w*4+1], golden_bytes[w*4+0] };
    end
  endtask

  task automatic preload_flash();
    int i;
    for (i = 0; i < IMAGE_BYTES; i++) begin
      u_flash.memory_features_i0.write_mem_w(i, golden_bytes[i]);
    end
    `TB_INFO(("[TB] Preloaded %0d bytes into flash from ebreak_combined.mem", IMAGE_BYTES));
  endtask

  longint unsigned cyc_cnt;
  always_ff @(posedge clk) cyc_cnt <= cyc_cnt + 1;

  // =====================================================================
  // Cycle accounting
  //
  // Every FSM state is counted while measurement is enabled, then grouped
  // into boot phases. spi_shift / axi_write / overlap are tracked separately
  // so the SPI-vs-AXI concurrency can be quantified rather than assumed.
  // =====================================================================
  bit              meas_en;
  longint unsigned state_cycles [0:15];
  longint unsigned spi_shift_cycles;   // chip-select asserted (burst in flight)
  longint unsigned axi_write_cycles;   // FSM parked in S_WRITE_SRAM
  longint unsigned overlap_cycles;     // both of the above at once

  task automatic meas_clear();
    int i;
    for (i = 0; i < 16; i++) state_cycles[i] = 0;
    spi_shift_cycles = 0;
    axi_write_cycles = 0;
    overlap_cycles   = 0;
  endtask

  // The $isunknown guard matters: measurement is armed just before the reset is
  // driven, and state_q is X until the first async reset lands. Indexing the
  // array with an X state would be an out-of-bounds access.
  always_ff @(posedge clk) begin
    if (meas_en && !$isunknown(dut_bootloader.state_q)) begin
      state_cycles[int'(dut_bootloader.state_q)] <= state_cycles[int'(dut_bootloader.state_q)] + 1;
      if (!flash_CSNeg)                                spi_shift_cycles <= spi_shift_cycles + 1;
      if (dut_bootloader.state_q == ST_WRITE_SRAM)     axi_write_cycles <= axi_write_cycles + 1;
      if (!flash_CSNeg && dut_bootloader.state_q == ST_WRITE_SRAM)
                                                       overlap_cycles   <= overlap_cycles + 1;
    end
  end

  function automatic real cyc_to_us(longint unsigned c);
    return (real'(c) * CLK_NS) / 1000.0;
  endfunction

  function automatic real pct_of(longint unsigned part, longint unsigned whole);
    return (whole == 0) ? 0.0 : (100.0 * real'(part)) / real'(whole);
  endfunction

  task automatic report_boot_profile(string tc_id, longint unsigned total_cyc);
    longint unsigned ph_clear, ph_flash, ph_cfg, ph_burst, ph_fetch, ph_clean, ph_reset;
    longint unsigned axi_tail;
    int i;

    ph_reset = state_cycles[ST_RESET];
    ph_clear = state_cycles[ST_CLEAR_SRAM];
    ph_flash = state_cycles[ST_FLASH_WAIT];
    ph_cfg   = state_cycles[ST_INIT_CLKDIV] + state_cycles[ST_INIT_SPICMD]
             + state_cycles[ST_INIT_SPIDUM];
    ph_burst = state_cycles[ST_INIT_SPILEN] + state_cycles[ST_CFG_SPIADR]
             + state_cycles[ST_TRIGGER];
    ph_fetch = state_cycles[ST_READ_FIFO]  + state_cycles[ST_WRITE_SRAM]
             + state_cycles[ST_CHECK_DONE];
    ph_clean = state_cycles[ST_CLEAN_ASSERT] + state_cycles[ST_CLEAN_HOLD]
             + state_cycles[ST_CLEAN_RELEASE];

    // AXI work that was NOT hidden underneath an in-flight SPI burst.
    axi_tail = axi_write_cycles - overlap_cycles;

    `TB_INFO(("\n---------------- [%s] BOOT PHASE PROFILE ----------------", tc_id));
    `TB_INFO(("  Config      : ISRAM=%0d words  DSRAM=%0d words  clear=%0d words",
              ISRAM_NUM_WORDS_TB, DSRAM_NUM_WORDS_TB, CLEAR_WORDS_TB));
    `TB_INFO(("  Firmware    : %0d words (%0d instr + %0d data), %0d bytes",
              TOTAL_WORDS_TB, NUM_INSTR_WORDS_TB, NUM_DATA_WORDS_TB, IMAGE_BYTES));
    `TB_INFO(("  Burst       : MAX_CHUNK_WORDS=%0d  -> %0d SPI burst(s)",
              MAX_CHUNK_WORDS_TB, EXP_CHUNKS));
    `TB_INFO(("  Clock       : %0.1f ns  (SPI_CLK_DIV=%0d)", CLK_NS, SPI_CLK_DIV_TB));

    `TB_INFO(("\n  %-22s %12s %12s %8s", "PHASE", "CYCLES", "TIME(us)", "%"));
    `TB_INFO(("  %-22s %12s %12s %8s", "----------------------",
              "------------", "------------", "--------"));
    `TB_INFO(("  %-22s %12d %12.2f %7.2f%%", "S_RESET entry",  ph_reset,
              cyc_to_us(ph_reset), pct_of(ph_reset, total_cyc)));
    `TB_INFO(("  %-22s %12d %12.2f %7.2f%%", "SRAM clear",     ph_clear,
              cyc_to_us(ph_clear), pct_of(ph_clear, total_cyc)));
    `TB_INFO(("  %-22s %12d %12.2f %7.2f%%", "Flash power-up", ph_flash,
              cyc_to_us(ph_flash), pct_of(ph_flash, total_cyc)));
    `TB_INFO(("  %-22s %12d %12.2f %7.2f%%", "SPI config (once)", ph_cfg,
              cyc_to_us(ph_cfg), pct_of(ph_cfg, total_cyc)));
    `TB_INFO(("  %-22s %12d %12.2f %7.2f%%", "Burst setup (/chunk)", ph_burst,
              cyc_to_us(ph_burst), pct_of(ph_burst, total_cyc)));
    `TB_INFO(("  %-22s %12d %12.2f %7.2f%%", "Fetch drain (/word)", ph_fetch,
              cyc_to_us(ph_fetch), pct_of(ph_fetch, total_cyc)));
    `TB_INFO(("  %-22s %12d %12.2f %7.2f%%", "Clean-slate reset", ph_clean,
              cyc_to_us(ph_clean), pct_of(ph_clean, total_cyc)));
    `TB_INFO(("  %-22s %12s %12s %8s", "----------------------",
              "------------", "------------", "--------"));
    `TB_INFO(("  %-22s %12d %12.2f %7.2f%%", "TOTAL BOOT", total_cyc,
              cyc_to_us(total_cyc), 100.0));

    `TB_INFO(("\n  Per-state breakdown:"));
    for (i = 0; i < 16; i++) begin
      if (state_cycles[i] != 0)
        `TB_INFO(("    %-18s %12d  (%6.2f%%)", st_name[i], state_cycles[i],
                  pct_of(state_cycles[i], total_cyc)));
    end

    // -----------------------------------------------------------------
    // SPI vs AXI concurrency.
    //
    // The SPI master shifts a burst autonomously and pushes a word into its
    // RX FIFO every 32 bits, gating SCK itself if the FIFO backs up
    // (spi_master_rx.sv:94-102). So the AXI writes run underneath the shift
    // rather than after it, and only the trailing writes -- those issued once
    // the last burst has already ended -- add to the critical path.
    // -----------------------------------------------------------------
    `TB_INFO(("\n  SPI / AXI concurrency:"));
    `TB_INFO(("    SPI burst in flight (CSN low) : %0d cycles (%0.2f us, %0.2f%% of boot)",
              spi_shift_cycles, cyc_to_us(spi_shift_cycles),
              pct_of(spi_shift_cycles, total_cyc)));
    `TB_INFO(("    AXI write (S_WRITE_SRAM)      : %0d cycles (%0.2f us)",
              axi_write_cycles, cyc_to_us(axi_write_cycles)));
    `TB_INFO(("    ... overlapped with SPI       : %0d cycles (%0.2f%% of AXI, hidden)",
              overlap_cycles, pct_of(overlap_cycles, axi_write_cycles)));
    `TB_INFO(("    ... NOT overlapped (tail)     : %0d cycles (%0.2f us, %0.2f%% of boot)",
              axi_tail, cyc_to_us(axi_tail), pct_of(axi_tail, total_cyc)));
    if (TOTAL_WORDS_TB != 0)
      `TB_INFO(("    Cost per firmware word        : %0.1f cycles (fetch phase / word)",
                real'(ph_fetch) / real'(TOTAL_WORDS_TB)));
    `TB_INFO(("--------------------------------------------------------\n"));
  endtask

  // ---------------------------------------------------------------------
  // Reset tasks
  // ---------------------------------------------------------------------
  task automatic do_cold_boot();
    @(negedge clk);
    hard_rst_ni = 1'b0;
    soft_rst_ni = 1'b1;
    repeat (5) @(posedge clk);
    @(negedge clk);
    hard_rst_ni = 1'b1;
    `TB_INFO(("[TB] Cold boot: hard_rst_ni released @cycle %0d", cyc_cnt));

    // TC4: Synchronous reset check during active boot
    @(posedge clk);
    if (core_rst_ni !== 1'b0)
        `TB_ERROR(("[TC4] core_rst_ni not held LOW during boot"));
    if (periph_rst_ni !== 1'b0)
        `TB_ERROR(("[TC4] periph_rst_ni not held LOW during boot"));
  endtask

  task automatic do_warm_boot();
    @(negedge clk);
    soft_rst_ni = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk);
    soft_rst_ni = 1'b1;
    `TB_INFO(("[TB] Warm boot: soft_rst_ni released @cycle %0d", cyc_cnt));

    // TC4: Synchronous reset check during active boot
    @(posedge clk);
    if (core_rst_ni !== 1'b0)
        `TB_ERROR(("[TC4] core_rst_ni not held LOW during boot"));
    if (periph_rst_ni !== 1'b0)
        `TB_ERROR(("[TC4] periph_rst_ni not held LOW during boot"));
  endtask

  task automatic wait_boot_done(longint unsigned max_cycles);
    longint unsigned start_c = cyc_cnt;
    while (!boot_done && (cyc_cnt - start_c) < max_cycles) @(posedge clk);
    if (!boot_done)
      `TB_ERROR(("[TB] TIMEOUT waiting for boot_done_o (waited %0d cycles)", max_cycles));
  endtask

  function automatic int unsigned addr_to_word_idx(logic [31:0] addr);
    return addr[$clog2(AXI_MEM_WORDS)+1:2];
  endfunction

  task automatic check_sram_contents(string tc_id);
    int w;
    int unsigned isram_idx, dsram_idx;
    logic [31:0] exp, act;
    int errors = 0;

    for (w = 0; w < NUM_INSTR_WORDS_TB; w++) begin
      isram_idx = addr_to_word_idx(ISRAM_BASE + w*4);
      exp = golden_words[w];
      act = u_axi_mem.backdoor_read(isram_idx);
      if (exp !== act) begin
        errors++;
        `TB_ERROR(("[%s] ISRAM word %0d mismatch: exp=%08h act=%08h", tc_id, w, exp, act));
      end
    end

    for (w = 0; w < NUM_DATA_WORDS_TB; w++) begin
      dsram_idx = addr_to_word_idx(DSRAM_BASE + w*4);
      exp = golden_words[NUM_INSTR_WORDS_TB + w];
      act = u_axi_mem.backdoor_read(dsram_idx);
      if (exp !== act) begin
        errors++;
        `TB_ERROR(("[%s] DSRAM word %0d mismatch: exp=%08h act=%08h", tc_id, w, exp, act));
      end
    end

    if (golden_words[NUM_INSTR_WORDS_TB-1] !==
        u_axi_mem.backdoor_read(addr_to_word_idx(ISRAM_BASE + (NUM_INSTR_WORDS_TB-1)*4)))
      `TB_ERROR(("[%s_BOUNDARY] Last ISRAM word mismatch at index %0d", tc_id, NUM_INSTR_WORDS_TB-1));

    if (golden_words[NUM_INSTR_WORDS_TB] !==
        u_axi_mem.backdoor_read(addr_to_word_idx(DSRAM_BASE)))
      `TB_ERROR(("[%s_BOUNDARY] First DSRAM word mismatch at index 0", tc_id));

    if (errors == 0) begin
      `TB_INFO(("[%s] PASS: all %0d words (ISRAM+DSRAM) match golden image", tc_id, TOTAL_WORDS_TB));
    end else begin
      `TB_INFO(("[%s] FAIL: %0d word mismatches found", tc_id, errors));
    end
  endtask

  // ---------------------------------------------------------------------
  // SPI protocol monitor (TC8) -- CHUNK AWARE
  //
  // One chip-select assertion now carries CMD(8) + ADDR(24) + N*32 data bits.
  // The monitor checks the opcode, checks that each burst's start address
  // continues from where the previous burst ended, and checks every 32-bit
  // word as it completes rather than only at chip-select release.
  // ---------------------------------------------------------------------
  localparam int unsigned MON_CMD_BITS  = 8;
  localparam int unsigned MON_ADDR_BITS = 24;
  localparam int unsigned MON_HDR_BITS  = MON_CMD_BITS + MON_ADDR_BITS;

  logic [7:0]  mon_opcode;
  logic [23:0] mon_addr;
  logic [31:0] mon_data;
  int          mon_bitcnt;
  int          mon_word_count;      // words seen across the whole boot
  int          mon_chunk_words;     // words seen in the current burst
  int          mon_chunk_count;     // bursts (chip-select assertions) seen
  bit          mon_txn_active;

  always @(negedge flash_CSNeg) begin
    mon_bitcnt      = 0;
    mon_opcode      = '0;
    mon_addr        = '0;
    mon_data        = '0;
    mon_chunk_words = 0;
    mon_txn_active  = 1'b1;
    mon_chunk_count++;
  end

  always @(posedge flash_CSNeg) begin
    if (mon_txn_active && mon_bitcnt > MON_HDR_BITS) begin
      `TB_INFO(("[TC8] burst %0d complete: %0d words (%0d data bits)",
                mon_chunk_count, mon_chunk_words, mon_bitcnt - MON_HDR_BITS));
      if (((mon_bitcnt - MON_HDR_BITS) % 32) != 0)
        `TB_ERROR(("[TC8] burst %0d ended mid-word: %0d data bits is not a multiple of 32",
                   mon_chunk_count, mon_bitcnt - MON_HDR_BITS));
    end
    mon_txn_active = 1'b0;
  end

  always @(posedge flash_SCK) begin
    int data_idx;
    logic [31:0] swapped;
    if (!flash_CSNeg) begin
      if (mon_bitcnt < MON_CMD_BITS) begin
        mon_opcode = {mon_opcode[6:0], flash_SI};
      end else if (mon_bitcnt < MON_HDR_BITS) begin
        mon_addr = {mon_addr[22:0], flash_SI};
      end else begin
        data_idx = mon_bitcnt - MON_HDR_BITS;
        mon_data = {mon_data[30:0], flash_SO};
        // A word completes on every 32nd data bit, not at chip-select release.
        if ((data_idx % 32) == 31) begin
          swapped = {mon_data[7:0], mon_data[15:8], mon_data[23:16], mon_data[31:24]};
          if (mon_word_count < TOTAL_WORDS_TB) begin
            if (swapped !== golden_words[mon_word_count]) begin
              `TB_ERROR(("[TC8] SPI data mismatch @word %0d: exp=%08h got=%08h (raw=%08h)",
                         mon_word_count, golden_words[mon_word_count], swapped, mon_data));
            end else if (mon_word_count < 5) begin
              `TB_INFO(("[TC8] SPI word %0d data OK (%08h)", mon_word_count, swapped));
            end
          end else begin
            `TB_ERROR(("[TC8] SPI fetched more words than the image holds (word %0d)",
                       mon_word_count));
          end
          mon_word_count++;
          mon_chunk_words++;
        end
      end
      mon_bitcnt++;
      if (mon_bitcnt == MON_HDR_BITS) begin
        if (mon_opcode !== 8'h03)
          `TB_ERROR(("[TC8] Wrong SPI opcode: got %02h, expected 03h", mon_opcode));
        // Each burst must resume exactly where the previous one stopped.
        if (mon_addr !== 24'(mon_word_count * 4))
          `TB_ERROR(("[TC8] burst %0d start address wrong: got %06h expected %06h",
                     mon_chunk_count, mon_addr, 24'(mon_word_count * 4)));
      end
    end
  end

  // ---------------------------------------------------------------------
  // Main test sequence variables
  // ---------------------------------------------------------------------
  longint unsigned t_start_cyc, t_boot_cyc;
  time             t_start_time, t_boot_time;

  longint unsigned run2_start_cyc, run2_cycles;
  longint unsigned run1_cycles;

  initial begin
    g_log_fd = $fopen("bootloader_spi_32KB_sram_tb.log", "w");
    if (!g_log_fd)
      $display("[TB] WARNING: could not open bootloader_spi_32KB_sram_tb.log - console-only logging");

    hard_rst_ni  = 1'b1;
    soft_rst_ni  = 1'b1;

    #1;

    build_golden_words();
    preload_flash();

    // ---------------- TC1: Cold Boot ----------------
    `TB_INFO(("\n===== TC1: Cold Boot (32 KB ISRAM + 32 KB DSRAM) ====="));
    mon_word_count  = 0;
    mon_chunk_count = 0;
    meas_clear();

    t_start_cyc  = cyc_cnt;
    t_start_time = $time;
    meas_en      = 1'b1;

    do_cold_boot();
    wait_boot_done(2000000);

    meas_en     = 1'b0;
    t_boot_cyc  = cyc_cnt;
    t_boot_time = $time;
    run1_cycles = t_boot_cyc - t_start_cyc;

    check_sram_contents("TC1");

    // NOTE: TB_INFO/TB_ERROR expand to begin...end, so the trailing ';' becomes
    // a null statement that closes the if. Every if/else around them therefore
    // needs explicit begin/end.
    if (mon_chunk_count != EXP_CHUNKS) begin
      `TB_ERROR(("[TC1] expected %0d SPI burst(s), observed %0d",
                 EXP_CHUNKS, mon_chunk_count));
    end else begin
      `TB_INFO(("[TC1] PASS: %0d SPI burst(s) as expected for %0d words @ %0d words/burst",
                mon_chunk_count, TOTAL_WORDS_TB, MAX_CHUNK_WORDS_TB));
    end

    if (mon_word_count != TOTAL_WORDS_TB)
      `TB_ERROR(("[TC1] fetched %0d words, expected %0d", mon_word_count, TOTAL_WORDS_TB));

    `TB_INFO(("[TC1] Total boot cycles: %0d  (%0t)", run1_cycles, (t_boot_time - t_start_time)));
    report_boot_profile("TC1", run1_cycles);

    // ---------------- TC3: Fixed-time determinism ----------------
    `TB_INFO(("\n===== TC3: Determinism (repeat cold boot) ====="));
    mon_word_count  = 0;
    mon_chunk_count = 0;
    run2_start_cyc  = cyc_cnt;
    do_cold_boot();
    wait_boot_done(2000000);
    check_sram_contents("TC3");
    run2_cycles = cyc_cnt - run2_start_cyc;
    if (run2_cycles !== run1_cycles) begin
      `TB_ERROR(("[TC3] FAIL: boot cycle count not deterministic (run1=%0d run2=%0d)",
             run1_cycles, run2_cycles));
    end else begin
      `TB_INFO(("[TC3] PASS: boot cycle count deterministic (%0d cycles both runs)",
               run1_cycles));
    end

    // ---------------- TC2: Warm Boot ----------------
    `TB_INFO(("\n===== TC2: Warm Boot ====="));
    do_warm_boot();
    wait_boot_done(20);
    check_sram_contents("TC2");
    `TB_INFO(("[TC2] boot_done asserted, SRAM preserved check complete"));

    // ---------------- TC6: APB Passthrough ----------------
    `TB_INFO(("\n===== TC6: APB Passthrough (post boot_done) ====="));
    apb_slv_req.paddr   = 12'h000; // REG_STATUS
    apb_slv_req.psel    = 1'b1;
    apb_slv_req.penable = 1'b0;
    apb_slv_req.pwrite  = 1'b0;
    @(posedge clk);
    apb_slv_req.penable = 1'b1;
    @(posedge clk);
    while (!apb_slv_resp.pready) @(posedge clk);
    `TB_INFO(("[TC6] Passthrough read STATUS = %08h", apb_slv_resp.prdata));
    apb_slv_req = '0;

    `TB_INFO(("\n===== All testcases complete ====="));
    if (g_log_fd) $fclose(g_log_fd);
    $finish;
  end

  // ---------------------------------------------------------------------
  // Timeout watchdog
  // ---------------------------------------------------------------------
  initial begin
    #25ms;
    `TB_ERROR(("[TB] GLOBAL TIMEOUT - simulation did not finish"));
    if (g_log_fd) $fclose(g_log_fd);
    $finish;
  end

  // ---------------------------------------------------------------------
  // Waveform dump
  // ---------------------------------------------------------------------
  initial begin
    $shm_open("bootloader_spi_32KB_sram_tb.shm");

    $shm_probe(bootloader_spi_32KB_sram_tb, "AS");
    $shm_probe(bootloader_spi_32KB_sram_tb.dut_apb_spi_master, "AS");
    $shm_probe(bootloader_spi_32KB_sram_tb.dut_apb_spi_master.u_spictrl, "AS");
    $shm_probe(bootloader_spi_32KB_sram_tb.dut_apb_spi_master.u_axiregs, "AS");
    $shm_probe(bootloader_spi_32KB_sram_tb.dut_apb_spi_master.u_txfifo, "AS");
    $shm_probe(bootloader_spi_32KB_sram_tb.dut_apb_spi_master.u_txfifo, "AM");
    $shm_probe(bootloader_spi_32KB_sram_tb.dut_apb_spi_master.u_rxfifo, "AS");
    $shm_probe(bootloader_spi_32KB_sram_tb.dut_apb_spi_master.u_rxfifo, "AM");
    $shm_probe(bootloader_spi_32KB_sram_tb.dut_bootloader, "AS");
    $shm_probe(bootloader_spi_32KB_sram_tb.u_axi_mem, "AS");
    $shm_probe(bootloader_spi_32KB_sram_tb.u_axi_mem, "AM");
    $shm_probe(bootloader_spi_32KB_sram_tb.u_flash, "AS");
  end

endmodule : bootloader_spi_32KB_sram_tb
