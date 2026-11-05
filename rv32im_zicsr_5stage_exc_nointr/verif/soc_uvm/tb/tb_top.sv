`timescale 1ns/1ps

module tb_top;
  import uvm_pkg::*;
  import soc_pkg::*;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  soc_ctrl_if ctrl (clk);
  uart_if     uart (clk);
  trace_if    trace (clk);

  logic       i2c_scl_oen, i2c_sda_oen, i2c_scl_o, i2c_sda_o;
  wire        i2c_scl = i2c_scl_oen ? 1'b1 : i2c_scl_o;
  wire        i2c_sda = i2c_sda_oen ? 1'b1 : i2c_sda_o;

  riscforge_soc_subsystem dut (
    .clk_i                       (clk),
    .hard_rst_ni                 (ctrl.hard_rst_n),
    .soft_rst_ni                 (ctrl.soft_rst_n),
    .test_mode_i                 (ctrl.test_mode),
    .fetch_enable_i              (ctrl.fetch_en),
    .boot_addr_i                 (ctrl.boot_addr),
    .boot_done_o                 (ctrl.boot_done),
    .i2c_scl_i                   (i2c_scl),
    .i2c_scl_o                   (i2c_scl_o),
    .i2c_scl_oen_o               (i2c_scl_oen),
    .i2c_sda_i                   (i2c_sda),
    .i2c_sda_o                   (i2c_sda_o),
    .i2c_sda_oen_o               (i2c_sda_oen),
    .i2c_interrupt_o             (),
    .timer_irq_o                 (),
    .uart_sin_i                  (uart.sin),
    .uart_sout_o                 (uart.sout),
    .uart_int_o                  (),
    .uart_out1n_o                (),
    .uart_out2n_o                (),
    .uart_rtsn_o                 (),
    .uart_dtrn_o                 (),
    .uart_ctsn_i                 (1'b0),
    .uart_dsrn_i                 (1'b0),
    .uart_dcdn_i                 (1'b0),
    .uart_rin_i                  (1'b1),
    .gpio_in_i                   ('0),
    .gpio_out_o                  (),
    .gpio_tx_en_o                (),
    .gpio_in_sync_o              (),
    .gpio_global_interrupt_o     (),
    .gpio_pin_level_interrupts_o (),
    .spi_clk_o                   (),
    .spi_csn0_o                  (),
    .spi_csn1_o                  (),
    .spi_csn2_o                  (),
    .spi_csn3_o                  (),
    .spi_mode_o                  (),
    .spi_sdo0_o                  (),
    .spi_sdo1_o                  (),
    .spi_sdo2_o                  (),
    .spi_sdo3_o                  (),
    .spi_sdi0_i                  (1'b0),
    .spi_sdi1_i                  (1'b0),
    .spi_sdi2_i                  (1'b0),
    .spi_sdi3_i                  (1'b0),
    .spi_events_o                ()
  );

  assign ctrl.core_rst_n = dut.core_rst_n;

  assign trace.rst_n     = dut.core_rst_n;
  assign trace.wb_en     = dut.i_riscv_core.RegWriteW_gated;
  assign trace.wb_rd     = dut.i_riscv_core.RDW;
  assign trace.wb_data   = dut.i_riscv_core.ResultW;
  assign trace.wb_pc     = dut.i_riscv_core.PC_W;
  assign trace.mem_req   = dut.core_lsu_req;
  assign trace.mem_we    = dut.core_lsu_we;
  assign trace.mem_addr  = dut.core_lsu_addr;
  assign trace.mem_wdata = dut.core_lsu_wdata;

  initial begin
    string hex = "imem.hex";
    void'($value$plusargs("HEX=%s", hex));
    if ($test$plusargs("SKIP_BOOT")) begin
      force dut.core_rst_n   = 1'b0;
      force dut.periph_rst_n = 1'b0;
      wait (ctrl.hard_rst_n === 1'b0);
      wait (ctrl.hard_rst_n === 1'b1);
      $readmemh(hex, dut.i_isram.mem_array);
      repeat (5) @(posedge clk);
      force dut.periph_rst_n = 1'b1;
      force dut.core_rst_n   = 1'b1;
    end else begin
      force dut.core_rst_n = 1'b0;
      wait (ctrl.hard_rst_n === 1'b0);
      wait (ctrl.hard_rst_n === 1'b1);
      wait (ctrl.boot_done === 1'b1);
      $readmemh(hex, dut.i_isram.mem_array);
      @(posedge clk);
      release dut.core_rst_n;
    end
    $display("[TB] loaded %s", hex);
  end

  initial begin
    uvm_config_db #(virtual soc_ctrl_if)::set(null, "uvm_test_top", "ctrl", ctrl);
    uvm_config_db #(virtual uart_if)::set(null, "uvm_test_top.env.uart", "vif", uart);
    uvm_config_db #(virtual trace_if)::set(null, "uvm_test_top.env.trace", "vif", trace);
    run_test("soc_hello_test");
  end
endmodule
