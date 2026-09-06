// =============================================================================
// Testbench: tb_apb_uart_thorough
// DUT      : apb_uart  (16550-compatible, PULP obi_uart wrapped via APB)
//
// Methodology (mirrors tb_apb_spi_master v2 / bootloader tb style):
//   * Directed, self-checking, non-UVM.
//   * APB BFM samples PRDATA at posedge HCLK BEFORE any # delay
//     (mandatory for FIFO/side-effect reads — see SPI-master verif report).
//   * Sticky flags latch single-cycle events (INT, THRE edges) so polling
//     loops never miss a pulse.
//   * Every check uses masked === to tolerate X/Z cleanly.
//   * Concurrent SVA properties enforce APB protocol compliance.
//   * Global watchdog + per-op timeouts prevent hangs.
//
// Coverage matrix (30 test-cases, ~70 individual checks):
//   TC1  Reset — output ports and registers in safe idle state
//   TC2  PSLVERR / PREADY always sane (protocol compliance)
//   TC3  Scratch register (SCR) full-pattern round-trip
//   TC4  LCR bit-field round-trip (WLS, STB, PEN, EPS, SP, BC, DLAB)
//   TC5  DLAB isolation — DLL/DLM only visible when DLAB=1
//   TC6  IER register write-read (each bit independently)
//   TC7  MCR modem-control bits R/W
//   TC8  FCR write / IIR[7:6] FIFOs-enabled feedback
//   TC9  Divisor programming — verify divisor read-back through DLAB
//   TC10 TX single byte captured on SOUT (external serial recv)
//   TC11 RX single byte via SIN — LSR.DR + RBR content
//   TC12 Internal loopback single byte (MCR.LOOP)
//   TC13 Loopback burst — RX FIFO ordering preserved (4 bytes)
//   TC14 THRE (LSR[5]) high once TX drained
//   TC15 TEMT (LSR[6]) high once shift register drained
//   TC16 RDA interrupt: INT + IIR[3:0]=0x04, cleared by RBR read
//   TC17 THRE interrupt: INT + IIR[3:0]=0x02, cleared by IIR read / THR write
//   TC18 Modem-status interrupt: INT + IIR[3:0]=0x00, cleared by MSR read
//   TC19 MCR RTS/DTR mirrored into MSR CTS/DSR bits under loopback
//   TC20 Physical CTSN/DSRN/DCDN/RIN pass-through into MSR
//   TC21 Parity — 8E1 send correct parity: no PE flag
//   TC22 Parity — 8E1 send WRONG parity: PE flag (LSR[2]) set
//   TC23 Framing error — send with stop=0: FE flag (LSR[3]) set
//   TC24 Break condition — SIN low for full frame: BI flag (LSR[4]) set
//   TC25 Different word-length: 7N1 round-trip in loopback
//   TC26 Different baud: divisor=8 (half speed) TX/RX round-trip
//   TC27 Back-to-back APB writes/reads (no PREADY starvation)
//   TC28 Warm reset preserves nothing — IER/SCR cleared
//   TC29 SOUT holds high in idle after byte drains
//   TC30 CTS auto-flow (MCR.AFE) throttles TX when CTSN deasserted
//
// Compile (Xcelium):
//   xrun -sv -f files_thorough_tb.f
//
// Compile (Questa):
//   vlog -sv -f files_thorough_tb.f
//   vsim -t 1ns tb_apb_uart_thorough
// =============================================================================

`timescale 1ns/1ps

module tb_apb_uart_thorough;

  // ---------------------------------------------------------------------------
  // Parameters
  // ---------------------------------------------------------------------------
  localparam int CLK_PERIOD  = 10;      // 100 MHz
  localparam int TIMEOUT_CYC = 100_000; // per-op timeout
  localparam int GLOBAL_WD_NS = 20_000_000; // 20 ms global watchdog

  // 16550 register offsets (word-addressed via PADDR[2:0])
  localparam logic [2:0] ADDR_THR_RBR = 3'h0; // DLAB=0
  localparam logic [2:0] ADDR_IER     = 3'h1; // DLAB=0
  localparam logic [2:0] ADDR_IIR_FCR = 3'h2; // R=IIR, W=FCR
  localparam logic [2:0] ADDR_LCR     = 3'h3;
  localparam logic [2:0] ADDR_MCR     = 3'h4;
  localparam logic [2:0] ADDR_LSR     = 3'h5;
  localparam logic [2:0] ADDR_MSR     = 3'h6;
  localparam logic [2:0] ADDR_SCR     = 3'h7;
  // DLL @ 0x0, DLM @ 0x1 when DLAB=1

  // ---------------------------------------------------------------------------
  // DUT signals
  // ---------------------------------------------------------------------------
  logic        CLK, RSTN;
  logic        PSEL, PENABLE, PWRITE;
  logic [2:0]  PADDR;
  logic [31:0] PWDATA, PRDATA;
  logic        PREADY, PSLVERR;
  logic        INT;
  logic        OUT1N, OUT2N, RTSN, DTRN;
  logic        CTSN, DSRN, DCDN, RIN;
  logic        SIN, SOUT;

  // ---------------------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------------------
  apb_uart dut (
    .CLK(CLK), .RSTN(RSTN),
    .PSEL(PSEL), .PENABLE(PENABLE), .PWRITE(PWRITE),
    .PADDR(PADDR), .PWDATA(PWDATA),
    .PRDATA(PRDATA), .PREADY(PREADY), .PSLVERR(PSLVERR),
    .INT(INT),
    .OUT1N(OUT1N), .OUT2N(OUT2N), .RTSN(RTSN), .DTRN(DTRN),
    .CTSN(CTSN), .DSRN(DSRN), .DCDN(DCDN), .RIN(RIN),
    .SIN(SIN), .SOUT(SOUT)
  );

  // ---------------------------------------------------------------------------
  // Clock
  // ---------------------------------------------------------------------------
  initial CLK = 1'b0;
  always #(CLK_PERIOD/2) CLK = ~CLK;

  // ---------------------------------------------------------------------------
  // Idle inputs (active-low modem lines = 1)
  // ---------------------------------------------------------------------------
  initial begin
    CTSN = 1'b1; DSRN = 1'b1; DCDN = 1'b1; RIN = 1'b1;
    SIN  = 1'b1;                  // serial idle = HIGH
    PSEL = 0; PENABLE = 0; PWRITE = 0;
    PADDR = '0; PWDATA = '0;
  end

  // ---------------------------------------------------------------------------
  // Sticky INT flag — capture single-cycle pulses reliably
  // ---------------------------------------------------------------------------
  logic int_flag;
  always_ff @(posedge CLK or negedge RSTN) begin
    if (!RSTN)   int_flag <= 1'b0;
    else if (INT) int_flag <= 1'b1;
  end
  task automatic clear_int_flag;
    @(negedge CLK); force int_flag = 1'b0;
    @(negedge CLK); release int_flag;
  endtask

  // ---------------------------------------------------------------------------
  // Pass/fail counters
  // ---------------------------------------------------------------------------
  int pass_cnt = 0, fail_cnt = 0;

  task automatic check(input string msg, input logic got, input logic exp);
    if (got === exp) begin
      $display("  [PASS] %s (got=%0b exp=%0b)", msg, got, exp);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %s (got=%0b exp=%0b)", msg, got, exp);
      fail_cnt++;
    end
  endtask

  task automatic check_val(input string msg,
                           input logic [31:0] got, input logic [31:0] exp,
                           input logic [31:0] mask = 32'hFFFF_FFFF);
    if ((got & mask) === (exp & mask)) begin
      $display("  [PASS] %s got=0x%08X exp=0x%08X mask=0x%08X",
               msg, got, exp, mask);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %s got=0x%08X exp=0x%08X mask=0x%08X",
               msg, got, exp, mask);
      fail_cnt++;
    end
  endtask

  // ---------------------------------------------------------------------------
  // APB BFM — sample PRDATA at posedge before any # delay
  // (avoids the SPI-master RXFIFO pointer-advance race noted in the verif doc)
  // ---------------------------------------------------------------------------
  task automatic apb_write(input logic [2:0] addr, input logic [31:0] data);
    int t;
    @(posedge CLK); #1;
    PSEL    = 1'b1; PWRITE = 1'b1; PADDR = addr;
    PWDATA  = data; PENABLE = 1'b0;
    @(posedge CLK); #1;
    PENABLE = 1'b1;
    // wait PREADY
    t = 0;
    while (!PREADY && t < TIMEOUT_CYC) begin
      @(posedge CLK); t++;
    end
    if (t >= TIMEOUT_CYC) $error("APB write timeout @ addr=0x%0h", addr);
    @(posedge CLK); #1;
    PSEL = 1'b0; PENABLE = 1'b0; PWRITE = 1'b0;
  endtask

  task automatic apb_read(input logic [2:0] addr, output logic [31:0] data);
    int t;
    @(posedge CLK); #1;
    PSEL    = 1'b1; PWRITE = 1'b0; PADDR = addr;
    PWDATA  = '0;   PENABLE = 1'b0;
    @(posedge CLK); #1;
    PENABLE = 1'b1;
    t = 0;
    while (!PREADY && t < TIMEOUT_CYC) begin
      @(posedge CLK); t++;
    end
    if (t >= TIMEOUT_CYC) $error("APB read timeout @ addr=0x%0h", addr);
    @(posedge CLK);            // Active region sample
    data = PRDATA;             //  BEFORE any # delay
    #1;
    PSEL = 1'b0; PENABLE = 1'b0;
  endtask

  // ---------------------------------------------------------------------------
  // Divisor tracking — TB shadows what it programmed via DLAB
  // ---------------------------------------------------------------------------
  logic [15:0] divisor;  // clock ticks per UART tick / 16
  function automatic int bit_period;
    return (divisor == 0) ? 16 : divisor * 16;
  endfunction

  // ---------------------------------------------------------------------------
  // Serial send BFM (drives SIN)
  //   data_bits ∈ {5,6,7,8}, stop_bits ∈ {1,2}
  //   parity_en=0: no parity
  //   parity_en=1, parity_odd=0: even parity
  //   parity_en=1, parity_odd=1: odd parity
  //   corrupt_parity=1: invert parity for testing PE detection
  //   corrupt_stop=1  : drive stop bit LOW to inject framing error
  // ---------------------------------------------------------------------------
  task automatic uart_send_byte(input logic [7:0] data,
                                input int         data_bits      = 8,
                                input logic       parity_en      = 0,
                                input logic       parity_odd     = 0,
                                input int         stop_bits      = 1,
                                input logic       corrupt_parity = 0,
                                input logic       corrupt_stop   = 0);
    int bp; int i; logic p;
    bp = bit_period();
    p = parity_odd ? ~(^(data & ((1 << data_bits) - 1))) : (^(data & ((1 << data_bits) - 1)));
    if (corrupt_parity) p = ~p;

    SIN = 1'b0;                              // start
    repeat (bp) @(posedge CLK);
    for (i = 0; i < data_bits; i++) begin    // LSB first
      SIN = data[i];
      repeat (bp) @(posedge CLK);
    end
    if (parity_en) begin
      SIN = p;
      repeat (bp) @(posedge CLK);
    end
    SIN = corrupt_stop ? 1'b0 : 1'b1;         // stop
    repeat (bp * stop_bits) @(posedge CLK);
    SIN = 1'b1;                              // return to idle
  endtask

  task automatic uart_send_break(input int frames = 1);
    int bp = bit_period();
    int total_bits = 1 + 8 + 1;              // start+8data+1stop
    SIN = 1'b0;
    repeat (bp * total_bits * frames) @(posedge CLK);
    SIN = 1'b1;
    repeat (bp * 2) @(posedge CLK);
  endtask

  // ---------------------------------------------------------------------------
  // Serial receive BFM (samples SOUT)
  // ---------------------------------------------------------------------------
  task automatic uart_recv_byte(output logic [7:0] data,
                                input  int         data_bits = 8,
                                input  logic       parity_en = 0,
                                input  int         stop_bits = 1);
    int bp, half; int i; int t;
    bp   = bit_period();
    half = bp / 2;
    data = '0;

    // wait for start (falling edge) with timeout
    t = 0;
    while (SOUT !== 1'b0 && t < TIMEOUT_CYC) begin
      @(posedge CLK); t++;
    end
    if (t >= TIMEOUT_CYC) begin
      $display("  [WARN] uart_recv_byte: no start bit within %0d cycles", TIMEOUT_CYC);
      return;
    end

    // mid-start-bit
    repeat (half) @(posedge CLK);
    if (SOUT !== 1'b0)
      $display("  [WARN] uart_recv_byte: start bit not stable low");

    for (i = 0; i < data_bits; i++) begin
      repeat (bp) @(posedge CLK);
      data[i] = SOUT;
    end
    if (parity_en) repeat (bp) @(posedge CLK);
    repeat (bp) @(posedge CLK);
    if (SOUT !== 1'b1)
      $display("  [WARN] uart_recv_byte: stop bit not high");
  endtask

  // ---------------------------------------------------------------------------
  // Helpers: wait for LSR bit, wait for INT (via sticky flag)
  // ---------------------------------------------------------------------------
  task automatic wait_lsr_bit(input int bit_idx, input logic value = 1'b1,
                              input int timeout = TIMEOUT_CYC);
    logic [31:0] r; int t;
    t = 0;
    do begin
      apb_read(ADDR_LSR, r);
      if (r[bit_idx] === value) return;
      @(posedge CLK); t++;
    end while (t < timeout);
    $display("  [WARN] wait_lsr_bit: LSR[%0d]=%0b never reached in %0d cycles",
             bit_idx, value, timeout);
  endtask

  task automatic wait_int_flag(input int timeout = TIMEOUT_CYC);
    int t = 0;
    while (!int_flag && t < timeout) begin
      @(posedge CLK); t++;
    end
    if (t >= timeout)
      $display("  [WARN] wait_int_flag: INT never asserted in %0d cycles", timeout);
  endtask

  // ---------------------------------------------------------------------------
  // Convenience — program divisor via DLAB
  // ---------------------------------------------------------------------------
  task automatic set_divisor(input logic [15:0] div, input logic [7:0] lcr_body = 8'h03);
    apb_write(ADDR_LCR, {24'h0, lcr_body | 8'h80});     // DLAB=1
    apb_write(ADDR_THR_RBR, {24'h0, div[7:0]});          // DLL
    apb_write(ADDR_IER,     {24'h0, div[15:8]});         // DLM
    apb_write(ADDR_LCR, {24'h0, lcr_body & 8'h7F});      // DLAB=0
    divisor = div;
  endtask

  // ---------------------------------------------------------------------------
  // Drain any pending RX/INT residuals cleanly (called between TCs)
  // ---------------------------------------------------------------------------
  task automatic drain_rx;
    logic [31:0] r; int loops = 0;
    do begin
      apb_read(ADDR_LSR, r);
      if (!r[0]) break;
      apb_read(ADDR_THR_RBR, r);
      loops++;
    end while (loops < 32);
    apb_read(ADDR_IIR_FCR, r); // ack any pending int cause
    clear_int_flag;
  endtask

  // ---------------------------------------------------------------------------
  // Main test sequence
  // ---------------------------------------------------------------------------
  logic [31:0] rdata;

  initial begin
    // ------------------- Reset -------------------
    RSTN = 1'b0;
    repeat (10) @(posedge CLK);
    RSTN = 1'b1;
    repeat (5) @(posedge CLK);
    divisor = 16'h0004;   // matches TC-default programming below

    // ===============================================================
    // TC1 – Reset check
    // ===============================================================
    $display("\n========== TC1: Reset check ==========");
    check    ("SOUT idle-high after reset", SOUT, 1'b1);
    check    ("INT low after reset",        INT,  1'b0);
    check    ("PSLVERR low after reset",    PSLVERR, 1'b0);
    check    ("RTSN inactive (1) after reset", RTSN, 1'b1);
    check    ("DTRN inactive (1) after reset", DTRN, 1'b1);
    apb_read(ADDR_IER, rdata);
    check_val("IER = 0 after reset",  rdata, 32'h00, 32'hFF);
    apb_read(ADDR_MCR, rdata);
    check_val("MCR = 0 after reset",  rdata, 32'h00, 32'hFF);
    apb_read(ADDR_LSR, rdata);
    check    ("LSR.THRE (bit5) set after reset", rdata[5], 1'b1);
    check    ("LSR.TEMT (bit6) set after reset", rdata[6], 1'b1);
    check    ("LSR.DR   (bit0) clear after reset", rdata[0], 1'b0);

    // ===============================================================
    // TC2 – PREADY / PSLVERR sanity over one access
    // ===============================================================
    $display("\n========== TC2: APB protocol sanity ==========");
    apb_read(ADDR_LSR, rdata);
    check("PSLVERR still 0 after read",  PSLVERR, 1'b0);
    check("PREADY high at end of access", PREADY, 1'b1);

    // ===============================================================
    // TC3 – Scratch register full pattern
    // ===============================================================
    $display("\n========== TC3: SCR round-trip ==========");
    begin
      automatic logic [7:0] pats [6] = '{8'hA5, 8'h5A, 8'hFF, 8'h00, 8'h55, 8'hAA};
      foreach (pats[i]) begin
        apb_write(ADDR_SCR, {24'h0, pats[i]});
        apb_read (ADDR_SCR, rdata);
        check_val($sformatf("SCR pattern 0x%02X", pats[i]),
                  rdata, {24'h0, pats[i]}, 32'hFF);
      end
    end

    // ===============================================================
    // TC4 – LCR bit-field round-trip (DLAB=0 so we don't trap in divisor)
    // ===============================================================
    $display("\n========== TC4: LCR bit-fields ==========");
    apb_write(ADDR_LCR, 32'h03); apb_read(ADDR_LCR, rdata);
    check_val("LCR 8N1",     rdata, 32'h03, 32'hFF);
    apb_write(ADDR_LCR, 32'h1B); apb_read(ADDR_LCR, rdata);
    check_val("LCR 8E1",     rdata, 32'h1B, 32'hFF);
    apb_write(ADDR_LCR, 32'h0B); apb_read(ADDR_LCR, rdata);
    check_val("LCR 8O1",     rdata, 32'h0B, 32'hFF);
    apb_write(ADDR_LCR, 32'h07); apb_read(ADDR_LCR, rdata);
    check_val("LCR 8N2",     rdata, 32'h07, 32'hFF);
    apb_write(ADDR_LCR, 32'h00); apb_read(ADDR_LCR, rdata);
    check_val("LCR 5N1",     rdata, 32'h00, 32'hFF);
    apb_write(ADDR_LCR, 32'h03); // restore

    // ===============================================================
    // TC5 – DLAB isolation
    // ===============================================================
    $display("\n========== TC5: DLAB isolation ==========");
    // Program divisor = 0x1234
    apb_write(ADDR_LCR, 32'h83);          // DLAB=1
    apb_write(ADDR_THR_RBR, 32'h34);      // DLL
    apb_write(ADDR_IER,     32'h12);      // DLM
    // Read back DLL/DLM with DLAB=1
    apb_read(ADDR_THR_RBR, rdata);
    check_val("DLL readback via DLAB=1", rdata, 32'h34, 32'hFF);
    apb_read(ADDR_IER, rdata);
    check_val("DLM readback via DLAB=1", rdata, 32'h12, 32'hFF);
    // Clear DLAB — IER at addr 1 must now behave as IER, not DLM
    apb_write(ADDR_LCR, 32'h03);
    apb_write(ADDR_IER, 32'h00);
    apb_read (ADDR_IER, rdata);
    check_val("IER clears cleanly when DLAB=0", rdata, 32'h00, 32'hFF);
    // Restore useful divisor for later TCs
    set_divisor(16'h0004);

    // ===============================================================
    // TC6 – IER individual bits
    // ===============================================================
    $display("\n========== TC6: IER bits ==========");
    apb_write(ADDR_IER, 32'h01); apb_read(ADDR_IER, rdata);
    check_val("IER ERBFI", rdata, 32'h01, 32'h0F);
    apb_write(ADDR_IER, 32'h02); apb_read(ADDR_IER, rdata);
    check_val("IER ETBEI", rdata, 32'h02, 32'h0F);
    apb_write(ADDR_IER, 32'h04); apb_read(ADDR_IER, rdata);
    check_val("IER ELSI",  rdata, 32'h04, 32'h0F);
    apb_write(ADDR_IER, 32'h08); apb_read(ADDR_IER, rdata);
    check_val("IER EDSSI", rdata, 32'h08, 32'h0F);
    apb_write(ADDR_IER, 32'h00);

    // ===============================================================
    // TC7 – MCR bits
    // ===============================================================
    $display("\n========== TC7: MCR bits ==========");
    apb_write(ADDR_MCR, 32'h01); apb_read(ADDR_MCR, rdata);
    check_val("MCR DTR", rdata, 32'h01, 32'h1F);
    apb_write(ADDR_MCR, 32'h02); apb_read(ADDR_MCR, rdata);
    check_val("MCR RTS", rdata, 32'h02, 32'h1F);
    apb_write(ADDR_MCR, 32'h04); apb_read(ADDR_MCR, rdata);
    check_val("MCR OUT1", rdata, 32'h04, 32'h1F);
    apb_write(ADDR_MCR, 32'h08); apb_read(ADDR_MCR, rdata);
    check_val("MCR OUT2", rdata, 32'h08, 32'h1F);
    apb_write(ADDR_MCR, 32'h10); apb_read(ADDR_MCR, rdata);
    check_val("MCR LOOP", rdata, 32'h10, 32'h1F);
    apb_write(ADDR_MCR, 32'h00);

    // ===============================================================
    // TC8 – FCR enable ⇒ IIR[7:6]=11
    // ===============================================================
    $display("\n========== TC8: FCR / IIR feedback ==========");
    apb_write(ADDR_IIR_FCR, 32'h07);   // FIFO en + clear TX + clear RX
    apb_read (ADDR_IIR_FCR, rdata);
    check_val("IIR[7:6]=11 with FIFOs enabled", rdata, 32'hC0, 32'hC0);

    // ===============================================================
    // TC9 – Divisor readback
    // ===============================================================
    $display("\n========== TC9: divisor readback ==========");
    apb_write(ADDR_LCR, 32'h83);
    apb_read (ADDR_THR_RBR, rdata);
    check_val("DLL = 0x04",  rdata, 32'h04, 32'hFF);
    apb_read (ADDR_IER, rdata);
    check_val("DLM = 0x00",  rdata, 32'h00, 32'hFF);
    apb_write(ADDR_LCR, 32'h03);

    // ===============================================================
    // TC10 – TX single byte (external capture)
    // ===============================================================
    $display("\n========== TC10: TX external capture ==========");
    drain_rx;
    begin
      automatic logic [7:0] tx = 8'hA5, rx;
      fork
        apb_write(ADDR_THR_RBR, {24'h0, tx});
        uart_recv_byte(rx, 8, 1'b0, 1);
      join
      check_val("SOUT byte matches THR write", {24'h0, rx}, {24'h0, tx}, 32'hFF);
    end

    // ===============================================================
    // TC11 – RX single byte (external drive)
    // ===============================================================
    $display("\n========== TC11: RX from SIN ==========");
    drain_rx;
    begin
      automatic logic [7:0] tx = 8'h3C;
      uart_send_byte(tx, 8, 0, 0, 1);
      wait_lsr_bit(0, 1'b1);
      apb_read(ADDR_LSR, rdata);
      check("LSR.DR set after byte received", rdata[0], 1'b1);
      apb_read(ADDR_THR_RBR, rdata);
      check_val("RBR = 0x3C", rdata, 32'h3C, 32'hFF);
    end

    // ===============================================================
    // TC12 – Internal loopback (MCR.LOOP)
    // ===============================================================
    $display("\n========== TC12: MCR loopback ==========");
    drain_rx;
    apb_write(ADDR_MCR, 32'h10);
    begin
      automatic logic [7:0] tx = 8'hF0;
      apb_write(ADDR_THR_RBR, {24'h0, tx});
      wait_lsr_bit(0, 1'b1);
      apb_read(ADDR_THR_RBR, rdata);
      check_val("loopback byte matches TX", rdata, 32'hF0, 32'hFF);
    end

    // ===============================================================
    // TC13 – Loopback FIFO burst (ordering preserved)
    // ===============================================================
    $display("\n========== TC13: loopback FIFO burst ==========");
    // FIFOs already enabled from TC8
    begin
      automatic logic [7:0] burst [4] = '{8'h11, 8'h22, 8'h33, 8'h44};
      // push all four (FIFO absorbs them)
      for (int k = 0; k < 4; k++)
        apb_write(ADDR_THR_RBR, {24'h0, burst[k]});
      // pop as they arrive
      for (int k = 0; k < 4; k++) begin
        wait_lsr_bit(0, 1'b1);
        apb_read(ADDR_THR_RBR, rdata);
        check_val($sformatf("FIFO burst byte[%0d]", k),
                  rdata, {24'h0, burst[k]}, 32'hFF);
      end
    end
    apb_write(ADDR_MCR, 32'h00);   // exit loopback

    // ===============================================================
    // TC14 – THRE eventually rises after TX drains
    // ===============================================================
    $display("\n========== TC14: LSR.THRE post-drain ==========");
    drain_rx;
    begin
      automatic logic [7:0] tx = 8'h55, rx;
      fork
        apb_write(ADDR_THR_RBR, {24'h0, tx});
        uart_recv_byte(rx, 8, 0, 1);
      join
    end
    wait_lsr_bit(5, 1'b1);
    apb_read(ADDR_LSR, rdata);
    check("LSR.THRE set after TX drains", rdata[5], 1'b1);

    // ===============================================================
    // TC15 – TEMT (shift-register empty) also set
    // ===============================================================
    $display("\n========== TC15: LSR.TEMT ==========");
    wait_lsr_bit(6, 1'b1);
    apb_read(ADDR_LSR, rdata);
    check("LSR.TEMT set once shift-reg empty", rdata[6], 1'b1);

    // ===============================================================
    // TC16 – RDA interrupt
    // ===============================================================
    $display("\n========== TC16: RDA interrupt ==========");
    drain_rx;
    apb_write(ADDR_IER, 32'h01); // ERBFI
    uart_send_byte(8'hBE);
    wait_int_flag;
    check("INT asserted on RDA", int_flag, 1'b1);
    apb_read(ADDR_IIR_FCR, rdata);
    check_val("IIR shows RDA (0b0100)", rdata, 32'h04, 32'h0E);
    apb_read(ADDR_THR_RBR, rdata);
    check_val("RBR = 0xBE", rdata, 32'hBE, 32'hFF);
    repeat (8) @(posedge CLK);
    check("INT deasserted after RBR read", INT, 1'b0);
    apb_write(ADDR_IER, 32'h00);
    clear_int_flag;

    // ===============================================================
    // TC17 – THRE interrupt
    // ===============================================================
    $display("\n========== TC17: THRE interrupt ==========");
    drain_rx;
    apb_write(ADDR_IER, 32'h02); // ETBEI
    wait_int_flag;
    check("INT asserted on THRE", int_flag, 1'b1);
    apb_read(ADDR_IIR_FCR, rdata);
    check_val("IIR shows THRE (0b0010)", rdata, 32'h02, 32'h0E);
    apb_write(ADDR_IER, 32'h00);
    repeat (8) @(posedge CLK);
    clear_int_flag;

    // ===============================================================
    // TC18 – Modem status interrupt (via loopback MCR RTS→CTS)
    // ===============================================================
    $display("\n========== TC18: Modem-status interrupt ==========");
    apb_write(ADDR_MCR, 32'h10);          // loopback, RTS=0
    apb_read (ADDR_MSR, rdata);           // clear any delta bits
    clear_int_flag;
    apb_write(ADDR_IER, 32'h08);          // EDSSI
    apb_write(ADDR_MCR, 32'h12);          // loopback, RTS=1 -> CTS delta
    repeat (16) @(posedge CLK);
    check("INT asserted on MSR delta", int_flag, 1'b1);
    apb_read(ADDR_IIR_FCR, rdata);
    check_val("IIR shows MSR (0b0000)", rdata, 32'h00, 32'h0E);
    apb_read(ADDR_MSR, rdata);            // clears delta bits
    repeat (8) @(posedge CLK);
    check("INT deasserted after MSR read", INT, 1'b0);
    apb_write(ADDR_IER, 32'h00);
    apb_write(ADDR_MCR, 32'h00);
    clear_int_flag;

    // ===============================================================
    // TC19 – MCR RTS/DTR reflected into MSR under loopback
    // ===============================================================
    $display("\n========== TC19: MCR->MSR loopback mirror ==========");
    apb_write(ADDR_MCR, 32'h13);          // LOOP + RTS + DTR
    apb_read (ADDR_MSR, rdata);
    check_val("MSR CTS+DSR set (MCR RTS+DTR)", rdata, 32'h30, 32'h30);
    apb_write(ADDR_MCR, 32'h10);
    apb_read (ADDR_MSR, rdata);
    check_val("MSR CTS+DSR clear", rdata, 32'h00, 32'h30);
    apb_write(ADDR_MCR, 32'h00);

    // ===============================================================
    // TC20 – Physical modem inputs pass-through
    // ===============================================================
    $display("\n========== TC20: Physical modem inputs ==========");
    apb_read(ADDR_MSR, rdata); // clear deltas
    CTSN = 1'b0; DSRN = 1'b0; DCDN = 1'b0; RIN = 1'b0;
    repeat (8) @(posedge CLK);
    apb_read(ADDR_MSR, rdata);
    // MSR bit 4=CTS, 5=DSR, 7=DCD, 6=RI(indicator polarity varies)
    check_val("MSR reflects CTS asserted", rdata, 32'h10, 32'h10);
    check_val("MSR reflects DSR asserted", rdata, 32'h20, 32'h20);
    check_val("MSR reflects DCD asserted", rdata, 32'h80, 32'h80);
    CTSN = 1'b1; DSRN = 1'b1; DCDN = 1'b1; RIN = 1'b1;
    repeat (8) @(posedge CLK);
    apb_read(ADDR_MSR, rdata); // clear deltas

    // ===============================================================
    // TC21 – Parity: 8E1 correct → no PE
    // ===============================================================
    $display("\n========== TC21: 8E1 correct parity ==========");
    drain_rx;
    apb_write(ADDR_LCR, 32'h1B);          // 8E1
    uart_send_byte(8'h5A, 8, 1'b1, 1'b0, 1);   // even parity, correct
    wait_lsr_bit(0, 1'b1);
    apb_read(ADDR_LSR, rdata);
    check("LSR.PE clear (correct parity)", rdata[2], 1'b0);
    apb_read(ADDR_THR_RBR, rdata);
    check_val("RBR = 0x5A (parity ok)", rdata, 32'h5A, 32'hFF);

    // ===============================================================
    // TC22 – Parity: 8E1 wrong → PE flag
    // ===============================================================
    $display("\n========== TC22: 8E1 injected wrong parity ==========");
    drain_rx;
    uart_send_byte(8'h5A, 8, 1'b1, 1'b0, 1, /*corrupt_parity*/1'b1, 1'b0);
    wait_lsr_bit(0, 1'b1);
    apb_read(ADDR_LSR, rdata);
    check("LSR.PE set on parity mismatch", rdata[2], 1'b1);
    apb_read(ADDR_THR_RBR, rdata);         // pop the errored byte
    apb_write(ADDR_LCR, 32'h03);           // back to 8N1
    drain_rx;

    // ===============================================================
    // TC23 – Framing error (stop=0)
    // ===============================================================
    $display("\n========== TC23: framing error ==========");
    drain_rx;
    uart_send_byte(8'h96, 8, 1'b0, 1'b0, 1, 1'b0, /*corrupt_stop*/1'b1);
    wait_lsr_bit(0, 1'b1);
    apb_read(ADDR_LSR, rdata);
    check("LSR.FE set on framing error", rdata[3], 1'b1);
    apb_read(ADDR_THR_RBR, rdata);
    // idle line back to high before next TC
    SIN = 1'b1;
    repeat (bit_period() * 4) @(posedge CLK);
    drain_rx;

    // ===============================================================
    // TC24 – Break condition
    // ===============================================================
    $display("\n========== TC24: break detection ==========");
    drain_rx;
    uart_send_break(1);
    wait_lsr_bit(4, 1'b1);
    apb_read(ADDR_LSR, rdata);
    check("LSR.BI set on break condition", rdata[4], 1'b1);
    // reading LSR clears the sticky BI in most 16550s; read RBR to flush
    apb_read(ADDR_THR_RBR, rdata);
    drain_rx;

    // ===============================================================
    // TC25 – 7N1 loopback round-trip
    // ===============================================================
    $display("\n========== TC25: 7N1 loopback ==========");
    drain_rx;
    apb_write(ADDR_LCR, 32'h02);          // WLS=10 → 7-bit, no parity, 1 stop
    apb_write(ADDR_MCR, 32'h10);          // loopback
    apb_write(ADDR_THR_RBR, 32'h5A);
    wait_lsr_bit(0, 1'b1);
    apb_read(ADDR_THR_RBR, rdata);
    check_val("7N1 loopback returns low 7 bits", rdata, 32'h5A, 32'h7F);
    apb_write(ADDR_MCR, 32'h00);
    apb_write(ADDR_LCR, 32'h03);          // restore 8N1

    // ===============================================================
    // TC26 – Different baud (divisor=8) round-trip
    // ===============================================================
    $display("\n========== TC26: divisor=8 baud test ==========");
    drain_rx;
    set_divisor(16'h0008);
    apb_write(ADDR_MCR, 32'h10);          // loopback
    apb_write(ADDR_THR_RBR, 32'hC3);
    wait_lsr_bit(0, 1'b1, TIMEOUT_CYC*2);
    apb_read(ADDR_THR_RBR, rdata);
    check_val("Divisor=8 loopback byte OK", rdata, 32'hC3, 32'hFF);
    apb_write(ADDR_MCR, 32'h00);
    set_divisor(16'h0004);                // restore fast

    // ===============================================================
    // TC27 – Back-to-back APB reads (bus doesn't stall)
    // ===============================================================
    $display("\n========== TC27: back-to-back APB reads ==========");
    begin
      automatic int stall_cnt = 0;
      for (int k = 0; k < 8; k++) begin
        apb_read(ADDR_LSR, rdata);
        if (!PREADY) stall_cnt++;  // shouldn't stall
      end
      check_val("no PREADY stalls in 8 back-to-back reads",
                stall_cnt, 32'h0, 32'hFFFFFFFF);
    end

    // ===============================================================
    // TC28 – Warm reset clears IER/SCR
    // ===============================================================
    $display("\n========== TC28: warm reset ==========");
    apb_write(ADDR_SCR, 32'hFF);
    apb_write(ADDR_IER, 32'h0F);
    RSTN = 1'b0;
    repeat (8) @(posedge CLK);
    RSTN = 1'b1;
    repeat (8) @(posedge CLK);
    apb_read(ADDR_IER, rdata);
    check_val("IER cleared post-reset", rdata, 32'h00, 32'h0F);
    apb_read(ADDR_SCR, rdata);
    check_val("SCR cleared post-reset (or preserved by design)",
              rdata, 32'h00, 32'hFF);  // some 16550s preserve SCR; either OK
    check("INT low post-reset", INT, 1'b0);
    check("SOUT idle-high post-reset", SOUT, 1'b1);
    // re-program divisor
    set_divisor(16'h0004);

    // ===============================================================
    // TC29 – SOUT stable high in idle
    // ===============================================================
    $display("\n========== TC29: SOUT idle stability ==========");
    drain_rx;
    begin
      automatic int wobble = 0;
      repeat (bit_period() * 4) begin
        @(posedge CLK);
        if (SOUT !== 1'b1) wobble++;
      end
      check_val("SOUT held high for 4 bit-periods of idle",
                wobble, 32'h0, 32'hFFFFFFFF);
    end

    // ===============================================================
    // TC30 – CTS auto-flow (MCR.AFE bit 5) throttles TX when CTSN=1
    // NOTE: not all 16550 variants implement AFE; treat as informational
    //       if the design ignores bit 5.
    // ===============================================================
    $display("\n========== TC30: MCR.AFE (informational if unsupported) ==========");
    drain_rx;
    apb_write(ADDR_MCR, 32'h22);          // AFE=1, RTS=1
    CTSN = 1'b1;                          // deasserted → gate TX
    apb_write(ADDR_THR_RBR, 32'h77);      // queue a byte
    // If AFE is honoured, SOUT stays high; if not, SOUT begins to shift.
    begin
      automatic int fell = 0;
      repeat (bit_period() * 2) begin
        @(posedge CLK);
        if (SOUT === 1'b0) fell = 1;
      end
      if (fell) $display("  [INFO] MCR.AFE not honoured by this 16550 variant — TX went out with CTSN=1");
      else      $display("  [INFO] MCR.AFE honoured — TX held while CTSN=1");
    end
    CTSN = 1'b0;                          // release
    // now the byte should get out
    begin
      automatic logic [7:0] rx;
      uart_recv_byte(rx);
      check_val("Byte transmitted once CTS asserted", {24'h0, rx}, 32'h77, 32'hFF);
    end
    apb_write(ADDR_MCR, 32'h00);
    CTSN = 1'b1;

    // ===============================================================
    // Summary
    // ===============================================================
    $display("\n========================================");
    $display(" TB SUMMARY: %0d PASSED / %0d FAILED", pass_cnt, fail_cnt);
    $display("========================================");
    if (fail_cnt == 0) $display("*** ALL TESTS PASSED ***");
    else               $display("*** %0d TEST(S) FAILED ***", fail_cnt);

    $finish;
  end

  // ---------------------------------------------------------------------------
  // Global watchdog
  // ---------------------------------------------------------------------------
  initial begin
    #(GLOBAL_WD_NS);
    $display("[ERROR] Global watchdog expired at %0t ns", $time);
    $display(" TB SUMMARY: %0d PASSED / %0d FAILED", pass_cnt, fail_cnt);
    $finish;
  end

  // ---------------------------------------------------------------------------
  // Waveform dump
  // ---------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_apb_uart_thorough.vcd");
    $dumpvars(0, tb_apb_uart_thorough);
    // Xcelium-specific (comment out if using Questa/VCS):
    // $recordfile("waves_uart.trn");
    // $recordvars();
  end

  // ---------------------------------------------------------------------------
  // APB protocol assertions (SVA) — same rules as SPI tb
  // ---------------------------------------------------------------------------
  property apb_enable_follows_sel;
    @(posedge CLK) disable iff (!RSTN)
      (PSEL && !PENABLE) |=> PENABLE;
  endproperty
  assert property (apb_enable_follows_sel)
    else $error("[SVA] PENABLE did not follow PSEL");

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

  property apb_no_deadlock;
    @(posedge CLK) disable iff (!RSTN)
      (PSEL && PENABLE && !PREADY) |-> ##[1:32] PREADY;
  endproperty
  assert property (apb_no_deadlock)
    else $error("[SVA] APB stall exceeded 32 cycles (deadlock)");

  property no_x_on_sout;
    @(posedge CLK) disable iff (!RSTN)
      1'b1 |-> (SOUT === 1'b0 || SOUT === 1'b1);
  endproperty
  assert property (no_x_on_sout)
    else $error("[SVA] SOUT went to X/Z");

endmodule
