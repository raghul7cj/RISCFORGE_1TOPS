class soc_cfg extends uvm_object;
  `uvm_object_utils(soc_cfg)

  int unsigned uart_bit_clks = 16;
  bit [31:0]   tohost_addr   = 32'h0001_0FFC;
  int unsigned timeout_clks  = 500_000;
  string       uart_expect   = "";

  bit          check_gpio;
  bit [31:0]   gpio_expect;

  bit          check_spi;
  bit [31:0]   spi_expect;
  bit [31:0]   spi_rdata     = 32'hCAFE_F00D;

  bit          check_i2c;
  bit [6:0]    i2c_addr      = 7'h50;
  bit [7:0]    i2c_expect;
  bit [7:0]    i2c_rdata     = 8'h96;

  bit [8:0]    irq_expect;

  uvm_event    done_ev;

  function new(string name = "soc_cfg");
    super.new(name);
    done_ev = new("done_ev");
  endfunction

  function void read_plusargs();
    void'($value$plusargs("UART_BIT_CLKS=%d", uart_bit_clks));
    void'($value$plusargs("TIMEOUT=%d", timeout_clks));
    void'($value$plusargs("UART_EXPECT=%s", uart_expect));
  endfunction
endclass
