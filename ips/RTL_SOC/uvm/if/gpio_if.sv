interface gpio_if (input logic clk);
  logic [31:0] gpio_in;
  logic [31:0] gpio_out;
  logic [31:0] gpio_tx_en;
endinterface
