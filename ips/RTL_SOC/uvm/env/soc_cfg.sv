class soc_cfg extends uvm_object;
  `uvm_object_utils(soc_cfg)

  int unsigned uart_bit_clks  = 32;
  int unsigned uart_data_bits = 8;
  int unsigned uart_parity    = 0;
  int unsigned uart_stop_bits = 1;
  bit [31:0]   tohost_addr   = 32'h0002_0000;
  bit [31:0]   phase_addr    = 32'h0002_0004;
  int unsigned timeout_clks  = 500_000;
  int unsigned boot_clks     = 5_000;
  bit          cold_boot;
  bit          allow_lsu_err;
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
  int unsigned i2c_stretch   = 0;
  bit          i2c_al_once;

  bit [12:0]   irq_expect;
  bit [31:0]   gpio_pins_expect;
  bit [31:0]   gpio_en_expect;
  bit          check_gpio_pins;

  uvm_event    done_ev;
  uvm_event    phase_ev;
  int unsigned phase;

  function new(string name = "soc_cfg");
    super.new(name);
    done_ev  = new("done_ev");
    phase_ev = new("phase_ev");
  endfunction

  function void read_plusargs();
    void'($value$plusargs("UART_BIT_CLKS=%d", uart_bit_clks));
    void'($value$plusargs("TIMEOUT=%d", timeout_clks));
    void'($value$plusargs("UART_EXPECT=%s", uart_expect));
  endfunction
endclass
