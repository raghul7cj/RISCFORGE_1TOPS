// =============================================================================
// RISC-V Instruction Injection via SPI — BFM Testbench
// DUT: apb_spi_master (ETH Zurich / University of Bologna)
//
// Purpose: Verify end-to-end instruction loading path:
//   SPI Slave BFM (spi_inject_word) → SPI Master RX → RX FIFO → APB Read
//
// Tests:
//   TC1 – Single RISC-V instruction inject, FIFO probe, APB readback
//   TC2 – Sequential 4-instruction load (4 separate SPI transactions)
//   TC3 – Back-to-back burst (4x32-bit in one 128-bit SPI transaction)
//   TC4 – APB transaction validation with protocol logging
// =============================================================================

`timescale 1ns/1ps

module tb_apb_spi_master_bfm;

  // -----------------------------------------------------------------------
  // Parameters
  // -----------------------------------------------------------------------
  parameter BUFFER_DEPTH   = 10;
  parameter APB_ADDR_WIDTH = 12;
  parameter CLK_PERIOD     = 10;

  // -----------------------------------------------------------------------
  // Register addresses
  // -----------------------------------------------------------------------
  localparam REG_STATUS = 4'b0000;
  localparam REG_CLKDIV = 4'b0001;
  localparam REG_SPICMD = 4'b0010;
  localparam REG_SPIADR = 4'b0011;
  localparam REG_SPILEN = 4'b0100;
  localparam REG_SPIDUM = 4'b0101;
  localparam REG_TXFIFO = 4'b0110;
  localparam REG_RXFIFO = 4'b1000;
  localparam REG_INTCFG = 4'b1001;
  localparam REG_INTSTA = 4'b1010;

  // -----------------------------------------------------------------------
  // RISC-V instructions used for testing
  // -----------------------------------------------------------------------
  localparam logic [31:0] RISCV_NOP     = 32'h00000013; // addi x0, x0, 0
  localparam logic [31:0] RISCV_ADDI_X1 = 32'h00500093; // addi x1, x0, 5
  localparam logic [31:0] RISCV_ADDI_X2 = 32'h00A00113; // addi x2, x0, 10
  localparam logic [31:0] RISCV_ADD_X3  = 32'h002081B3; // add  x3, x1, x2
  localparam logic [31:0] RISCV_SW_X3   = 32'h00302023; // sw   x3, 0(x0)

  // -----------------------------------------------------------------------
  // DUT signals
  // -----------------------------------------------------------------------
  logic                      HCLK;
  logic                      HRESETn;
  logic [APB_ADDR_WIDTH-1:0] PADDR;
  logic [31:0]               PWDATA;
  logic                      PWRITE;
  logic                      PSEL;
  logic                      PENABLE;
  logic [31:0]               PRDATA;
  logic                      PREADY;
  logic                      PSLVERR;
  logic [1:0]                events_o;

  logic spi_clk;
  logic spi_csn0, spi_csn1, spi_csn2, spi_csn3;
  logic [1:0] spi_mode;
  logic spi_sdo0, spi_sdo1, spi_sdo2, spi_sdo3;
  logic spi_sdi0, spi_sdi1, spi_sdi2, spi_sdi3;

  // -----------------------------------------------------------------------
  // Pass / fail counters
  // -----------------------------------------------------------------------
  int pass_cnt = 0;
  int fail_cnt = 0;

  // -----------------------------------------------------------------------
  // Address helper
  // -----------------------------------------------------------------------
  function automatic logic [APB_ADDR_WIDTH-1:0] reg_addr(input logic [3:0] idx);
    reg_addr = {6'h0, idx, 2'b00};
  endfunction

  // -----------------------------------------------------------------------
  // DUT instantiation
  // -----------------------------------------------------------------------
  apb_spi_master #(
    .BUFFER_DEPTH   (BUFFER_DEPTH),
    .APB_ADDR_WIDTH (APB_ADDR_WIDTH)
  ) dut (
    .HCLK    (HCLK),    .HRESETn (HRESETn),
    .PADDR   (PADDR),   .PWDATA  (PWDATA),
    .PWRITE  (PWRITE),  .PSEL    (PSEL),
    .PENABLE (PENABLE), .PRDATA  (PRDATA),
    .PREADY  (PREADY),  .PSLVERR (PSLVERR),
    .events_o(events_o),
    .spi_clk (spi_clk),
    .spi_csn0(spi_csn0), .spi_csn1(spi_csn1),
    .spi_csn2(spi_csn2), .spi_csn3(spi_csn3),
    .spi_mode(spi_mode),
    .spi_sdo0(spi_sdo0), .spi_sdo1(spi_sdo1),
    .spi_sdo2(spi_sdo2), .spi_sdo3(spi_sdo3),
    .spi_sdi0(spi_sdi0), .spi_sdi1(spi_sdi1),
    .spi_sdi2(spi_sdi2), .spi_sdi3(spi_sdi3)
  );

  // -----------------------------------------------------------------------
  // APB Master BFM
  // -----------------------------------------------------------------------
  apb_master_bfm #(
    .APB_ADDR_WIDTH(APB_ADDR_WIDTH)
  ) u_apb_bfm (
    .HCLK    (HCLK),    .HRESETn (HRESETn),
    .PADDR   (PADDR),   .PWDATA  (PWDATA),
    .PWRITE  (PWRITE),  .PSEL    (PSEL),
    .PENABLE (PENABLE), .PRDATA  (PRDATA),
    .PREADY  (PREADY)
  );

  // -----------------------------------------------------------------------
  // SPI signal tie-offs (standard mode: only sdi1 carries data)
  // -----------------------------------------------------------------------
  assign spi_sdi0 = 1'b0;
  assign spi_sdi2 = 1'b0;
  assign spi_sdi3 = 1'b0;

  // -----------------------------------------------------------------------
  // Clock generation
  // -----------------------------------------------------------------------
  initial HCLK = 1'b0;
  always #(CLK_PERIOD/2) HCLK = ~HCLK;

  // =======================================================================
  // SPI Slave BFM Tasks
  // =======================================================================

  // Inject a single 32-bit word on spi_sdi1 (MSB-first, standard SPI)
  // Drives data on negedge spi_clk so DUT samples on the next rising edge.
  task automatic spi_inject_word(input logic [31:0] word);
    int i;
    begin
      spi_sdi1 = 1'b0;
      wait (spi_csn0 === 1'b0);      // wait for CSN assertion
      spi_sdi1 = word[31];           // drive MSB before first rising edge
      for (i = 30; i >= 0; i--) begin
        @(negedge spi_clk);
        spi_sdi1 = word[i];
      end
      wait (spi_csn0 === 1'b1);      // hold last bit until transaction ends
      spi_sdi1 = 1'b0;
    end
  endtask

  // Inject multiple 32-bit words back-to-back in a single SPI transaction.
  // Used when spi_data_len > 32 (e.g. 128 = 4 words).
  // No gap between words — the RX module internally segments every 32 bits.
  task automatic spi_inject_burst(
    input logic [31:0] w0, w1, w2, w3,
    input int          num_words
  );
    logic [31:0] words [0:3];
    int w, i;
    begin
      words[0] = w0; words[1] = w1; words[2] = w2; words[3] = w3;
      spi_sdi1 = 1'b0;
      wait (spi_csn0 === 1'b0);
      spi_sdi1 = words[0][31];       // drive MSB before first rising edge
      for (w = 0; w < num_words; w++) begin
        for (i = (w == 0 ? 30 : 31); i >= 0; i--) begin
          @(negedge spi_clk);
          spi_sdi1 = words[w][i];
        end
      end
      wait (spi_csn0 === 1'b1);      // hold last bit until transaction ends
      spi_sdi1 = 1'b0;
    end
  endtask

  // =======================================================================
  // APB Helper Tasks
  // =======================================================================

  task automatic cfg_spi(
    input logic [7:0]  clk_div,
    input logic [31:0] cmd_val,
    input logic [5:0]  cmd_bits,
    input logic [31:0] adr_val,
    input logic [5:0]  adr_bits,
    input logic [15:0] data_bits,
    input logic [15:0] dum_rd,
    input logic [15:0] dum_wr
  );
    begin
      u_apb_bfm.apb_write(reg_addr(REG_CLKDIV), {24'h0, clk_div});
      u_apb_bfm.apb_write(reg_addr(REG_SPICMD), cmd_val);
      u_apb_bfm.apb_write(reg_addr(REG_SPIADR), adr_val);
      u_apb_bfm.apb_write(reg_addr(REG_SPILEN), {data_bits, 2'b00, adr_bits, 2'b00, cmd_bits});
      u_apb_bfm.apb_write(reg_addr(REG_SPIDUM), {dum_wr, dum_rd});
    end
  endtask

  task automatic trigger_read(input logic [3:0] cs = 4'b0001);
    begin
      u_apb_bfm.apb_write(reg_addr(REG_STATUS), {20'h0, cs, 4'h0, 4'b0001});
    end
  endtask

  task automatic core_read_rx(output logic [31:0] data);
    begin
      u_apb_bfm.apb_read(reg_addr(REG_RXFIFO), data);
    end
  endtask

  task automatic read_status(output logic [31:0] data);
    begin
      u_apb_bfm.apb_read(reg_addr(REG_STATUS), data);
    end
  endtask

  task automatic wait_eot(input int timeout_cycles = 10000);
    int cnt;
    begin
      cnt = 0;
      while ((dut.s_eot !== 1'b1) && (cnt < timeout_cycles)) begin
        @(posedge HCLK);
        cnt++;
      end
      if (cnt >= timeout_cycles)
        $display("  [FAIL] EOT timeout after %0d cycles", timeout_cycles);
      else
        $display("  [INFO] EOT observed after %0d cycles", cnt);
      @(posedge HCLK);
    end
  endtask

  // =======================================================================
  // Checker
  // =======================================================================
  task automatic check(
    input string       msg,
    input logic [31:0] got,
    input logic [31:0] exp,
    input logic [31:0] mask = 32'hFFFF_FFFF
  );
    if ((got & mask) === (exp & mask)) begin
      $display("  [PASS] %s  got=0x%08X  exp=0x%08X", msg, got, exp);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %s  got=0x%08X  exp=0x%08X (mask=0x%08X)", msg, got, exp, mask);
      fail_cnt++;
    end
  endtask

  // =======================================================================
  // Main Test Sequence
  // =======================================================================
  logic [31:0] rx_word;
  logic [31:0] status_word;

  initial begin
    HRESETn  = 1'b0;
    u_apb_bfm.idle_bus();
    spi_sdi1 = 1'b0;
    repeat (5) @(posedge HCLK);
    HRESETn = 1'b1;
    repeat (5) @(posedge HCLK);

    $display("\n");
    $display("============================================================");
    $display("  RISC-V Instruction Injection via SPI - BFM Testbench");
    $display("============================================================");
    $display("  Data path: SPI Slave BFM -> SPI Master RX -> RX FIFO -> APB");
    $display("============================================================\n");

    // ==================================================================
    // TC1: Single RISC-V Instruction Injection
    //   - Inject NOP (0x00000013) via SPI slave BFM
    //   - Verify it lands in RX FIFO
    //   - Read back via APB and confirm integrity
    // ==================================================================
    $display("\n========== TC1: Single Instruction Inject (NOP) ==========");
    $display("  Injecting: 0x%08X (addi x0, x0, 0 = NOP)", RISCV_NOP);

    cfg_spi(8'd4, 32'h0, 6'd0, 32'h0, 6'd0, 16'd32, 16'd0, 16'd0);
    fork
      spi_inject_word(RISCV_NOP);
      begin
        trigger_read();
        wait_eot();
      end
    join

    // Probe FIFO internals
    $display("  [PROBE] RX FIFO elements  = %0d (expect 1)", dut.u_rxfifo.elements);
    $display("  [PROBE] RX FIFO buffer[0] = 0x%08X", dut.u_rxfifo.buffer[0]);
    check("TC1: FIFO fill level", {28'h0, dut.u_rxfifo.elements}, 32'h1, 32'hF);

    // APB readback
    core_read_rx(rx_word);
    $display("  [APB]   PRDATA = 0x%08X", rx_word);
    check("TC1: NOP instruction via APB", rx_word, RISCV_NOP);

    $display("  [PROBE] RX FIFO elements after read = %0d (expect 0)",
             dut.u_rxfifo.elements);

    // ==================================================================
    // TC2: Sequential Multi-Instruction Loading
    //   - 4 real RISC-V instructions, each as a separate SPI read
    //   - Verifies repeated inject-and-read cycles
    // ==================================================================
    $display("\n========== TC2: Sequential 4-Instruction Load ==========");
    begin
      logic [31:0] instr [0:3];
      string       names [0:3];
      int          k;

      instr[0] = RISCV_ADDI_X1;  names[0] = "addi x1, x0, 5 ";
      instr[1] = RISCV_ADDI_X2;  names[1] = "addi x2, x0, 10";
      instr[2] = RISCV_ADD_X3;   names[2] = "add  x3, x1, x2";
      instr[3] = RISCV_SW_X3;    names[3] = "sw   x3, 0(x0) ";

      for (k = 0; k < 4; k++) begin
        $display("\n  --- Instr[%0d]: 0x%08X  %s ---", k, instr[k], names[k]);

        cfg_spi(8'd4, 32'h0, 6'd0, 32'h0, 6'd0, 16'd32, 16'd0, 16'd0);
        fork
          spi_inject_word(instr[k]);
          begin
            trigger_read();
            wait_eot();
          end
        join

        $display("  [PROBE] RX FIFO elements = %0d", dut.u_rxfifo.elements);
        core_read_rx(rx_word);
        check($sformatf("TC2[%0d]: %s", k, names[k]), rx_word, instr[k]);
      end
    end

    // ==================================================================
    // TC3: Back-to-Back Burst (single 128-bit SPI transaction)
    //   - 4 words injected in one continuous CSN assertion
    //   - RX module segments every 32 bits into FIFO entries
    //   - Drain all 4 via APB and verify order + data
    // ==================================================================
    $display("\n========== TC3: Burst Inject (4x32b, 128-bit SPI read) ==========");
    $display("  Words: 0x%08X, 0x%08X, 0x%08X, 0x%08X",
             RISCV_ADDI_X1, RISCV_ADDI_X2, RISCV_ADD_X3, RISCV_SW_X3);

    cfg_spi(8'd4, 32'h0, 6'd0, 32'h0, 6'd0, 16'd128, 16'd0, 16'd0);
    fork
      spi_inject_burst(RISCV_ADDI_X1, RISCV_ADDI_X2, RISCV_ADD_X3, RISCV_SW_X3, 4);
      begin
        trigger_read();
        wait_eot();
      end
    join

    $display("  [PROBE] RX FIFO elements = %0d (expect 4)", dut.u_rxfifo.elements);
    check("TC3: FIFO has 4 entries",
          {28'h0, dut.u_rxfifo.elements}, 32'h4, 32'hF);

    // Drain all 4 words via APB
    core_read_rx(rx_word);
    check("TC3: Word[0] addi x1", rx_word, RISCV_ADDI_X1);
    core_read_rx(rx_word);
    check("TC3: Word[1] addi x2", rx_word, RISCV_ADDI_X2);
    core_read_rx(rx_word);
    check("TC3: Word[2] add  x3", rx_word, RISCV_ADD_X3);
    core_read_rx(rx_word);
    check("TC3: Word[3] sw   x3", rx_word, RISCV_SW_X3);

    $display("  [PROBE] RX FIFO elements after drain = %0d (expect 0)",
             dut.u_rxfifo.elements);

    // ==================================================================
    // TC4: APB Transaction Validation
    //   - Inject one word via SPI
    //   - Read back via APB with protocol-level logging
    //   - Confirms data appears as a valid APB read transaction
    // ==================================================================
    $display("\n========== TC4: APB Transaction Validation ==========");
    $display("  Injecting: 0xFEEDC0DE");

    cfg_spi(8'd4, 32'h0, 6'd0, 32'h0, 6'd0, 16'd32, 16'd0, 16'd0);
    fork
      spi_inject_word(32'hFEEDC0DE);
      begin
        trigger_read();
        wait_eot();
      end
    join

    // Display APB transaction log
    $display("  [APB TRANSACTION LOG]");
    $display("  +---------------------------------------------------+");
    $display("  | Register : REG_RXFIFO (0x%03X)                     |",
             reg_addr(REG_RXFIFO));
    $display("  | Type     : READ                                   |");
    core_read_rx(rx_word);
    $display("  | PRDATA   : 0x%08X                              |", rx_word);
    $display("  | PREADY   : %b (immediate)                          |", PREADY);
    $display("  | PSLVERR  : %b (no error)                           |", PSLVERR);
    $display("  +---------------------------------------------------+");
    check("TC4: APB read data integrity", rx_word, 32'hFEEDC0DE);

    // Verify controller returned to IDLE
    read_status(status_word);
    check("TC4: Controller IDLE after txn",
          status_word, 32'h1, 32'h0000_007F);

    // ==================================================================
    // Summary
    // ==================================================================
    $display("\n============================================================");
    $display("  RESULTS:  PASSED = %0d  /  FAILED = %0d", pass_cnt, fail_cnt);
    $display("============================================================");
    if (fail_cnt == 0)
      $display("  *** ALL TESTS PASSED ***");
    else
      $display("  *** %0d TEST(S) FAILED ***", fail_cnt);
    $display("============================================================\n");

    #100;
    $finish;
  end

  // -----------------------------------------------------------------------
  // Global watchdog
  // -----------------------------------------------------------------------
  initial begin
    #10_000_000;
    $display("[ERROR] Global watchdog timeout!");
    $finish;
  end

  // -----------------------------------------------------------------------
  // Waveform dump (Cadence Xcelium)
  // -----------------------------------------------------------------------
  initial begin
    $recordfile("tb_spi_bfm.trn");
    $recordvars();
    $recordvars(tb_apb_spi_master_bfm.dut.u_txfifo);
    $recordvars(tb_apb_spi_master_bfm.dut.u_rxfifo);
  end

endmodule