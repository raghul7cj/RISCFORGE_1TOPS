interface irq_if (input logic clk);
  logic       rst_n;
  logic [3:0] timer;
  logic       uart;
  logic       gpio;
  logic       i2c;
  logic [1:0] spi;
endinterface
