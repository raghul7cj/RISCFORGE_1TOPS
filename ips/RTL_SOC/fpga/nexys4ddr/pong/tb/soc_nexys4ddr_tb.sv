// =============================================================================
// RISCFORGE 1TOPS — Nexys 4 DDR board-top testbench
// =============================================================================
// Simulates top_pong (not the bare SoC) the way the board powers up:
// CPU_RESETN is released from time 0, and the flash holds the firmware at the
// board offset 0x400000 with everything below it erased (where the bitstream
// would sit). It checks the parts that are new in the board top:
//
//   A  pre-boot: >= 3 dummy flash clocks with QSPI_CSN high, before the SoC
//      leaves reset; CSN never low before that (STARTUPE2 workaround)
//   B  cold boot reads the image from 0x400000 (defparam FLASH_START_ADDR):
//      ISRAM / DSRAM match the image; LED[0] boot_done, LED[1] pre-boot done
//   C  the Pong title arrives on UART_RXD_OUT
//   D  CPU_RESETN press: boot_done drops, the SoC boots again from flash,
//      the title arrives again
//   E  LED[2] (bus timeout) stays off, no UART framing error
//
// STARTUPE2 is not simulated (top_pong instantiates it only under
// `SYNTHESIS); the flash model is clocked from the internal net dut.flash_sck.
// -----------------------------------------------------------------------------
// Prepare (simulation build of Pong, then the offset preload file):
//     cd ips/RTL_SOC/mem/pong && python build.py --sim
//     python ../../fpga/nexys4ddr/pong/tb/make_sim_flash.py
// Select in ips/RTL_SOC/run.f:
//     +incdir+../mem/pong/sim_build
//     ../fpga/nexys4ddr/pong/top_pong.sv
//     ../fpga/nexys4ddr/pong/tb/soc_nexys4ddr_tb.sv
//     -top soc_nexys4ddr_tb
// Run from ips/RTL_SOC/sim/:
//     xrun -f ../run.f -l logs/nexys4ddr.log          (+WAVES for soc_nexys4ddr_tb.shm)
// =============================================================================
`timescale 1ns/1ps

module soc_nexys4ddr_tb;

  `include "fw_params.svh"

  localparam time         CLK_PERIOD   = 10ns;
  localparam int unsigned UART_BIT_CYC = 16 * FW_UART_DIV;
  localparam int unsigned RES_WORDS    = 16;
  localparam longint unsigned BOOT_TIMEOUT_CYCLES = 300_000 + 400 * (FW_NUM_INSTR_WORDS + FW_NUM_DATA_WORDS);
  localparam longint unsigned TITLE_TIMEOUT_CYCLES = 2_000_000;

  localparam string FLASH_FILE = "../fpga/nexys4ddr/pong/tb/pong_flash_at_400000.mem";
  localparam string OTP_FILE   = "../../spi_slave_infinion/S25fs512s/model/s25fs512sOTP.mem";

  // ───────────────────────────────────────────────────────────────────────
  //  Board
  // ───────────────────────────────────────────────────────────────────────
  logic        clk;
  logic        cpu_resetn;
  logic        uart_txd_in;      // PC -> FPGA
  wire         uart_rxd_out;     // FPGA -> PC
  wire         qspi_csn, qspi_dq0, qspi_dq1, qspi_dq2, qspi_dq3;
  wire  [15:0] led;

  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  longint unsigned cyc_cnt;
  always_ff @(posedge clk) cyc_cnt <= cyc_cnt + 1;

  initial begin
    cpu_resetn  = 1'b1;          // button not pressed at power-up
    uart_txd_in = 1'b1;
  end

  top_pong dut (
    .CLK100MHZ    ( clk          ),
    .CPU_RESETN   ( cpu_resetn   ),
    .UART_TXD_IN  ( uart_txd_in  ),
    .UART_RXD_OUT ( uart_rxd_out ),
    .QSPI_CSN     ( qspi_csn     ),
    .QSPI_DQ0     ( qspi_dq0     ),
    .QSPI_DQ1     ( qspi_dq1     ),
    .QSPI_DQ2     ( qspi_dq2     ),
    .QSPI_DQ3     ( qspi_dq3     ),
    .LED          ( led          )
  );

  wire flash_sck = dut.flash_sck;    // CCLK (STARTUPE2.USRCCLKO on the board)

  s25fs512s #(
    .UserPreload   ( 1          ),
    .mem_file_name ( FLASH_FILE ),
    .otp_file_name ( OTP_FILE   )
  ) u_flash (
    .SI       ( qspi_dq0  ),
    .SO       ( qspi_dq1  ),
    .SCK      ( flash_sck ),
    .CSNeg    ( qspi_csn  ),
    .WPNeg    ( qspi_dq2  ),
    .RESETNeg ( qspi_dq3  )      // HOLD# on the board; the model has RESET# instead, both idle high
  );

  `define ISRAM_W(i)  dut.u_soc.i_isram.u_imem.mem_array[i]
  `define DSRAM_W(i)  dut.u_soc.i_dsram.mem[i]

  // ───────────────────────────────────────────────────────────────────────
  //  Checks
  // ───────────────────────────────────────────────────────────────────────
  int unsigned tb_pass, tb_fail;

  task automatic tb_check(input string label, input bit cond);
    if (cond) begin
      tb_pass++;
      $display("[TB]   PASS  %s", label);
    end else begin
      tb_fail++;
      $display("[TB]   FAIL  %s", label);
    end
  endtask

  // Pre-boot monitor: SCK edges and CSN while the SoC is still in reset
  int unsigned pre_sck_edges, pre_csn_low;
  always @(posedge flash_sck)
    if (dut.preboot_done !== 1'b1) pre_sck_edges++;
  always @(posedge clk)
    if (dut.preboot_done !== 1'b1 && qspi_csn !== 1'b1) pre_csn_low++;

  // UART decoder; keeps the last 64 printable characters
  int unsigned uart_bytes, uart_frame_err, title_seen;
  string       uart_tail;

  function automatic bit tail_has(input string s, input string pat);
    for (int i = 0; i + pat.len() <= s.len(); i++)
      if (s.substr(i, i + pat.len() - 1) == pat) return 1'b1;
    return 1'b0;
  endfunction

  initial begin
    logic [7:0] b;
    uart_tail = "";
    forever begin
      @(negedge uart_rxd_out);
      repeat (UART_BIT_CYC / 2) @(posedge clk);
      if (uart_rxd_out !== 1'b0) continue;
      for (int i = 0; i < 8; i++) begin
        repeat (UART_BIT_CYC) @(posedge clk);
        b[i] = uart_rxd_out;
      end
      repeat (UART_BIT_CYC) @(posedge clk);
      if (uart_rxd_out !== 1'b1) uart_frame_err++;
      uart_bytes++;
      if (b >= 8'h20 && b <= 8'h7E) begin
        uart_tail = $sformatf("%s%c", uart_tail, b);
        if (uart_tail.len() > 64) uart_tail = uart_tail.substr(uart_tail.len() - 64, uart_tail.len() - 1);
        if (tail_has(uart_tail, "RISCFORGE PONG")) begin
          title_seen++;
          uart_tail = "";
        end
      end
    end
  end

  // ───────────────────────────────────────────────────────────────────────
  //  Sequence
  // ───────────────────────────────────────────────────────────────────────
  logic [31:0] golden_i [0:FW_NUM_INSTR_WORDS-1];
  logic [31:0] golden_d [0:FW_NUM_DATA_WORDS-1];

  task automatic wait_boot(input string what);
    longint unsigned n;
    n = 0;
    while (led[0] !== 1'b1 && n < BOOT_TIMEOUT_CYCLES) begin
      @(posedge clk);
      n++;
    end
    tb_check($sformatf("%s: boot_done (LED[0]) at cyc %0d", what, cyc_cnt), led[0] === 1'b1);
  endtask

  task automatic wait_title(input string what, input int unsigned count);
    longint unsigned n;
    n = 0;
    while (title_seen < count && n < TITLE_TIMEOUT_CYCLES) begin
      @(posedge clk);
      n++;
    end
    tb_check($sformatf("%s: \"RISCFORGE PONG\" on UART_RXD_OUT (cyc %0d)", what, cyc_cnt),
             title_seen >= count);
  endtask

  initial begin
    int unsigned mism;

    if ($test$plusargs("WAVES")) begin
      `ifdef XCELIUM
        $shm_open("soc_nexys4ddr_tb.shm");
        $shm_probe(soc_nexys4ddr_tb, "ASMC");
      `else
        $dumpfile("soc_nexys4ddr_tb.vcd");
        $dumpvars(0, soc_nexys4ddr_tb);
      `endif
    end

    $readmemh(FW_IMEM_HEX, golden_i);
    $readmemh(FW_DMEM_HEX, golden_d);

    $display("[TB] --- RISCFORGE SoC — Nexys 4 DDR board top");
    $display("[TB]  Flash preload : %s (image at 0x400000)", FLASH_FILE);
    $display("[TB]  Image         : %0d ISRAM + %0d DSRAM words", FW_NUM_INSTR_WORDS, FW_NUM_DATA_WORDS);

    // ── A: pre-boot ──────────────────────────────────────────────────
    $display("[TB] --- A: pre-boot dummy clocks");
    wait (dut.preboot_done === 1'b1);
    tb_check($sformatf("%0d dummy SCK edges before the SoC leaves reset (>= 3)", pre_sck_edges),
             pre_sck_edges >= 3);
    tb_check($sformatf("QSPI_CSN high throughout pre-boot (%0d low cycles)", pre_csn_low),
             pre_csn_low == 0);
    tb_check("LED[1] pre-boot done", led[1] === 1'b1);

    // ── B: cold boot from 0x400000 ───────────────────────────────────
    $display("[TB] --- B: cold boot from flash offset 0x400000");
    wait_boot("power-up");
    mism = 0;
    for (int i = 0; i < FW_NUM_INSTR_WORDS; i++)
      if (`ISRAM_W(i) !== golden_i[i]) mism++;
    tb_check($sformatf("ISRAM holds the image (%0d of %0d words differ)", mism, FW_NUM_INSTR_WORDS),
             mism == 0);
    mism = 0;
    for (int i = RES_WORDS; i < FW_NUM_DATA_WORDS; i++)
      if (`DSRAM_W(i) !== golden_d[i]) mism++;
    tb_check($sformatf("DSRAM holds the data words (%0d differ)", mism), mism == 0);

    // ── C: UART ──────────────────────────────────────────────────────
    $display("[TB] --- C: Pong on the UART");
    wait_title("power-up", 1);

    // ── D: reset button ──────────────────────────────────────────────
    $display("[TB] --- D: CPU_RESETN press re-boots from flash");
    cpu_resetn = 1'b0;
    repeat (2000) @(posedge clk);
    tb_check("boot_done drops while CPU_RESETN is held", led[0] === 1'b0);
    cpu_resetn = 1'b1;
    wait_boot("after reset");
    wait_title("after reset", 2);

    // ── E ────────────────────────────────────────────────────────────
    $display("[TB] --- E: whole run");
    tb_check("LED[2] bus-timeout indicator off", led[2] === 1'b0);
    tb_check($sformatf("no UART framing error (%0d bytes)", uart_bytes),
             uart_frame_err == 0 && uart_bytes > 0);

    $display("[TB] ------------------------------------------------------------------");
    $display("[TB]  TB checks : %0d passed, %0d failed   (%0d cycles)", tb_pass, tb_fail, cyc_cnt);
    if (tb_fail == 0) $display("[TB]  *** NEXYS4DDR BOARD TOP TEST PASSED ***");
    else              $display("[TB]  *** NEXYS4DDR BOARD TOP TEST FAILED ***");
    $display("[TB] ------------------------------------------------------------------");
    $finish;
  end

  initial begin
    #60ms;
    $display("[TB] GLOBAL TIMEOUT (60 ms simulated)");
    $finish;
  end

endmodule : soc_nexys4ddr_tb
