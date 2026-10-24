`timescale 1ns/1ps

// RISC-V Instruction Injection via SPI — BFM Testbench
// DUT: apb_spi_master (ETH Zurich / University of Bologna)
// Data path: SPI Slave BFM -> SPI Master RX -> RX FIFO -> APB Read
//
// TC1 - Single instruction inject, FIFO probe, APB readback
// TC2 - Sequential 4-instruction load (4 separate SPI transactions)
// TC3 - Back-to-back burst (4x32-bit in one 128-bit SPI transaction)
// TC4 - APB transaction validation with protocol logging
// TC5 - RX FIFO overflow / backpressure stall + recovery
// TC6 - Empty FIFO silent stale data read (PREADY=1 bug)

module tb_apb_spi_master_bfm;

  parameter BUFFER_DEPTH   = 10;
  parameter APB_ADDR_WIDTH = 12;
  parameter CLK_PERIOD     = 10;

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

  localparam logic [31:0] RISCV_NOP     = 32'h00000013; // addi x0, x0, 0
  localparam logic [31:0] RISCV_ADDI_X1 = 32'h00500093; // addi x1, x0, 5
  localparam logic [31:0] RISCV_ADDI_X2 = 32'h00A00113; // addi x2, x0, 10
  localparam logic [31:0] RISCV_ADD_X3  = 32'h002081B3; // add  x3, x1, x2
  localparam logic [31:0] RISCV_SW_X3   = 32'h00302023; // sw   x3, 0(x0)

  logic                      HCLK, HRESETn;
  logic [APB_ADDR_WIDTH-1:0] PADDR;
  logic [31:0]               PWDATA, PRDATA;
  logic                      PWRITE, PSEL, PENABLE, PREADY, PSLVERR;
  logic [1:0]                events_o;

  logic        spi_clk;
  logic        spi_csn0, spi_csn1, spi_csn2, spi_csn3;
  logic [1:0]  spi_mode;
  logic        spi_sdo0, spi_sdo1, spi_sdo2, spi_sdo3;
  logic        spi_sdi0, spi_sdi1, spi_sdi2, spi_sdi3;

  function automatic logic [APB_ADDR_WIDTH-1:0] reg_addr(input logic [3:0] idx);
    reg_addr = {6'h0, idx, 2'b00};
  endfunction

  apb_spi_master #(
    .BUFFER_DEPTH(BUFFER_DEPTH), .APB_ADDR_WIDTH(APB_ADDR_WIDTH)
  ) dut (
    .HCLK(HCLK), .HRESETn(HRESETn),
    .PADDR(PADDR), .PWDATA(PWDATA), .PWRITE(PWRITE),
    .PSEL(PSEL), .PENABLE(PENABLE), .PRDATA(PRDATA),
    .PREADY(PREADY), .PSLVERR(PSLVERR), .events_o(events_o),
    .spi_clk(spi_clk),
    .spi_csn0(spi_csn0), .spi_csn1(spi_csn1),
    .spi_csn2(spi_csn2), .spi_csn3(spi_csn3),
    .spi_mode(spi_mode),
    .spi_sdo0(spi_sdo0), .spi_sdo1(spi_sdo1),
    .spi_sdo2(spi_sdo2), .spi_sdo3(spi_sdo3),
    .spi_sdi0(spi_sdi0), .spi_sdi1(spi_sdi1),
    .spi_sdi2(spi_sdi2), .spi_sdi3(spi_sdi3)
  );

  apb_master_bfm #(.APB_ADDR_WIDTH(APB_ADDR_WIDTH)) u_apb_bfm (
    .HCLK(HCLK), .HRESETn(HRESETn),
    .PADDR(PADDR), .PWDATA(PWDATA), .PWRITE(PWRITE),
    .PSEL(PSEL), .PENABLE(PENABLE), .PRDATA(PRDATA), .PREADY(PREADY)
  );

  assign spi_sdi0 = 1'b0;
  assign spi_sdi2 = 1'b0;
  assign spi_sdi3 = 1'b0;

  initial HCLK = 1'b0;
  always #(CLK_PERIOD/2) HCLK = ~HCLK;

  // -----------------------------------------------------------------------
  // SPI Slave BFM Tasks
  // Drives spi_sdi1 MSB-first on negedge spi_clk; DUT samples on posedge.
  // -----------------------------------------------------------------------
  task automatic spi_inject_word(input logic [31:0] word);
    int i;
    begin
      spi_sdi1 = 1'b0;
      wait (spi_csn0 === 1'b0);
      spi_sdi1 = word[31];
      for (i = 30; i >= 0; i--) begin
        @(negedge spi_clk); //change afterwards for PD
        spi_sdi1 = word[i];
      end
      wait (spi_csn0 === 1'b1);
      spi_sdi1 = 1'b0;
    end
  endtask

  task automatic spi_inject_burst(
    input logic [31:0] w0, w1, w2, w3, input int num_words
  );
    logic [31:0] words [0:3];
    int w, i;
    begin
      words[0]=w0; words[1]=w1; words[2]=w2; words[3]=w3;
      spi_sdi1 = 1'b0;
      wait (spi_csn0 === 1'b0);
      spi_sdi1 = words[0][31];
      for (w = 0; w < num_words; w++)
        for (i = (w==0 ? 30 : 31); i >= 0; i--) begin
          @(negedge spi_clk);
          spi_sdi1 = words[w][i];
        end
      wait (spi_csn0 === 1'b1);
      spi_sdi1 = 1'b0;
    end
  endtask

  // Dynamic-length burst — used for overflow testing where N varies.
  task automatic spi_inject_burst_n(input logic [31:0] words[]);
    int w, i;
    begin
      spi_sdi1 = 1'b0;
      wait (spi_csn0 === 1'b0);
      spi_sdi1 = words[0][31];
      for (w = 0; w < words.size(); w++)
        for (i = (w==0 ? 30 : 31); i >= 0; i--) begin
          @(negedge spi_clk);
          spi_sdi1 = words[w][i];
        end
      wait (spi_csn0 === 1'b1);
      spi_sdi1 = 1'b0;
    end
  endtask

  // -----------------------------------------------------------------------
  // APB Helper Tasks
  // -----------------------------------------------------------------------
  task automatic cfg_spi(
    input logic [7:0]  clk_div,
    input logic [31:0] cmd_val,
    input logic [5:0]  cmd_bits,
    input logic [31:0] adr_val,
    input logic [5:0]  adr_bits,
    input logic [15:0] data_bits,
    input logic [15:0] dum_rd, dum_wr
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
    u_apb_bfm.apb_write(reg_addr(REG_STATUS), {20'h0, cs, 4'h0, 4'b0001});
  endtask

  task automatic core_read_rx(output logic [31:0] data);
    u_apb_bfm.apb_read(reg_addr(REG_RXFIFO), data);
  endtask

  task automatic read_status(output logic [31:0] data);
    u_apb_bfm.apb_read(reg_addr(REG_STATUS), data);
  endtask

  task automatic wait_eot(input int timeout_cycles = 10000);
    int cnt;
    begin
      cnt = 0;
      while ((dut.s_eot !== 1'b1) && (cnt < timeout_cycles)) begin
        @(posedge HCLK); cnt++;
      end
      if (cnt >= timeout_cycles)
        $display("  [TIMEOUT] EOT not seen after %0d cycles", timeout_cycles);
      else
        $display("  [EOT] after %0d cycles", cnt);
      @(posedge HCLK);
    end
  endtask

  // -----------------------------------------------------------------------
  // Checker — prints got/expected inline, no separate counters
  // -----------------------------------------------------------------------
  task automatic check(
    input string       msg,
    input logic [31:0] got,
    input logic [31:0] exp,
    input logic [31:0] mask = 32'hFFFF_FFFF
  );
    if ((got & mask) === (exp & mask))
      $display("  [PASS] %-45s  got=0x%08X  exp=0x%08X", msg, got, exp);
    else
      $display("  [FAIL] %-45s  got=0x%08X  exp=0x%08X", msg, got, exp);
  endtask

  // -----------------------------------------------------------------------
  // RX/TX overflow monitors — edge-detected to log each event exactly once
  // -----------------------------------------------------------------------
  int rx_overflow_cnt = 0;
  int tx_overflow_cnt = 0;

  initial begin
    logic rx_stall, rx_stall_d, tx_stall, tx_stall_d;
    rx_stall_d = 0; tx_stall_d = 0;
    fork
      forever begin
        @(posedge HCLK);
        rx_stall = dut.u_rxfifo.full && dut.spi_ctrl_data_rx_valid &&
                   !(dut.u_rxfifo.ready_i && dut.u_rxfifo.valid_o);
        if (rx_stall && !rx_stall_d) begin
          rx_overflow_cnt++;
          $display("  [WARNING] RX FIFO OVERFLOW #%0d at %0t — word 0x%08X",
                   rx_overflow_cnt, $time, dut.spi_ctrl_data_rx);
        end
        rx_stall_d = rx_stall;
      end
      forever begin
        @(posedge HCLK);
        tx_stall = dut.u_txfifo.full && dut.spi_data_tx_valid &&
                   !(dut.u_txfifo.ready_i && dut.u_txfifo.valid_o);
        if (tx_stall && !tx_stall_d) begin
          tx_overflow_cnt++;
          $display("  [WARNING] TX FIFO OVERFLOW #%0d at %0t — word 0x%08X",
                   tx_overflow_cnt, $time, dut.spi_data_tx);
        end
        tx_stall_d = tx_stall;
      end
    join_none
  end

  // =======================================================================
  // Main Test Sequence
  // =======================================================================
  logic [31:0] rx_word, status_word;

  initial begin
    HRESETn = 1'b0;
    u_apb_bfm.idle_bus();
    spi_sdi1 = 1'b0;
    repeat (5) @(posedge HCLK);
    HRESETn = 1'b1;
    repeat (5) @(posedge HCLK);

    $display("================================================================");
    $display("  RISC-V SPI Instruction Injection — BFM Testbench");
    $display("  DUT: apb_spi_master  |  Path: SPI BFM -> RX FIFO -> APB");
    $display("================================================================");

    // ================================================================
    // TC1: Single instruction inject
    //   Inject NOP via SPI, verify it lands in FIFO, read back via APB.
    // ================================================================
    $display("\n--- TC1: Single Instruction Inject (NOP) ---");
    cfg_spi(8'd4, 32'h0, 6'd0, 32'h0, 6'd0, 16'd32, 16'd0, 16'd0);
    fork
      spi_inject_word(RISCV_NOP);
      begin trigger_read(); wait_eot(); end
    join
    $display("  FIFO elements=%0d  buffer[0]=0x%08X",
             dut.u_rxfifo.elements, dut.u_rxfifo.buffer[0]);
    check("TC1: FIFO fill level",      {28'h0, dut.u_rxfifo.elements}, 32'h1, 32'hF);
    core_read_rx(rx_word);	
    check("TC1: NOP readback via APB", rx_word, RISCV_NOP);
    $display("  FIFO elements after read=%0d", dut.u_rxfifo.elements);

    // ================================================================
    // TC2: Sequential 4-instruction load
    //   Each instruction is a separate SPI transaction, drained after each.
    // ================================================================
    $display("\n--- TC2: Sequential 4-Instruction Load ---");
    begin
      logic [31:0] instr [0:3];
      string       names [0:3];
      int k;
      instr[0]=RISCV_ADDI_X1; names[0]="addi x1,x0,5 ";
      instr[1]=RISCV_ADDI_X2; names[1]="addi x2,x0,10";
      instr[2]=RISCV_ADD_X3;  names[2]="add  x3,x1,x2";
      instr[3]=RISCV_SW_X3;   names[3]="sw   x3,0(x0)";
      for (k = 0; k < 4; k++) begin
        cfg_spi(8'd4, 32'h0, 6'd0, 32'h0, 6'd0, 16'd32, 16'd0, 16'd0);
        fork
          spi_inject_word(instr[k]);
          begin trigger_read(); wait_eot(); end
        join
        core_read_rx(rx_word);
        check($sformatf("TC2[%0d]: %s", k, names[k]), rx_word, instr[k]);
      end
    end

    // ================================================================
    // TC3: 128-bit burst (4 words, single CSN assertion)
    //   RX module segments every 32 bits; all 4 appear in FIFO in order.
    // ================================================================
    $display("\n--- TC3: Burst Inject (4x32b, single 128-bit transaction) ---");
    cfg_spi(8'd4, 32'h0, 6'd0, 32'h0, 6'd0, 16'd128, 16'd0, 16'd0);
    fork
      spi_inject_burst(RISCV_ADDI_X1, RISCV_ADDI_X2, RISCV_ADD_X3, RISCV_SW_X3, 4);
      begin trigger_read(); wait_eot(); end
    join
    $display("  FIFO elements=%0d (expect 4)", dut.u_rxfifo.elements);
    check("TC3: FIFO has 4 entries", {28'h0, dut.u_rxfifo.elements}, 32'h4, 32'hF);
    core_read_rx(rx_word); check("TC3: Word[0] addi x1", rx_word, RISCV_ADDI_X1);
    core_read_rx(rx_word); check("TC3: Word[1] addi x2", rx_word, RISCV_ADDI_X2);
    core_read_rx(rx_word); check("TC3: Word[2] add  x3", rx_word, RISCV_ADD_X3);
    core_read_rx(rx_word); check("TC3: Word[3] sw   x3", rx_word, RISCV_SW_X3);
    $display("  FIFO elements after drain=%0d", dut.u_rxfifo.elements);

    // ================================================================
    // TC4: APB protocol validation
    //   Inject 0xFEEDC0DE, log the APB signals on readback.
    //   Confirms PRDATA integrity, PREADY=1 (immediate), PSLVERR=0.
    // ================================================================
    $display("\n--- TC4: APB Transaction Validation ---");
    cfg_spi(8'd4, 32'h0, 6'd0, 32'h0, 6'd0, 16'd32, 16'd0, 16'd0);
    fork
      spi_inject_word(32'hFEEDC0DE);
      begin trigger_read(); wait_eot(); end
    join
    core_read_rx(rx_word);
    $display("  REG_RXFIFO=0x%03X  PRDATA=0x%08X  PREADY=%b  PSLVERR=%b",
             reg_addr(REG_RXFIFO), rx_word, PREADY, PSLVERR);
    check("TC4: PRDATA integrity",       rx_word,      32'hFEEDC0DE);
    read_status(status_word);
    check("TC4: Controller IDLE",        status_word,  32'h1, 32'h7F);

    // ================================================================
    // TC5: RX FIFO overflow / backpressure stall
    //   Send 16 words into a depth-10 FIFO.
    //   Once full, the valid/ready handshake backpressures the SPI
    //   controller which stalls spi_clk — a protocol deadlock.
    //   Recovery: drain via APB, controller resumes and finishes.
    // ================================================================
    $display("\n--- TC5: RX FIFO Overflow / Backpressure Stall ---");
    begin
      localparam int N_WORDS      = 16;
      localparam int QUIET_CYCLES = 500;
      logic [31:0] words [N_WORDS];
      int          j, overflow_before, elements_before_stall;
      bit          stalled;

      for (j = 0; j < N_WORDS; j++) words[j] = 32'hA000_0000 + j;
      overflow_before = rx_overflow_cnt;
      stalled         = 1'b0;

      $display("  Sending %0d words into depth-%0d FIFO — expect stall at word %0d",
               N_WORDS, BUFFER_DEPTH, BUFFER_DEPTH);

      cfg_spi(8'd4, 32'h0, 6'd0, 32'h0, 6'd0, 16'(N_WORDS*32), 16'd0, 16'd0);

      // BFM launched as background thread; trigger_read fires CSN to unblock it.
      fork spi_inject_burst_n(words); join_none
      trigger_read();

      // Race: stall detector vs EOT — whichever fires first wins.
      fork
        begin : eot_waiter   wait_eot(20000); end
        begin : stall_detector
          int quiet_cnt; quiet_cnt = 0;
          forever begin
            @(posedge HCLK);
            if (dut.u_rxfifo.elements == BUFFER_DEPTH) quiet_cnt++;
            else quiet_cnt = 0;
            if (quiet_cnt >= QUIET_CYCLES) begin
              stalled = 1'b1;
              $display("  FIFO pinned at %0d for %0d cycles — stall confirmed",
                       BUFFER_DEPTH, QUIET_CYCLES);
              break;
            end
          end
        end
      join_any
      disable fork;
      spi_sdi1 = 1'b0;

      elements_before_stall = dut.u_rxfifo.elements;
      $display("  FIFO elements at stall=%0d  overflow events=%0d",
               elements_before_stall, rx_overflow_cnt - overflow_before);
      check("TC5: FIFO fills to BUFFER_DEPTH", {28'h0,elements_before_stall}, 32'(BUFFER_DEPTH), 32'hF);
      check("TC5: SPI clock stalled",          stalled ? 32'h1 : 32'h0,       32'h1);

      // Drain the stalled FIFO — releases backpressure, controller resumes.
      $display("  Draining FIFO to release stall...");
      for (j = 0; j < BUFFER_DEPTH; j++) begin
        core_read_rx(rx_word);
        check($sformatf("TC5: drained[%0d]", j), rx_word, words[j]);
      end
      wait_eot(20000);

      // Controller may push residual words after drain — flush silently.
      begin : tc5_flush
        int flush_cnt; flush_cnt = 0;
        while (dut.u_rxfifo.elements > 0) begin
          core_read_rx(rx_word);
          $display("  [FLUSH] residual[%0d]=0x%08X (indeterminate post-kill)",
                   flush_cnt, rx_word);
          flush_cnt++;
        end
        $display("  FIFO clear after flush (%0d residual words drained)", flush_cnt);
      end
    end

// ================================================================
    // TC6: Empty FIFO PREADY Stall & Recovery Test
    //   1. Command SPI to start a transaction.
    //   2. Immediately read RX FIFO before data arrives (bus stalls).
    //   3. Observer confirms PREADY is 0.
    //   4. SPI finishes shifting, FIFO fills, PREADY goes high, read completes.
    // ================================================================
    $display("\n--- TC6: Empty FIFO PREADY Stall & Recovery Test ---");
    begin : tc6
      logic [31:0] delayed_read_val;

      $display("  FIFO empty: elements=%0d. Initiating SPI transaction...", dut.u_rxfifo.elements);

      // Configure SPI
      cfg_spi(8'd4, 32'h0, 6'd0, 32'h0, 6'd0, 16'd32, 16'd0, 16'd0);

      fork
        // THREAD 1: SPI Slave BFM (Waits for CSN to drop, then shifts data)
        begin
          spi_inject_word(RISCV_NOP);
        end

        // THREAD 2: APB Operations
        begin
          // 1. Send APB command to start the SPI Master
          trigger_read(); 
          
          // 2. Immediately try to read the RX FIFO. 
          // The SPI transaction takes hundreds of cycles, so the FIFO is currently empty.
          // This read will correctly stall waiting for PREADY=1.
          $display("  [APB BFM] Initiating early read. Bus should stall...");
          core_read_rx(delayed_read_val);
          $display("  [APB BFM] PREADY went high! Read completed with PRDATA=0x%08X", delayed_read_val);
        end

        // THREAD 3: Observer
        begin
          // Wait 15 clock cycles to let Thread 2 finish the trigger and enter the read stall
          repeat(15) @(posedge HCLK);

          // PROVE THAT PREADY IS 0
          $display("  [OBSERVER] Checking bus... PREADY is currently: %b", PREADY);
          if (PREADY === 1'b0)
            $display("  [OBSERVER] SUCCESS: Read is stalled, wait-states are active.");
          else
            $display("  [OBSERVER] FAIL: PREADY should be 0!");
        end
      join

      wait_eot(); // Ensure SPI controller goes back to IDLE
      check("TC6: PREADY Recovery Test (Data Match)", delayed_read_val, RISCV_NOP);
    end


    $display("\n================================================================");
    $display("  Simulation complete");
    $display("================================================================\n");
    #100; $finish;
  end

  initial begin
    #250_000;
    $display("[WATCHDOG] Timeout — simulation hung");
    $finish;
  end

  initial begin
    $shm_open("tb_spi_bfm.shm");
    $shm_probe(tb_apb_spi_master_bfm,            "AS");
    $shm_probe(tb_apb_spi_master_bfm.dut.u_txfifo, "AM");
    $shm_probe(tb_apb_spi_master_bfm.dut.u_rxfifo, "AM");
  end

endmodule