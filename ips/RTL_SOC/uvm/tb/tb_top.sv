`timescale 1ns/1ps

`ifndef FW_WORDS
`define FW_WORDS 64
`endif

module tb_top;
  import uvm_pkg::*;
  import soc_pkg::*;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  soc_ctrl_if ctrl  (clk);
  uart_if     uart  (clk);
  gpio_if     gpio  (clk);
  spi_if      spi   (clk);
  i2c_if      i2c   (clk);
  irq_if      irq   (clk);
  trace_if    trace (clk);

  logic       i2c_scl_o, i2c_scl_oen, i2c_sda_o, i2c_sda_oen;
  logic [3:0] timer0_irq, timer1_irq;
  logic       uart_int, gpio_int, i2c_int;
  logic [1:0] spi_events;
  logic [5:0] apb_timeout;
  logic       axi_wr_timeout, axi_rd_timeout;
  logic       spi_csn0, spi_miso;
  wire        flash_so;

  assign i2c.scl = (i2c_scl_oen ? 1'b1 : i2c_scl_o) & i2c.scl_drv;
  assign i2c.sda = (i2c_sda_oen ? 1'b1 : i2c_sda_o) & i2c.sda_drv;

`ifdef FLASH_BOOT
  s25fs512s #(
    .UserPreload   (1),
    .mem_file_name ("flash.mem"),
    .otp_file_name ("../../spi_slave_infinion/S25fs512s/model/s25fs512sOTP.mem")
  ) u_flash (
    .SI       (spi.sdo),
    .SO       (flash_so),
    .SCK      (spi.sck),
    .CSNeg    (spi_csn0),
    .WPNeg    (1'b1),
    .RESETNeg (1'b1)
  );
`else
  assign flash_so = 1'b0;
`endif

  assign spi_miso = (spi.csn === 1'b0) ? spi.sdi : flash_so;

  riscforge_soc_subsystem #(
    .NUM_INSTR_WORDS (`FW_WORDS),
    .NUM_DATA_WORDS  (0)
  ) dut (
    .clk_i                       (clk),
    .hard_rst_ni                 (ctrl.hard_rst_n),
    .soft_rst_ni                 (ctrl.soft_rst_n),
    .test_mode_i                 (ctrl.test_mode),
    .fetch_enable_i              (ctrl.fetch_en),
    .boot_addr_i                 (ctrl.boot_addr),
    .boot_done_o                 (ctrl.boot_done),
    .i2c_scl_i                   (i2c.scl),
    .i2c_scl_o                   (i2c_scl_o),
    .i2c_scl_oen_o               (i2c_scl_oen),
    .i2c_sda_i                   (i2c.sda),
    .i2c_sda_o                   (i2c_sda_o),
    .i2c_sda_oen_o               (i2c_sda_oen),
    .i2c_interrupt_o             (i2c_int),
    .timer0_irq_o                (timer0_irq),
    .timer1_irq_o                (timer1_irq),
    .uart_sin_i                  (uart.sin),
    .uart_sout_o                 (uart.sout),
    .uart_int_o                  (uart_int),
    .gpio_in_i                   (gpio.gpio_in),
    .gpio_out_o                  (gpio.gpio_out),
    .gpio_tx_en_o                (gpio.gpio_tx_en),
    .gpio_in_sync_o              (),
    .gpio_global_interrupt_o     (gpio_int),
    .gpio_pin_level_interrupts_o (),
    .spi_clk_o                   (spi.sck),
    .spi_csn0_o                  (spi_csn0),
    .spi_csn1_o                  (spi.csn),
    .spi_sdo0_o                  (spi.sdo),
    .spi_sdi1_i                  (spi_miso),
    .spi_events_o                (spi_events),
    .apb_timeout_sticky_o        (apb_timeout),
    .axi_wr_timeout_sticky_o     (axi_wr_timeout),
    .axi_rd_timeout_sticky_o     (axi_rd_timeout)
  );

  assign ctrl.core_rst_n = dut.core_rst_n;

  assign irq.rst_n  = dut.core_rst_n;
  assign irq.timer0 = timer0_irq;
  assign irq.timer1 = timer1_irq;
  assign irq.uart   = uart_int;
  assign irq.gpio   = gpio_int;
  assign irq.i2c    = i2c_int;
  assign irq.spi    = spi_events;

  assign trace.rst_n     = dut.core_rst_n;
  assign trace.wb_en     = dut.i_riscv_core.RegWriteW_gated;
  assign trace.wb_rd     = dut.i_riscv_core.RDW;
  assign trace.wb_data   = dut.i_riscv_core.ResultW;
  assign trace.wb_pc     = dut.i_riscv_core.PC_W;
  assign trace.mem_req   = dut.core_lsu_req;
  assign trace.mem_we    = dut.core_lsu_we;
  assign trace.mem_stall = dut.core_lsu_stall;
  assign trace.mem_addr  = dut.core_lsu_addr;
  assign trace.mem_wdata = dut.core_lsu_wdata;

  core_sva u_core_sva (
    .clk            (clk),
    .rst_n          (dut.core_rst_n),
    .pc             (dut.i_riscv_core.PC_W),
    .lsu_req        (dut.core_lsu_req),
    .lsu_err        (dut.core_lsu_err),
    .uart_sout      (uart.sout),
    .apb_timeout    (apb_timeout),
    .axi_wr_timeout (axi_wr_timeout),
    .axi_rd_timeout (axi_rd_timeout),
    .allow_err      (ctrl.allow_lsu_err)
  );

  for (genvar i = 0; i < 6; i++) begin : g_apb_sva
    apb_sva u_apb_sva (
      .clk     (clk),
      .rst_n   (dut.sys_rst_n),
      .psel    (dut.apb_req[i].psel),
      .penable (dut.apb_req[i].penable),
      .pready  (dut.apb_resp[i].pready),
      .paddr   (dut.apb_req[i].paddr)
    );
  end

`ifndef FLASH_BOOT
  initial begin
    string hex = "imem.hex";
    void'($value$plusargs("HEX=%s", hex));
    wait (ctrl.hard_rst_n === 1'b0);
    wait (ctrl.hard_rst_n === 1'b1);
    wait (ctrl.soft_rst_n === 1'b1);
    $readmemh(hex, dut.i_isram.u_imem.mem_array);
    for (int i = 0; i < $size(dut.i_dsram.mem); i++)
      dut.i_dsram.mem[i] = '0;
    $display("[TB] loaded %s into ISRAM, DSRAM cleared", hex);
  end
`endif

  initial begin
    uvm_config_db #(virtual soc_ctrl_if)::set(null, "uvm_test_top", "ctrl", ctrl);
    uvm_config_db #(virtual uart_if)::set(null, "uvm_test_top.env.uart", "vif", uart);
    uvm_config_db #(virtual gpio_if)::set(null, "uvm_test_top.env.gpio", "vif", gpio);
    uvm_config_db #(virtual spi_if)::set(null, "uvm_test_top.env.spi", "vif", spi);
    uvm_config_db #(virtual i2c_if)::set(null, "uvm_test_top.env.i2c", "vif", i2c);
    uvm_config_db #(virtual irq_if)::set(null, "uvm_test_top.env.irq", "vif", irq);
    uvm_config_db #(virtual trace_if)::set(null, "uvm_test_top.env.trace", "vif", trace);
    run_test("soc_hello_test");
  end
endmodule
