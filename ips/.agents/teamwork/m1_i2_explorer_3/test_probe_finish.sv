`timescale 1ns/1ps

`include "Verification/infrastructure/tb/rf_monitor_if.sv"
`include "Verification/infrastructure/tb/tb_pkg.sv"
`include "Verification/infrastructure/monitors/rf_monitors.sv"
`include "Verification/infrastructure/monitors/rf_monitor_env.sv"
`include "Verification/infrastructure/tb/rf_mon_probe.sv"
`include "Verification/infrastructure/tb/rf_mon_challenger_dut.sv"

module test_probe_finish;
  logic clk = 0;
  logic rst_n = 0;
  logic freeze = 0;

  always #5 clk = ~clk;

  rf_mon_challenger_dut u_dut (.clk(clk));

  rf_mon_probe #(
    .RING_DEPTH(256),
    .DUMP_N(4),
    .RUN_MONITORS(1'b1)
  ) u_mon (
    .clk(clk),
    .rst_n(rst_n),
    .freeze(freeze),
    .uart_rx_wire(1'b1),
    .uart_tx_wire(),
    .i2c_scl_wire(),
    .i2c_sda_wire(),
    .spi_sclk_wire(),
    .spi_csn0_wire(),
    .spi_csn1_wire(),
    .spi_mosi_wire(),
    .spi_miso_wire(1'b0),
    .gpio_in_wire(32'b0),
    .gpio_out_wire(),
    .gpio_oe_wire()
  );

  initial begin
    #10;
    rst_n = 1;
    #200;
    $display("Calling finish(1)...");
    $finish(1);
  end
endmodule
