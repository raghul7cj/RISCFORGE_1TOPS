`timescale 1ns/1ps

// -------------------------------------------------------------------------
// Testbench Macros
// -------------------------------------------------------------------------
`define TB_INFO(msg_args) $display msg_args
`define TB_ERROR(msg_args) $error msg_args

// -------------------------------------------------------------------------
// Bus Package Definition
// -------------------------------------------------------------------------
package tb_bus_pkg;
  // AXI-Lite Write Address Channel
  typedef struct packed {
    logic [31:0] addr;
    logic [2:0]  prot;
  } aw_chan_t;

  // AXI-Lite Write Data Channel
  typedef struct packed {
    logic [31:0] data;
    logic [3:0]  strb;
  } w_chan_t;

  // AXI-Lite Write Response Channel
  typedef struct packed {
    logic [1:0] resp;
  } b_chan_t;

  // AXI-Lite Read Address Channel
  typedef struct packed {
    logic [31:0] addr;
    logic [2:0]  prot;
  } ar_chan_t;

  // AXI-Lite Read Data Channel
  typedef struct packed {
    logic [31:0] data;
    logic [1:0]  resp;
  } r_chan_t;

  // Combined AXI-Lite Request (Master -> Slave)
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

  // Combined AXI-Lite Response (Slave -> Master)
  typedef struct packed {
    logic     aw_ready;
    logic     w_ready;
    b_chan_t  b;
    logic     b_valid;
    logic     ar_ready;
    r_chan_t  r;
    logic     r_valid;
  } axi_lite_resp_t;

  // APB Request (Master -> Slave)
  typedef struct packed {
    logic [31:0] paddr;
    logic [2:0]  pprot;
    logic        psel;
    logic        penable;
    logic        pwrite;
    logic [31:0] pwdata;
    logic [3:0]  pstrb;
  } apb_req_t;

  // APB Response (Slave -> Master)
  typedef struct packed {
    logic        pready;
    logic [31:0] prdata;
    logic        pslverr;
  } apb_resp_t;
endpackage : tb_bus_pkg

// -------------------------------------------------------------------------
// Decoupled AXI-Lite Memory Model
// -------------------------------------------------------------------------
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

  logic [31:0] mem [0:MEM_WORDS-1];
  
  // Independent flags to track AW and W channel reception
  logic aw_received, w_received, b_valid_q;
  logic [31:0] aw_addr_q, w_data_q;

  // Intermediate signals to safely select active write address and data
  logic [31:0] write_addr_eff;
  logic [31:0] write_data_eff;

  assign write_addr_eff = aw_received ? aw_addr_q : req_i.aw.addr;
  assign write_data_eff = w_received  ? w_data_q  : req_i.w.data;

  // Slave is ready for address/data if it hasn't received them yet and isn't busy sending a response
  assign resp_o.aw_ready = ~aw_received && !b_valid_q;
  assign resp_o.w_ready  = ~w_received && !b_valid_q;
  assign resp_o.b_valid  = b_valid_q;
  assign resp_o.b.resp   = 2'b00; // OKAY response

  // Write Channel FSM
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aw_received <= 1'b0;
      w_received  <= 1'b0;
      b_valid_q   <= 1'b0;
      aw_addr_q   <= '0;
      w_data_q    <= '0;
    end else begin
      // Latch Address
      if (req_i.aw_valid && resp_o.aw_ready) begin
        aw_received <= 1'b1;
        aw_addr_q   <= req_i.aw.addr;
      end
      // Latch Data
      if (req_i.w_valid && resp_o.w_ready) begin
        w_received <= 1'b1;
        w_data_q   <= req_i.w.data;
      end

      // Perform memory write only when BOTH address and data are available
      if ((aw_received || (req_i.aw_valid && resp_o.aw_ready)) &&
          (w_received  || (req_i.w_valid  && resp_o.w_ready)) && !b_valid_q) begin
        aw_received <= 1'b0;
        w_received  <= 1'b0;
        b_valid_q   <= 1'b1;
        // Map 32-bit byte address to word index using intermediate write_addr_eff
        mem[write_addr_eff[$clog2(MEM_WORDS)+1:2]] <= write_data_eff;
      end

      // Clear response flag once master is ready
      if (b_valid_q && req_i.b_ready) begin
        b_valid_q <= 1'b0;
      end
    end
  end

  // Read Channel FSM
  logic r_valid_q;
  logic [31:0] r_data_q;

  assign resp_o.ar_ready = !r_valid_q || req_i.r_ready;
  assign resp_o.r_valid  = r_valid_q;
  assign resp_o.r.data   = r_data_q;
  assign resp_o.r.resp   = 2'b00; // OKAY response

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      r_valid_q <= 1'b0;
      r_data_q  <= '0;
    end else begin
      if (req_i.ar_valid && resp_o.ar_ready) begin
        r_valid_q <= 1'b1;
        r_data_q  <= mem[req_i.ar.addr[$clog2(MEM_WORDS)+1:2]];
      end else if (req_i.r_ready) begin
        r_valid_q <= 1'b0;
      end
    end
  end

  // Backdoor read function for testbench verification
  function automatic logic [31:0] backdoor_read(int unsigned word_idx);
    return mem[word_idx];
  endfunction
endmodule : axi_lite_mem

// -------------------------------------------------------------------------
// Main Testbench Module
// -------------------------------------------------------------------------
module bootloader_coldboot_tb;
  import tb_bus_pkg::*;

  // -------------------------------------------------------------------------
  // Parameters & Golden Configuration
  // -------------------------------------------------------------------------
  localparam int unsigned NUM_INSTR_WORDS_TB = 375;
  localparam int unsigned NUM_DATA_WORDS_TB  = 1164;
  localparam int unsigned TOTAL_WORDS_TB     = NUM_INSTR_WORDS_TB + NUM_DATA_WORDS_TB;
  localparam int unsigned IMAGE_BYTES        = 6156;
  localparam int unsigned ISRAM_NUM_WORDS_TB = 512;
  localparam int unsigned DSRAM_NUM_WORDS_TB = 2048;
  localparam int unsigned TOTAL_INSTR_DSRAM_CLEAR_WORDS = ISRAM_NUM_WORDS_TB + DSRAM_NUM_WORDS_TB;
  
  localparam logic [31:0] ISRAM_BASE = 32'h0000_0000;
  localparam logic [31:0] DSRAM_BASE = 32'h0001_0000;
  
  localparam time CLK_PERIOD = 10ns;
  localparam int unsigned BOOT_TIMEOUT_CYCLES = 2_000_000;
  localparam int unsigned HEARTBEAT_PERIOD_CYCLES = 2000;

  // -------------------------------------------------------------------------
  // Clock & Reset Generation
  // -------------------------------------------------------------------------
  logic clk;
  logic hard_rst_ni;
  logic soft_rst_ni;

  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // -------------------------------------------------------------------------
  // Interconnect Signals
  // -------------------------------------------------------------------------
  axi_lite_req_t  axi_req;
  axi_lite_resp_t axi_resp;
  apb_req_t  apb_slv_req;
  apb_resp_t apb_slv_resp;
  apb_req_t  apb_mst_req;
  apb_resp_t apb_mst_resp;

  logic core_rst_ni, periph_rst_ni, spi_rst_ni;
  logic boot_done;

  // SPI interface signals
  wire spi_clk_w;
  wire spi_csn0_w, spi_csn1_w, spi_csn2_w, spi_csn3_w;
  wire [1:0] spi_mode_w;
  wire spi_sdo0_w, spi_sdo1_w, spi_sdo2_w, spi_sdo3_w;
  wire spi_sdi0_w, spi_sdi1_w, spi_sdi2_w, spi_sdi3_w;
  logic [1:0] spi_events;

  // Flash Memory signals
  wire flash_SI, flash_SO, flash_SCK, flash_CSNeg;
  wire flash_WPNeg, flash_RESETNeg;

  // Map SPI Master to Flash Memory
  assign flash_SCK      = spi_clk_w;
  assign flash_CSNeg    = spi_csn0_w;
  assign flash_SI       = spi_sdo0_w;
  assign spi_sdi1_w     = flash_SO;   // FIX: MISO maps to SDI1 in standard mode
  assign spi_sdi0_w     = 1'b0;       // Tie off unused inputs
  assign spi_sdi2_w     = 1'b0;
  assign spi_sdi3_w     = 1'b0;
  assign flash_WPNeg    = 1'b1;
  assign flash_RESETNeg = 1'b1;

  // -------------------------------------------------------------------------
  // DUT Instantiation: Bootloader
  // -------------------------------------------------------------------------
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
    .SPI_CLK_DIV      ( 8'd4                ),
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

  // -------------------------------------------------------------------------
  // Peripheral Instantiations
  // -------------------------------------------------------------------------
  
  // APB SPI Master Controller
  apb_spi_master #(
    .BUFFER_DEPTH   ( 10 ),
    .APB_ADDR_WIDTH ( 12 )
  ) dut_apb_spi_master (
    .HCLK      ( clk                   ),
    .HRESETn   ( spi_rst_ni            ),
    .PADDR     ( apb_mst_req.paddr[11:0] ),
    .PWDATA    ( apb_mst_req.pwdata    ),
    .PWRITE    ( apb_mst_req.pwrite    ),
    .PSEL      ( apb_mst_req.psel      ),
    .PENABLE   ( apb_mst_req.penable   ),
    .PRDATA    ( apb_mst_resp.prdata   ),
    .PREADY    ( apb_mst_resp.pready   ),
    .PSLVERR   ( apb_mst_resp.pslverr  ),
    .events_o  ( spi_events ),
    .spi_clk   ( spi_clk_w  ),
    .spi_csn0  ( spi_csn0_w ),
    .spi_csn1  ( spi_csn1_w ),
    .spi_csn2  ( spi_csn2_w ),
    .spi_csn3  ( spi_csn3_w ),
    .spi_mode  ( spi_mode_w ),
    .spi_sdo0  ( spi_sdo0_w ),
    .spi_sdo1  ( spi_sdo1_w ),
    .spi_sdo2  ( spi_sdo2_w ),
    .spi_sdo3  ( spi_sdo3_w ),
    .spi_sdi0  ( spi_sdi0_w ),
    .spi_sdi1  ( spi_sdi1_w ),
    .spi_sdi2  ( spi_sdi2_w ),
    .spi_sdi3  ( spi_sdi3_w )
  );

  // SPI Flash Memory Model
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

  // AXI-Lite System SRAM
  axi_lite_mem #(
    .MEM_WORDS ( 32768 ) // FIX: Increased to 32K words to fit both 0x0000_0000 and 0x0001_0000 ranges
  ) u_axi_mem (
    .clk_i  ( clk      ),
    .rst_ni ( hard_rst_ni & soft_rst_ni ),
    .req_i  ( axi_req  ),
    .resp_o ( axi_resp )
  );

  initial apb_slv_req = '0;

  // -------------------------------------------------------------------------
  // Memory Preloading & Image Parsing
  // -------------------------------------------------------------------------
  byte unsigned golden_bytes [0:IMAGE_BYTES-1];
  logic [31:0]  golden_words [0:TOTAL_WORDS_TB-1];
  string mem_file_path = "../spi_slave_infinion/S25fs512s/model/ebreak_combined.mem";

  initial begin
    void'($value$plusargs("MEMFILE=%s", mem_file_path));
    `TB_INFO(("[TB] Loading firmware image from: %s", mem_file_path));
    $readmemh(mem_file_path, golden_bytes);
  end

  // Group bytes into words for easier verification
  task automatic build_golden_words();
    int w;
    for (w = 0; w < TOTAL_WORDS_TB; w++) begin
      golden_words[w] = { golden_bytes[w*4+3], golden_bytes[w*4+2],
                          golden_bytes[w*4+1], golden_bytes[w*4+0] };
    end
  endtask

  // Preload firmware into flash model
  task automatic preload_flash();
    int i;
    for (i = 0; i < IMAGE_BYTES; i++) begin
      u_flash.memory_features_i0.write_mem_w(i, golden_bytes[i]);
    end
    `TB_INFO(("[TB] Preloaded %0d bytes into flash from ebreak_combined.mem", IMAGE_BYTES));
  endtask

  // -------------------------------------------------------------------------
  // Verification Tasks
  // -------------------------------------------------------------------------
  longint unsigned cyc_cnt;
  always_ff @(posedge clk) cyc_cnt <= cyc_cnt + 1;

  task automatic do_cold_boot();
    hard_rst_ni = 1'b0;
    soft_rst_ni = 1'b1;
    repeat (5) @(posedge clk);
    hard_rst_ni = 1'b1;
    `TB_INFO(("[TB] Cold boot: hard_rst_ni released @cycle %0d", cyc_cnt));
  endtask

  task automatic wait_boot_done(int unsigned max_cycles);
    longint unsigned start_c = cyc_cnt;
    while (!boot_done && (cyc_cnt - start_c) < max_cycles) @(posedge clk);
    if (!boot_done)
      `TB_ERROR(("[TB] TIMEOUT waiting for boot_done_o (waited %0d cycles)", max_cycles));
  endtask

  function automatic int unsigned addr_to_word_idx(logic [31:0] addr);
    return addr[$clog2(32768)+1:2]; // FIX: Map to 32K words to match AXI Mem
  endfunction

  // Validate SRAM contents against golden words
  task automatic check_sram_contents();
    int w;
    int unsigned isram_idx, dsram_idx;
    logic [31:0] exp, act;
    int errors = 0;

    // Check ISRAM Segment
    for (w = 0; w < NUM_INSTR_WORDS_TB; w++) begin
      isram_idx = addr_to_word_idx(ISRAM_BASE + w*4);
      exp = golden_words[w];
      act = u_axi_mem.backdoor_read(isram_idx);
      if (exp !== act) begin
        errors++;
        if (errors <= 5)
          `TB_ERROR(("[TC1] ISRAM word %0d mismatch: exp=%08h act=%08h", w, exp, act));
      end
    end

    // Check DSRAM Segment
    for (w = 0; w < NUM_DATA_WORDS_TB; w++) begin
      dsram_idx = addr_to_word_idx(DSRAM_BASE + w*4);
      exp = golden_words[NUM_INSTR_WORDS_TB + w];
      act = u_axi_mem.backdoor_read(dsram_idx);
      if (exp !== act) begin
        errors++;
        if (errors <= 5)
          `TB_ERROR(("[TC1] DSRAM word %0d mismatch: exp=%08h act=%08h", w, exp, act));
      end
    end

    if (errors == 0)
      `TB_INFO(("[TC1] PASS: all %0d words (ISRAM+DSRAM) match golden image", TOTAL_WORDS_TB));
    else
      `TB_INFO(("[TC1] FAIL: %0d word mismatches found (showing first 5 only)", errors));
  endtask

  // -------------------------------------------------------------------------
  // Debug Monitors
  // -------------------------------------------------------------------------
  always @(posedge clk) begin
    if (cyc_cnt != 0 && (cyc_cnt % 50000 == 0)) begin
      $display("[MON] cyc=%0d state=%s clear=%0d/%0d word=%0d/%0d boot_done=%0b core_rst=%0b periph_rst=%0b spi_rst=%0b apb_pready=%0b",
               cyc_cnt,
               dut_bootloader.state_q.name,
               dut_bootloader.clear_cnt_q, TOTAL_INSTR_DSRAM_CLEAR_WORDS,
               dut_bootloader.word_cnt_q, TOTAL_WORDS_TB,
               boot_done, core_rst_ni, periph_rst_ni, spi_rst_ni,
               apb_mst_resp.pready);
    end
  end

  // SILENCED FOR SIMULATION SPEED: Log Bootloader State Transitions
  // always @(dut_bootloader.state_q) begin
  //   `TB_INFO(("[FSM] @cycle %0d: state_q -> %s", cyc_cnt, dut_bootloader.state_q.name));
  // end

  // Monitor APB stalls
  int unsigned stall_cnt = 0;
  always @(posedge clk) begin
    if (apb_mst_req.psel && apb_mst_req.penable) begin
      if (!apb_mst_resp.pready) begin
        stall_cnt++;
        // SILENCED FOR SIMULATION SPEED
        // if (stall_cnt == 10)
        //   `TB_INFO(("[APB_MST] STALL: PENABLE high with PREADY low for 10+ cycles @cycle %0d (paddr=%03h pwrite=%0b pwdata=%08h)",
        //              cyc_cnt, apb_mst_req.paddr, apb_mst_req.pwrite, apb_mst_req.pwdata));
      end else begin
        // SILENCED FOR SIMULATION SPEED
        // if (stall_cnt > 0)
        //   `TB_INFO(("[APB_MST] beat completed @cycle %0d after %0d stall cycles: paddr=%03h pwrite=%0b pwdata=%08h prdata=%08h",
        //              cyc_cnt, stall_cnt, apb_mst_req.paddr, apb_mst_req.pwrite, apb_mst_req.pwdata, apb_mst_resp.prdata));
        stall_cnt = 0;
      end
    end
  end

  /* SILENCED FOR SIMULATION SPEED
  always @(posedge clk) begin
    if (apb_mst_req.psel && apb_mst_req.penable && apb_mst_resp.pready) begin
      `TB_INFO(("[APB_DONE] @cycle %0d addr=%03h write=%0b data=%08h rdata=%08h",
               cyc_cnt, apb_mst_req.paddr, apb_mst_req.pwrite,
               apb_mst_req.pwdata, apb_mst_resp.prdata));
    end
  end
  */

  // Detect first SPI activity
  bit spi_activity_seen = 1'b0;
  always @(negedge flash_CSNeg) begin
    if (!spi_activity_seen) begin
      spi_activity_seen = 1'b1;
      `TB_INFO(("[SPI] First CS assertion seen @cycle %0d", cyc_cnt));
    end
  end

  int trigger_dump_cnt = -1;
  always @(posedge clk) begin
    if (dut_bootloader.state_q == dut_bootloader.S_TRIGGER && trigger_dump_cnt == -1)
      trigger_dump_cnt = 0;

    if (trigger_dump_cnt >= 0 && trigger_dump_cnt < 30) begin
      `TB_INFO(("[TRIG+%0d] @cyc%0d psel=%0b penable=%0b pwrite=%0b paddr=%03h pwdata=%08h pready=%0b | spi_rd=%0b spi_csreg=%04b | u_spictrl.state=%s spi_cs=%0b | csn0_w=%0b flash_CSNeg=%0b",
               trigger_dump_cnt, cyc_cnt,
               apb_mst_req.psel, apb_mst_req.penable, apb_mst_req.pwrite,
               apb_mst_req.paddr[11:0], apb_mst_req.pwdata, apb_mst_resp.pready,
               dut_apb_spi_master.spi_rd, dut_apb_spi_master.spi_csreg,
               dut_apb_spi_master.u_spictrl.state.name, dut_apb_spi_master.u_spictrl.spi_cs,
               spi_csn0_w, flash_CSNeg));
      trigger_dump_cnt++;
    end
  end

  always @(posedge clk) begin
    if (cyc_cnt != 0 && (cyc_cnt % HEARTBEAT_PERIOD_CYCLES) == 0) begin
      `TB_INFO(("[HEARTBEAT] @cycle %0d: state_q=%s clear_cnt_q=%0d/%0d word_cnt_q=%0d/%0d",
               cyc_cnt, dut_bootloader.state_q.name,
               dut_bootloader.clear_cnt_q, TOTAL_INSTR_DSRAM_CLEAR_WORDS,
               dut_bootloader.word_cnt_q, TOTAL_WORDS_TB));
    end
  end

  // -------------------------------------------------------------------------
  // Execution Block
  // -------------------------------------------------------------------------
  initial begin
    hard_rst_ni = 1'b1;
    soft_rst_ni = 1'b1;
    #1;

    build_golden_words();
    preload_flash();

    `TB_INFO(("\n===== TC1: Cold Boot ====="));
    do_cold_boot();
    wait_boot_done(BOOT_TIMEOUT_CYCLES);

    if (!spi_activity_seen)
      `TB_INFO(("[DIAG] No SPI CS assertion was ever observed"));

    check_sram_contents();

    `TB_INFO(("\n===== Cold boot debug run complete ====="));
    $finish;
  end

  // Global Failsafe Timeout
  initial begin
    #100ms;
    `TB_ERROR(("[TB] GLOBAL TIMEOUT"));
    $finish;
  end

  // Waveform Dumping
  initial begin
    $shm_open("bootloader_coldboot_tb.shm");
    $shm_probe(bootloader_coldboot_tb, "AS");
    $shm_probe(bootloader_coldboot_tb.dut_apb_spi_master, "AS");
    $shm_probe(bootloader_coldboot_tb.dut_apb_spi_master.u_spictrl, "AS");
    $shm_probe(bootloader_coldboot_tb.dut_apb_spi_master.u_axiregs, "AS");
    $shm_probe(bootloader_coldboot_tb.dut_apb_spi_master.u_txfifo, "AS");
    $shm_probe(bootloader_coldboot_tb.dut_apb_spi_master.u_txfifo, "AM");
    $shm_probe(bootloader_coldboot_tb.dut_apb_spi_master.u_rxfifo, "AS");
    $shm_probe(bootloader_coldboot_tb.dut_apb_spi_master.u_rxfifo, "AM");
    $shm_probe(bootloader_coldboot_tb.dut_bootloader, "AS");
    $shm_probe(bootloader_coldboot_tb.u_axi_mem, "AS");
    $shm_probe(bootloader_coldboot_tb.u_axi_mem, "AM");
    $shm_probe(bootloader_coldboot_tb.u_flash, "AS");
  end
endmodule : bootloader_coldboot_tb
