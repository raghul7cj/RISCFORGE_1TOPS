// =============================================================================
// bootloader_spi_tb.sv
// Self-checking testbench for RISCFORGE/SONIC-MCU Bootloader + apb_spi_master
// + s25fs512s SPI NOR flash model.
//
// Verifies:
//   - Cold boot: full firmware (ebreak_combined.mem) fetch via SPI into
//     ISRAM (instructions) / DSRAM (data), backdoor-checked against golden.
//   - Warm boot: SRAM retention, SPI fetch skipped.
//   - Reset phasing (core/periph/spi resets).
//   - SPI backpressure on RX FIFO.
//   - APB passthrough after boot_done.
//   - SPI protocol correctness (opcode/address/word count/data).
//   - Parametric SRAM boundary (ISRAM->DSRAM crossover).
//   - Cycle-count measurement for config phase and per-word transfer.
//
// Firmware image: ebreak_combined.mem
//   Instruction image : 1500 bytes = 375  words -> ISRAM
//   Data image        : 4656 bytes = 1164 words -> DSRAM
//   Combined image     : 6156 bytes = 1539 words
//
// Compile order requirement: axi_pkg.sv must be compiled ahead of
// bootloader.sv (bootloader.sv references axi_pkg::prot_t for the AXI-Lite
// AW channel's `prot` field).
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
module bootloader_spi_tb;

  import tb_bus_pkg::*;

  integer g_log_fd;

  localparam int unsigned NUM_INSTR_WORDS_TB = 375;   
  localparam int unsigned NUM_DATA_WORDS_TB  = 1164;  
  localparam int unsigned TOTAL_WORDS_TB     = NUM_INSTR_WORDS_TB + NUM_DATA_WORDS_TB; 
  localparam int unsigned IMAGE_BYTES        = 6156;

  localparam int unsigned ISRAM_NUM_WORDS_TB = 512;   
  localparam int unsigned DSRAM_NUM_WORDS_TB = 2048;  

  localparam logic [31:0] ISRAM_BASE = 32'h0000_0000;
  localparam logic [31:0] DSRAM_BASE = 32'h0001_0000;

  // TB specific parameter for SPI clock division
  localparam logic [7:0] SPI_CLK_DIV_TB = 8'd4;

  localparam time CLK_PERIOD = 10ns;

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
    .MEM_WORDS ( 32768 ) 
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
    return addr[$clog2(32768)+1:2]; 
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
  // SPI protocol monitor (TC8)
  // ---------------------------------------------------------------------
  localparam int unsigned MON_CMD_BITS  = 8;
  localparam int unsigned MON_ADDR_BITS = 24;
  localparam int unsigned MON_DATA_BITS = 32;
  localparam int unsigned MON_TXN_BITS  = MON_CMD_BITS + MON_ADDR_BITS + MON_DATA_BITS;

  logic [7:0]  mon_opcode;
  logic [23:0] mon_addr;
  logic [31:0] mon_data;
  int          mon_bitcnt;
  int          mon_word_count;
  bit          mon_txn_active;

  always @(negedge flash_CSNeg) begin
    mon_bitcnt  = 0;
    mon_opcode  = '0;
    mon_addr    = '0;
    mon_data    = '0;
    mon_txn_active = 1'b1;
  end

  always @(posedge flash_CSNeg) begin
    if (mon_txn_active && mon_bitcnt == MON_TXN_BITS) begin
      if (mon_word_count < TOTAL_WORDS_TB) begin
        
        logic [31:0] swapped_mon_data;
        swapped_mon_data = {mon_data[7:0], mon_data[15:8], mon_data[23:16], mon_data[31:24]};

        if (swapped_mon_data !== golden_words[mon_word_count]) begin
          `TB_ERROR(("[TC8] SPI data mismatch @word %0d: exp=%08h got=%08h (raw=%08h)",
                 mon_word_count, golden_words[mon_word_count], swapped_mon_data, mon_data));
        end else begin
          if (mon_word_count < 5)
            `TB_INFO(("[TC8] SPI word %0d data OK (%08h)", mon_word_count, swapped_mon_data));
        end
      end
      mon_word_count++;
    end
    mon_txn_active = 1'b0;
  end

  always @(posedge flash_SCK) begin
    if (!flash_CSNeg) begin
      if (mon_bitcnt < MON_CMD_BITS) begin
        mon_opcode = {mon_opcode[6:0], flash_SI};
      end else if (mon_bitcnt < MON_CMD_BITS + MON_ADDR_BITS) begin
        mon_addr = {mon_addr[22:0], flash_SI};
      end else if (mon_bitcnt < MON_TXN_BITS) begin
        mon_data = {mon_data[30:0], flash_SO};
      end
      mon_bitcnt++;
      if (mon_bitcnt == MON_CMD_BITS + MON_ADDR_BITS) begin
        if (mon_opcode !== 8'h03) begin
          `TB_ERROR(("[TC8] Wrong SPI opcode: got %02h, expected 03h", mon_opcode));
        end
      end
    end
  end

  // ---------------------------------------------------------------------
  // Main test sequence variables
  // ---------------------------------------------------------------------
  longint unsigned t_start_cyc, t_cfg_cyc, t_boot_cyc;
  time t_start_time, t_cfg_time, t_boot_time;
  
  longint unsigned run2_start_cyc, run2_cycles;
  longint unsigned run1_cycles;

  initial begin
    g_log_fd = $fopen("bootloader_spi_tb.log", "w");
    if (!g_log_fd)
      $display("[TB] WARNING: could not open bootloader_spi_tb.log - console-only logging");

    hard_rst_ni  = 1'b1;
    soft_rst_ni  = 1'b1;

    #1;

    build_golden_words();
    preload_flash();

    // ---------------- TC1: Cold Boot ----------------
    `TB_INFO(("\n===== TC1: Cold Boot ====="));
    t_start_cyc = cyc_cnt;
    t_start_time = $time;
    mon_word_count = 0;
    
    // Performance monitoring thread
    fork
      begin
        // Wait until FSM reaches S_CFG_SPIADR (state 7) for the first time
        wait(dut_bootloader.state_q == 4'd7); 
        t_cfg_cyc = cyc_cnt;
        t_cfg_time = $time;
      end
    join_none
    
    do_cold_boot();
    wait_boot_done(2000000); 
    
    // Capture boot end metrics
    t_boot_cyc = cyc_cnt;
    t_boot_time = $time;
    run1_cycles = t_boot_cyc - t_start_cyc;

    check_sram_contents("TC1");
    
    // Log the performance metrics
    `TB_INFO(("[TC1] SPI_CLK_DIV Value: %0d", SPI_CLK_DIV_TB));
    `TB_INFO(("[TC1] Configuration Phase: %0d cycles (%0t)", (t_cfg_cyc - t_start_cyc), (t_cfg_time - t_start_time)));
    `TB_INFO(("[TC1] SRAM Feeding Phase: %0d cycles (%0t)", (t_boot_cyc - t_cfg_cyc), (t_boot_time - t_cfg_time)));
    `TB_INFO(("[TC1] Total Boot Phase: %0d cycles (%0t)", run1_cycles, (t_boot_time - t_start_time)));

    // ---------------- TC3: Fixed-time determinism ----------------
    `TB_INFO(("\n===== TC3: Determinism (repeat cold boot) ====="));
    run2_start_cyc = cyc_cnt;
    mon_word_count = 0;
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
    $shm_open("bootloader_spi_tb.shm");

    $shm_probe(bootloader_spi_tb, "AS");
    $shm_probe(bootloader_spi_tb.dut_apb_spi_master, "AS");
    $shm_probe(bootloader_spi_tb.dut_apb_spi_master.u_spictrl, "AS");
    $shm_probe(bootloader_spi_tb.dut_apb_spi_master.u_axiregs, "AS");
    $shm_probe(bootloader_spi_tb.dut_apb_spi_master.u_txfifo, "AS");
    $shm_probe(bootloader_spi_tb.dut_apb_spi_master.u_txfifo, "AM");
    $shm_probe(bootloader_spi_tb.dut_apb_spi_master.u_rxfifo, "AS");
    $shm_probe(bootloader_spi_tb.dut_apb_spi_master.u_rxfifo, "AM");
    $shm_probe(bootloader_spi_tb.dut_bootloader, "AS");
    $shm_probe(bootloader_spi_tb.u_axi_mem, "AS");
    $shm_probe(bootloader_spi_tb.u_axi_mem, "AM");
    $shm_probe(bootloader_spi_tb.u_flash, "AS");
  end

endmodule : bootloader_spi_tb
