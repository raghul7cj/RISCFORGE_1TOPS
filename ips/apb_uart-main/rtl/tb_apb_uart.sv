// =============================================================================
// Testbench: tb_apb_uart
// DUT      : apb_uart (apb_uart.sv)
// Covers   : APB protocol compliance, UART 16550 register map (THR/RBR/IER/IIR/
//            LCR/MCR/LSR/MSR/DLL/DLM/FCR/SCR), TX serialisation, RX de-
//            serialisation, loopback (MCR LOOP bit), interrupt assertion,
//            modem-signal pass-through, and reset behaviour.
//
// NOTE: This testbench is self-contained and does NOT require apb/typedef.svh
//       or obi/typedef.svh at the TB level – it drives the flat APB ports of
//       apb_uart directly.  The DUT itself still needs those headers resolved
//       by your compile script.
//
// Simulator: works with Questa / VCS / Xcelium.
// Compile example (Questa):
//   vlog -sv apb_uart.sv apb_uart_wrap.sv reg_uart_wrap.sv tb_apb_uart.sv \
//        +incdir+<path_to_apb_headers> +incdir+<path_to_obi_headers>
//   vsim -t 1ns tb_apb_uart
// =============================================================================

`timescale 1ns/1ps

module tb_apb_uart;

  // ---------------------------------------------------------------------------
  // Parameters
  // ---------------------------------------------------------------------------
  localparam int CLK_PERIOD   = 10;   // 100 MHz system clock
  localparam int APB_SETUP    = 1;    // setup-phase cycles
  localparam int TIMEOUT_CYC  = 50000;

  // 16550 register addresses (PADDR[2:0], byte-addressed ×4 inside DUT)
  localparam logic [2:0] ADDR_THR_RBR = 3'h0; // TX Holding / RX Buffer (DLAB=0)
  localparam logic [2:0] ADDR_IER     = 3'h1; // Interrupt Enable       (DLAB=0)
  localparam logic [2:0] ADDR_IIR_FCR = 3'h2; // IIR(rd) / FCR(wr)
  localparam logic [2:0] ADDR_LCR     = 3'h3; // Line Control
  localparam logic [2:0] ADDR_MCR     = 3'h4; // Modem Control
  localparam logic [2:0] ADDR_LSR     = 3'h5; // Line Status
  localparam logic [2:0] ADDR_MSR     = 3'h6; // Modem Status
  localparam logic [2:0] ADDR_SCR     = 3'h7; // Scratch
  // DLL/DLM share addrs 0/1 when DLAB=1

  // ---------------------------------------------------------------------------
  // DUT port signals
  // ---------------------------------------------------------------------------
  logic        CLK, RSTN;
  logic        PSEL, PENABLE, PWRITE;
  logic [2:0]  PADDR;
  logic [31:0] PWDATA;
  logic [31:0] PRDATA;
  logic        PREADY, PSLVERR;
  logic        INT;
  logic        OUT1N, OUT2N, RTSN, DTRN;
  logic        CTSN, DSRN, DCDN, RIN;
  logic        SIN, SOUT;

  // ---------------------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------------------
  apb_uart dut (
    .CLK     (CLK),
    .RSTN    (RSTN),
    .PSEL    (PSEL),
    .PENABLE (PENABLE),
    .PWRITE  (PWRITE),
    .PADDR   (PADDR),
    .PWDATA  (PWDATA),
    .PRDATA  (PRDATA),
    .PREADY  (PREADY),
    .PSLVERR (PSLVERR),
    .INT     (INT),
    .OUT1N   (OUT1N),
    .OUT2N   (OUT2N),
    .RTSN    (RTSN),
    .DTRN    (DTRN),
    .CTSN    (CTSN),
    .DSRN    (DSRN),
    .DCDN    (DCDN),
    .RIN     (RIN),
    .SIN     (SIN),
    .SOUT    (SOUT)
  );

  // ---------------------------------------------------------------------------
  // Clock generation
  // ---------------------------------------------------------------------------
  initial CLK = 1'b0;
  always  #(CLK_PERIOD/2) CLK = ~CLK;

  // ---------------------------------------------------------------------------
  // Idle / default modem inputs (active-low, so deasserted = 1)
  // ---------------------------------------------------------------------------
  initial begin
    CTSN = 1'b1;
    DSRN = 1'b1;
    DCDN = 1'b1;
    RIN  = 1'b1;
    SIN  = 1'b1; // idle serial line = HIGH
  end

  // ---------------------------------------------------------------------------
  // APB driver tasks
  // ---------------------------------------------------------------------------
  task automatic apb_write(input logic [2:0] addr,
                           input logic [31:0] data);
    @(posedge CLK);
    PSEL    <= 1'b1;
    PWRITE  <= 1'b1;
    PADDR   <= addr;
    PWDATA  <= data;
    PENABLE <= 1'b0;
    @(posedge CLK);
    PENABLE <= 1'b1;
    // Wait for PREADY (with timeout)
    fork
      begin : wait_rdy
        while (!PREADY) @(posedge CLK);
      end
      begin : timeout_guard
        repeat(TIMEOUT_CYC) @(posedge CLK);
        $error("TIMEOUT: APB write addr=0x%0x", addr);
        disable wait_rdy;
      end
    join_any
    disable timeout_guard;
    @(posedge CLK);
    PSEL    <= 1'b0;
    PENABLE <= 1'b0;
  endtask

  task automatic apb_read(input  logic [2:0]  addr,
                          output logic [31:0] data);
    @(posedge CLK);
    PSEL    <= 1'b1;
    PWRITE  <= 1'b0;
    PADDR   <= addr;
    PWDATA  <= '0;
    PENABLE <= 1'b0;
    @(posedge CLK);
    PENABLE <= 1'b1;
    fork
      begin : wait_rdy2
        while (!PREADY) @(posedge CLK);
      end
      begin : timeout_guard2
        repeat(TIMEOUT_CYC) @(posedge CLK);
        $error("TIMEOUT: APB read addr=0x%0x", addr);
        disable wait_rdy2;
      end
    join_any
    disable timeout_guard2;
    data = PRDATA;
    @(posedge CLK);
    PSEL    <= 1'b0;
    PENABLE <= 1'b0;
  endtask

  // ---------------------------------------------------------------------------
  // Assertion helper
  // ---------------------------------------------------------------------------
  int pass_cnt = 0, fail_cnt = 0;

  task automatic check(input string msg,
                       input logic got,
                       input logic exp);
    if (got === exp) begin
      $display("[PASS] %s  (got=%0b exp=%0b)", msg, got, exp);
      pass_cnt++;
    end else begin
      $error("[FAIL] %s  (got=%0b exp=%0b)", msg, got, exp);
      fail_cnt++;
    end
  endtask

  task automatic check_val(input string msg,
                           input logic [31:0] got,
                           input logic [31:0] exp,
                           input logic [31:0] mask = 32'hFFFF_FFFF);
    if ((got & mask) === (exp & mask)) begin
      $display("[PASS] %s  (got=0x%08X exp=0x%08X mask=0x%08X)", msg, got, exp, mask);
      pass_cnt++;
    end else begin
      $error("[FAIL] %s  (got=0x%08X exp=0x%08X mask=0x%08X)", msg, got, exp, mask);
      fail_cnt++;
    end
  endtask

  // ---------------------------------------------------------------------------
  // UART serial-send task  (bit-bangs SIN at the configured baud rate)
  // We read the divisor latch to determine bit period in clock cycles.
  // ---------------------------------------------------------------------------
  logic [15:0] divisor;

  task automatic uart_send_byte(input logic [7:0] data,
                                input int          data_bits  = 8,
                                input logic        parity_en  = 1'b0,
                                input logic        parity_odd = 1'b0,
                                input int          stop_bits  = 1);
    automatic int bit_period;
    automatic logic parity_bit;
    automatic int i;
    bit_period = (divisor == 0) ? 16 : divisor * 16; // divisor * 16 clocks per bit
    parity_bit = parity_odd ? ~^data[data_bits-1:0] : ^data[data_bits-1:0];

    // Start bit
    SIN = 1'b0;
    repeat(bit_period) @(posedge CLK);

    // Data bits (LSB first)
    for (i = 0; i < data_bits; i++) begin
      SIN = data[i];
      repeat(bit_period) @(posedge CLK);
    end

    // Optional parity
    if (parity_en) begin
      SIN = parity_bit;
      repeat(bit_period) @(posedge CLK);
    end

    // Stop bit(s)
    SIN = 1'b1;
    repeat(bit_period * stop_bits) @(posedge CLK);
  endtask

  // ---------------------------------------------------------------------------
  // UART serial-capture task  (samples SOUT at the configured baud rate)
  // ---------------------------------------------------------------------------
  task automatic uart_recv_byte(output logic [7:0] data,
                                input  int          data_bits = 8,
                                input  logic        parity_en = 1'b0,
                                input  int          stop_bits = 1);
    automatic int bit_period;
    automatic int half_period;
    automatic int i;
    bit_period  = (divisor == 0) ? 16 : divisor * 16;
    half_period = bit_period / 2;
    data = '0;

    // Wait for start bit (falling edge on SOUT)
    @(negedge SOUT);

    // Sample mid-start-bit to confirm
    repeat(half_period) @(posedge CLK);
    if (SOUT !== 1'b0) begin
      $error("[FAIL] uart_recv_byte: start bit not low"); fail_cnt++;
    end

    // Sample data bits
    for (i = 0; i < data_bits; i++) begin
      repeat(bit_period) @(posedge CLK);
      data[i] = SOUT;
    end

    // Skip parity
    if (parity_en)
      repeat(bit_period) @(posedge CLK);

    // Stop bit
    repeat(bit_period) @(posedge CLK);
    if (SOUT !== 1'b1) begin
      $error("[FAIL] uart_recv_byte: stop bit not high"); fail_cnt++;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Main test sequence
  // ---------------------------------------------------------------------------
  logic [31:0] rdata;

  initial begin
    // -------------------------------------------------------------------------
    // 0. Initialise APB bus
    // -------------------------------------------------------------------------
    PSEL    = 0; PENABLE = 0; PWRITE = 0;
    PADDR   = '0; PWDATA = '0;

    // -------------------------------------------------------------------------
    // 1. Reset
    // -------------------------------------------------------------------------
    RSTN = 1'b0;
    repeat(5) @(posedge CLK);
    RSTN = 1'b1;
    repeat(5) @(posedge CLK);
    $display("\n=== TEST 1: Reset ===");
    check("SOUT idle-high after reset", SOUT, 1'b1);
    check("INT deasserted after reset", INT,  1'b0);

    // -------------------------------------------------------------------------
    // 2. APB write then read – Scratch Register (SCR) round-trip
    // -------------------------------------------------------------------------
    $display("\n=== TEST 2: APB write/read – Scratch Register ===");
    apb_write(ADDR_SCR, 32'hA5);
    apb_read (ADDR_SCR, rdata);
    check_val("SCR write-read round-trip", rdata, 32'hA5);

    apb_write(ADDR_SCR, 32'h5A);
    apb_read (ADDR_SCR, rdata);
    check_val("SCR write-read round-trip (inv)", rdata, 32'h5A);

    // -------------------------------------------------------------------------
    // 3. APB protocol: PSLVERR should be 0 for valid accesses
    // -------------------------------------------------------------------------
    $display("\n=== TEST 3: APB PSLVERR ===");
    apb_read(ADDR_LSR, rdata);
    check("PSLVERR deasserted on valid read", PSLVERR, 1'b0);

    // -------------------------------------------------------------------------
    // 4. DLAB = 1: program DLL/DLM divisor  (baudrate = clk / (16 × divisor))
    //    Use divisor = 4 → baud = 100MHz / 64 ≈ 1.5625 Mbaud (fast for sim)
    // -------------------------------------------------------------------------
    $display("\n=== TEST 4: Divisor Latch (DLL/DLM) ===");
    apb_write(ADDR_LCR, 32'h83);  // DLAB=1, 8N1
    apb_write(ADDR_THR_RBR, 32'h04); // DLL = 4
    apb_write(ADDR_IER,     32'h00); // DLM = 0
    divisor = 16'h0004;
    apb_write(ADDR_LCR, 32'h03);  // DLAB=0, 8N1
    apb_read (ADDR_LCR, rdata);
    check_val("LCR = 0x03 (8N1, DLAB=0)", rdata, 32'h03, 32'hFF);

    // -------------------------------------------------------------------------
    // 5. TX: write a byte to THR, capture on SOUT
    // -------------------------------------------------------------------------
    $display("\n=== TEST 5: TX – write byte to THR ===");
    begin
      automatic logic [7:0] tx_byte = 8'hA5;
      automatic logic [7:0] rx_cap;
      fork
        begin
          apb_write(ADDR_THR_RBR, {24'h0, tx_byte});
        end
        begin
          uart_recv_byte(rx_cap, 8, 1'b0, 1);
        end
      join
      check_val("SOUT captures TX byte 0xA5", {24'h0, rx_cap}, {24'h0, tx_byte});
    end

    // LSR THRE (bit5) should eventually go high
    begin
      automatic int timeout_cnt = 0;
      do begin
        apb_read(ADDR_LSR, rdata);
        @(posedge CLK);
        timeout_cnt++;
      end while (!rdata[5] && timeout_cnt < TIMEOUT_CYC);
      check("LSR.THRE set after TX", rdata[5], 1'b1);
    end

    // -------------------------------------------------------------------------
    // 6. RX: drive SIN with a known byte, read RBR
    // -------------------------------------------------------------------------
    $display("\n=== TEST 6: RX – drive SIN, read RBR ===");
    begin
      automatic logic [7:0] rx_byte = 8'h3C;
      automatic logic [31:0] rbr_data;
      automatic int timeout_cnt;
      uart_send_byte(rx_byte, 8, 1'b0, 1'b0, 1);
      // Wait for DR (bit0 of LSR)
      timeout_cnt = 0;
      do begin
        apb_read(ADDR_LSR, rdata);
        @(posedge CLK);
        timeout_cnt++;
      end while (!rdata[0] && timeout_cnt < TIMEOUT_CYC);
      check("LSR.DR set after RX", rdata[0], 1'b1);
      apb_read(ADDR_THR_RBR, rbr_data);
      check_val("RBR contains received byte 0x3C", rbr_data, {24'h0, rx_byte}, 32'hFF);
    end

    // -------------------------------------------------------------------------
    // 7. Interrupt: enable RDA interrupt, send a byte, check INT
    // -------------------------------------------------------------------------
    $display("\n=== TEST 7: Interrupt – RDA ===");
    apb_write(ADDR_IER, 32'h01); // enable Received Data Available interrupt
    uart_send_byte(8'hBE, 8, 1'b0, 1'b0, 1);
    begin
      automatic int tc = 0;
      while (!INT && tc < TIMEOUT_CYC) begin
        @(posedge CLK); tc++;
      end
      check("INT asserted on RDA", INT, 1'b1);
    end
    // Read IIR – should indicate RDA (IIR[3:1] = 3'b010)
    apb_read(ADDR_IIR_FCR, rdata);
    check_val("IIR shows RDA interrupt", rdata, 32'h04, 32'h0F);
    // Clear interrupt by reading RBR
    apb_read(ADDR_THR_RBR, rdata);
    repeat(4) @(posedge CLK);
    check("INT deasserted after RBR read", INT, 1'b0);
    // Disable RDA interrupt
    apb_write(ADDR_IER, 32'h00);

    // -------------------------------------------------------------------------
    // 8. Loopback mode (MCR bit4): TX→RX internally
    // -------------------------------------------------------------------------
    $display("\n=== TEST 8: MCR Loopback ===");
    apb_write(ADDR_MCR, 32'h10); // LOOP=1
    begin
      automatic logic [7:0] loop_byte = 8'hF0;
      automatic logic [31:0] rbr_data;
      automatic int tc;
      apb_write(ADDR_THR_RBR, {24'h0, loop_byte});
      // Wait for DR
      tc = 0;
      do begin
        apb_read(ADDR_LSR, rdata);
        @(posedge CLK); tc++;
      end while (!rdata[0] && tc < TIMEOUT_CYC);
      check("LSR.DR set in loopback", rdata[0], 1'b1);
      apb_read(ADDR_THR_RBR, rbr_data);
      check_val("RBR matches loopback TX byte 0xF0", rbr_data, {24'h0, loop_byte}, 32'hFF);
    end
    apb_write(ADDR_MCR, 32'h00); // LOOP=0

    // -------------------------------------------------------------------------
    // 9. Modem signals: MCR RTS/DTR → MSR CTS/DSR in loopback
    // -------------------------------------------------------------------------
    $display("\n=== TEST 9: MCR RTS/DTR → MSR in loopback ===");
    apb_write(ADDR_MCR, 32'h13); // LOOP=1, RTS=1, DTR=1
    apb_read (ADDR_MSR, rdata);
    // In loopback: CTS=RTS, DSR=DTR reflected; active-low inverted.
    // MSR bit0=DCTS(delta), bit4=CTS, bit5=DSR.
    check_val("MSR CTS bit reflects MCR RTS in loopback", rdata, 32'h30, 32'h30);
    apb_write(ADDR_MCR, 32'h10); // LOOP=1, RTS=0, DTR=0
    apb_read (ADDR_MSR, rdata);
    check_val("MSR CTS/DSR clear when MCR RTS/DTR=0", rdata, 32'h00, 32'h30);
    apb_write(ADDR_MCR, 32'h00);

    // -------------------------------------------------------------------------
    // 10. Physical modem inputs: drive CTSN/DSRN
    // -------------------------------------------------------------------------
    $display("\n=== TEST 10: Physical modem inputs ===");
    CTSN = 1'b0; DSRN = 1'b0; // assert CTS/DSR
    repeat(4) @(posedge CLK);
    apb_read(ADDR_MSR, rdata);
    check_val("MSR reflects asserted CTSN/DSRN", rdata, 32'h30, 32'h30);
    CTSN = 1'b1; DSRN = 1'b1;
    repeat(4) @(posedge CLK);

    // -------------------------------------------------------------------------
    // 11. LCR parity modes (even / odd) – verify LCR readback
    // -------------------------------------------------------------------------
    $display("\n=== TEST 11: LCR parity configuration ===");
    apb_write(ADDR_LCR, 32'h1B); // 8E1 (even parity)
    apb_read (ADDR_LCR, rdata);
    check_val("LCR 8E1", rdata, 32'h1B, 32'hFF);

    apb_write(ADDR_LCR, 32'h0B); // 8O1 (odd parity)
    apb_read (ADDR_LCR, rdata);
    check_val("LCR 8O1", rdata, 32'h0B, 32'hFF);

    apb_write(ADDR_LCR, 32'h03); // back to 8N1
    apb_read (ADDR_LCR, rdata);
    check_val("LCR 8N1 restored", rdata, 32'h03, 32'hFF);

    // -------------------------------------------------------------------------
    // 12. FCR FIFO enable (write-only IIR bit0 indicates FIFO state)
    // -------------------------------------------------------------------------
    $display("\n=== TEST 12: FCR FIFO enable ===");
    apb_write(ADDR_IIR_FCR, 32'h01); // enable FIFO
    apb_read (ADDR_IIR_FCR, rdata);  // read IIR
    check_val("IIR[7:6]=11 when FIFOs enabled", rdata, 32'hC0, 32'hC0);

    // -------------------------------------------------------------------------
    // 13. TX FIFO: write multiple bytes in loopback
    // -------------------------------------------------------------------------
    $display("\n=== TEST 13: TX FIFO burst in loopback ===");
    apb_write(ADDR_MCR, 32'h10); // LOOP=1
    begin
      automatic logic [7:0] burst [3] = '{8'h11, 8'h22, 8'h33};
      automatic logic [31:0] rbr_data;
      automatic int tc;
      for (int k = 0; k < 3; k++)
        apb_write(ADDR_THR_RBR, {24'h0, burst[k]});
      for (int k = 0; k < 3; k++) begin
        tc = 0;
        do begin
          apb_read(ADDR_LSR, rdata);
          @(posedge CLK); tc++;
        end while (!rdata[0] && tc < TIMEOUT_CYC);
        apb_read(ADDR_THR_RBR, rbr_data);
        check_val($sformatf("FIFO loopback byte[%0d]", k),
                  rbr_data, {24'h0, burst[k]}, 32'hFF);
      end
    end
    apb_write(ADDR_MCR, 32'h00);

    // -------------------------------------------------------------------------
    // 14. TX-empty interrupt (IER bit1)
    // -------------------------------------------------------------------------
    $display("\n=== TEST 14: THRE interrupt ===");
    apb_write(ADDR_IER, 32'h02); // ETBEI: enable TX Holding Register Empty intr
    begin
      automatic int tc = 0;
      while (!INT && tc < TIMEOUT_CYC) begin
        @(posedge CLK); tc++;
      end
      check("INT asserted on THRE", INT, 1'b1);
    end
    apb_read(ADDR_IIR_FCR, rdata);
    check_val("IIR shows THRE interrupt (IIR[3:1]=001)", rdata, 32'h02, 32'h0F);
    apb_write(ADDR_IER, 32'h00);

    // -------------------------------------------------------------------------
    // 15. Reset clears registers
    // -------------------------------------------------------------------------
    $display("\n=== TEST 15: Re-reset clears state ===");
    apb_write(ADDR_SCR, 32'hFF);
    apb_write(ADDR_IER, 32'h0F);
    RSTN = 1'b0;
    repeat(5) @(posedge CLK);
    RSTN = 1'b1;
    repeat(5) @(posedge CLK);
    apb_read(ADDR_IER, rdata);
    check_val("IER cleared after reset", rdata, 32'h00, 32'hFF);
    check("INT deasserted after reset", INT, 1'b0);
    check("SOUT idle-high after reset", SOUT, 1'b1);

    // -------------------------------------------------------------------------
    // Summary
    // -------------------------------------------------------------------------
    $display("\n========================================");
    $display(" TEST SUMMARY: %0d PASSED, %0d FAILED", pass_cnt, fail_cnt);
    $display("========================================\n");

    if (fail_cnt == 0)
      $display("ALL TESTS PASSED");
    else
      $display("SOME TESTS FAILED – review log above");

    $finish;
  end

  // ---------------------------------------------------------------------------
  // Simulation watchdog
  // ---------------------------------------------------------------------------
  initial begin
    #(CLK_PERIOD * 2_000_000);
    $error("Global simulation watchdog expired!");
    $finish;
  end

  // ---------------------------------------------------------------------------
  // Concurrent APB protocol assertions (SVA)
  // ---------------------------------------------------------------------------
  // Rule: PENABLE must follow exactly one cycle after PSEL asserts
  property apb_enable_follows_sel;
    @(posedge CLK) disable iff (!RSTN)
      (PSEL && !PENABLE) |=> PENABLE;
  endproperty
  assert property (apb_enable_follows_sel)
    else $error("[SVA] PENABLE did not follow PSEL by one cycle");

  // Rule: addr/data/write must be stable during ENABLE phase
  property apb_addr_stable;
    @(posedge CLK) disable iff (!RSTN)
      (PSEL && PENABLE) |-> $stable(PADDR);
  endproperty
  assert property (apb_addr_stable)
    else $error("[SVA] PADDR changed during ENABLE phase");

  property apb_wdata_stable;
    @(posedge CLK) disable iff (!RSTN)
      (PSEL && PENABLE && PWRITE) |-> $stable(PWDATA);
  endproperty
  assert property (apb_wdata_stable)
    else $error("[SVA] PWDATA changed during ENABLE phase");

  // Rule: PREADY must eventually be asserted (no deadlock)
  property apb_no_stall;
    @(posedge CLK) disable iff (!RSTN)
      (PSEL && PENABLE && !PREADY) |-> ##[1:16] PREADY;
  endproperty
  assert property (apb_no_stall)
    else $error("[SVA] APB stall exceeded 16 cycles");

  // Rule: SOUT stays high when THRE & no TX in progress (idle line check)
  property sout_idle_high;
    @(posedge CLK) disable iff (!RSTN)
      (!PSEL) |-> (SOUT === 1'b1 || SOUT === 1'b0); // only range-check, not X/Z
  endproperty
  assert property (sout_idle_high)
    else $error("[SVA] SOUT driven to X/Z");

  // ---------------------------------------------------------------------------
  // VCD dump (comment out if not needed)
  // ---------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_apb_uart.vcd");
    $dumpvars(0, tb_apb_uart);
  end

endmodule
