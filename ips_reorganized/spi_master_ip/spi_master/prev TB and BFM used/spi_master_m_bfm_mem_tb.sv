`timescale 1ns/1ps

// SPI Master BFM Testbench — .mem-driven variant
// Same DUT path as spi_master_m_bfm_tb.sv (SPI Slave BFM -> RX FIFO -> APB),
// but stimulus words come from instr.mem via spi_slave_bfm instead of
// hardcoded localparams.
//
// TC1 - Single word inject   (mem[IDX_SINGLE])
// TC2 - Sequential 4 words   (mem[IDX_SEQ .. IDX_SEQ+3], one txn each)
// TC3 - 128-bit burst inject (mem[IDX_SEQ .. IDX_SEQ+3], one CSN)
// TC4 - APB readback sanity  (mem[IDX_SINGLE] via APB, log PREADY/PSLVERR)

module tb_apb_spi_master_bfm_mem;

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

  // Instruction memory index map (matches instr.mem layout)
  localparam int IDX_SINGLE = 0;
  localparam int IDX_SEQ    = 1;

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

  spi_slave_bfm #(.MEM_FILE("instr.mem")) u_slave (
    .spi_clk(spi_clk),
    .spi_csn(spi_csn0),
    .spi_sdi(spi_sdi1)
  );

  assign spi_sdi0 = 1'b0;
  assign spi_sdi2 = 1'b0;
  assign spi_sdi3 = 1'b0;

  initial HCLK = 1'b0;
  always #(CLK_PERIOD/2) HCLK = ~HCLK;

  // -----------------------------------------------------------------------
  // APB Helper Tasks
  // -----------------------------------------------------------------------
  task automatic cfg_spi(
    input logic [7:0]  clk_div,
    input logic [15:0] data_bits
  );
    begin
      u_apb_bfm.apb_write(reg_addr(REG_CLKDIV), {24'h0, clk_div});
      u_apb_bfm.apb_write(reg_addr(REG_SPICMD), 32'h0);
      u_apb_bfm.apb_write(reg_addr(REG_SPIADR), 32'h0);
      u_apb_bfm.apb_write(reg_addr(REG_SPILEN), {data_bits, 2'b00, 6'd0, 2'b00, 6'd0});
      u_apb_bfm.apb_write(reg_addr(REG_SPIDUM), 32'h0);
    end
  endtask

  task automatic trigger_read(input logic [3:0] cs = 4'b0001);
    u_apb_bfm.apb_write(reg_addr(REG_STATUS), {20'h0, cs, 4'h0, 4'b0001});
  endtask

  task automatic core_read_rx(output logic [31:0] data);
    u_apb_bfm.apb_read(reg_addr(REG_RXFIFO), data);
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

  // =======================================================================
  // Main Test Sequence
  // =======================================================================
  logic [31:0] rx_word;

  initial begin
    HRESETn = 1'b0;
    u_apb_bfm.idle_bus();
    repeat (5) @(posedge HCLK);
    HRESETn = 1'b1;
    repeat (5) @(posedge HCLK);

    $display("================================================================");
    $display("  SPI Instruction Injection — .mem-driven BFM Testbench");
    $display("  Stimulus source: instr.mem (via spi_slave_bfm)");
    $display("================================================================");

    // ---------- TC1: Single word inject ----------
    $display("\n--- TC1: Single Word Inject  (mem[%0d]) ---", IDX_SINGLE);
    cfg_spi(8'd4, 16'd32);
    fork
      u_slave.inject_word(IDX_SINGLE);
      begin trigger_read(); wait_eot(); end
    join
    core_read_rx(rx_word);
    check("TC1: readback matches mem[IDX_SINGLE]", rx_word, u_slave.mem[IDX_SINGLE]);

    // ---------- TC2: Sequential 4-word load ----------
    $display("\n--- TC2: Sequential 4-Word Load  (mem[%0d..%0d]) ---",
             IDX_SEQ, IDX_SEQ+3);
    for (int k = 0; k < 4; k++) begin
      cfg_spi(8'd4, 16'd32);
      fork
        u_slave.inject_word(IDX_SEQ + k);
        begin trigger_read(); wait_eot(); end
      join
      core_read_rx(rx_word);
      check($sformatf("TC2[%0d]: mem[%0d]", k, IDX_SEQ + k),
            rx_word, u_slave.mem[IDX_SEQ + k]);
    end

    // ---------- TC3: 128-bit burst (4 words, single CSN) ----------
    $display("\n--- TC3: Burst Inject 4x32b  (mem[%0d..%0d]) ---",
             IDX_SEQ, IDX_SEQ+3);
    cfg_spi(8'd4, 16'd128);
    fork
      u_slave.inject_burst(IDX_SEQ, 4);
      begin trigger_read(); wait_eot(); end
    join
    check("TC3: FIFO has 4 entries",
          {28'h0, dut.u_rxfifo.elements}, 32'h4, 32'hF);
    for (int k = 0; k < 4; k++) begin
      core_read_rx(rx_word);
      check($sformatf("TC3: word[%0d] == mem[%0d]", k, IDX_SEQ + k),
            rx_word, u_slave.mem[IDX_SEQ + k]);
    end

    // ---------- TC4: APB readback sanity ----------
    $display("\n--- TC4: APB Readback Sanity  (mem[%0d]) ---", IDX_SINGLE);
    cfg_spi(8'd4, 16'd32);
    fork
      u_slave.inject_word(IDX_SINGLE);
      begin trigger_read(); wait_eot(); end
    join
    core_read_rx(rx_word);
    $display("  PRDATA=0x%08X  PREADY=%b  PSLVERR=%b", rx_word, PREADY, PSLVERR);
    check("TC4: PRDATA integrity", rx_word, u_slave.mem[IDX_SINGLE]);

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
    $shm_open("tb_spi_bfm_mem.shm");
    $shm_probe(tb_apb_spi_master_bfm_mem,            "AS");
    $shm_probe(tb_apb_spi_master_bfm_mem.dut.u_txfifo, "AM");
    $shm_probe(tb_apb_spi_master_bfm_mem.dut.u_rxfifo, "AM");
  end

endmodule
