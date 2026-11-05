class soc_coverage extends uvm_component;
  `uvm_component_utils(soc_coverage)

  uvm_analysis_imp_commit #(commit_item, soc_coverage) commit_imp;
  uvm_analysis_imp_uart   #(uart_item,   soc_coverage) uart_imp;
  uvm_analysis_imp_irq    #(irq_item,    soc_coverage) irq_imp;
  uvm_analysis_imp_i2c    #(i2c_item,    soc_coverage) i2c_imp;
  uvm_analysis_imp_spi    #(spi_item,    soc_coverage) spi_imp;

  bit [4:0]    rd;
  bit [31:0]   wdata;
  bit [7:0]    uart_data;
  bit [8:0]    irq_rise;
  bit          i2c_rw;
  int unsigned spi_bits;

  covergroup cg_commit;
    cp_rd : coverpoint rd;
    cp_data : coverpoint wdata {
      bins zero = {0};
      bins one  = {1};
      bins neg  = {[32'h8000_0000:32'hFFFF_FFFF]};
      bins pos  = {[2:32'h7FFF_FFFF]};
    }
  endgroup

  covergroup cg_uart;
    cp_data : coverpoint uart_data {
      bins ctrl  = {[0:31]};
      bins text  = {[32:126]};
      bins other = {[127:255]};
    }
  endgroup

  covergroup cg_irq;
    cp_timer : coverpoint irq_rise[3:0] { bins hit = {[1:15]}; }
    cp_uart  : coverpoint irq_rise[4]   { bins hit = {1}; }
    cp_gpio  : coverpoint irq_rise[5]   { bins hit = {1}; }
    cp_i2c   : coverpoint irq_rise[6]   { bins hit = {1}; }
    cp_spi   : coverpoint irq_rise[8:7] { bins hit = {[1:3]}; }
  endgroup

  covergroup cg_bus;
    cp_i2c_rw : coverpoint i2c_rw;
    cp_spi    : coverpoint spi_bits { bins b8 = {8}; bins b32 = {32}; bins other = default; }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    commit_imp = new("commit_imp", this);
    uart_imp   = new("uart_imp", this);
    irq_imp    = new("irq_imp", this);
    i2c_imp    = new("i2c_imp", this);
    spi_imp    = new("spi_imp", this);
    cg_commit  = new();
    cg_uart    = new();
    cg_irq     = new();
    cg_bus     = new();
  endfunction

  function void write_commit(commit_item item);
    if (item.tohost) return;
    rd    = item.rd;
    wdata = item.data;
    cg_commit.sample();
  endfunction

  function void write_uart(uart_item item);
    uart_data = item.data;
    cg_uart.sample();
  endfunction

  function void write_irq(irq_item item);
    irq_rise = item.rise;
    cg_irq.sample();
  endfunction

  function void write_i2c(i2c_item item);
    i2c_rw = item.rw;
    cg_bus.sample();
  endfunction

  function void write_spi(spi_item item);
    spi_bits = item.bits;
    cg_bus.sample();
  endfunction
endclass
