class soc_coverage extends uvm_component;
  `uvm_component_utils(soc_coverage)

  uvm_analysis_imp_commit #(commit_item, soc_coverage) commit_imp;
  uvm_analysis_imp_uart   #(uart_item,   soc_coverage) uart_imp;
  uvm_analysis_imp_irq    #(irq_item,    soc_coverage) irq_imp;
  uvm_analysis_imp_i2c    #(i2c_item,    soc_coverage) i2c_imp;
  uvm_analysis_imp_spi    #(spi_item,    soc_coverage) spi_imp;
  uvm_analysis_imp_gpio   #(gpio_item,   soc_coverage) gpio_imp;

  bit [4:0]    rd;
  bit [31:0]   wdata;
  bit [7:0]    uart_data;
  int unsigned uart_bits;
  int unsigned uart_par;
  int unsigned uart_stop;
  bit [12:0]   irq_rise;
  bit          i2c_rw;
  int unsigned spi_bits;
  bit          trap_irq;
  int unsigned trap_cause;
  bit [31:0]   gpio_out;
  bit [31:0]   gpio_en;

  covergroup cg_commit;
    option.per_instance = 1;
    cp_rd : coverpoint rd;
    cp_data : coverpoint wdata {
      bins zero = {0};
      bins one  = {1};
      bins neg  = {[32'h8000_0000:32'hFFFF_FFFF]};
      bins pos  = {[2:32'h7FFF_FFFF]};
    }
  endgroup

  covergroup cg_uart;
    option.per_instance = 1;
    cp_data : coverpoint uart_data {
      bins ctrl  = {[0:31]};
      bins text  = {[32:126]};
      bins other = {[127:255]};
    }
    cp_bits : coverpoint uart_bits { bins b[] = {5, 6, 7, 8}; }
    cp_par  : coverpoint uart_par  { bins p[] = {0, 1, 2, 3, 4}; }
    cp_stop : coverpoint uart_stop { bins s[] = {1, 2}; }
  endgroup

  covergroup cg_irq;
    option.per_instance = 1;
    cp_t0_ovf : coverpoint irq_rise[0]  { bins hit = {1}; }
    cp_t0_cmp : coverpoint irq_rise[1]  { bins hit = {1}; }
    cp_t0c1   : coverpoint irq_rise[3]  { bins hit = {1}; }
    cp_t1_ovf : coverpoint irq_rise[4]  { bins hit = {1}; }
    cp_t1_cmp : coverpoint irq_rise[5]  { bins hit = {1}; }
    cp_t1c1   : coverpoint irq_rise[7]  { bins hit = {1}; }
    cp_uart   : coverpoint irq_rise[8]  { bins hit = {1}; }
    cp_gpio   : coverpoint irq_rise[9]  { bins hit = {1}; }
    cp_i2c    : coverpoint irq_rise[10] { bins hit = {1}; }
    cp_spi0   : coverpoint irq_rise[11] { bins hit = {1}; }
    cp_spi1   : coverpoint irq_rise[12] { bins hit = {1}; }
  endgroup

  covergroup cg_bus;
    option.per_instance = 1;
    cp_i2c_rw : coverpoint i2c_rw;
    cp_spi    : coverpoint spi_bits {
      bins b8   = {8};
      bins b16  = {16};
      bins b32  = {32};
      bins b56  = {56};
      bins b64  = {64};
      bins other = default;
    }
  endgroup

  covergroup cg_trap;
    option.per_instance = 1;
    cp_exc : coverpoint trap_cause iff (!trap_irq) {
      bins illegal   = {2};
      bins ebreak    = {3};
      bins ld_align  = {4};
      bins ld_fault  = {5};
      bins st_align  = {6};
      bins st_fault  = {7};
      bins ecall     = {11};
    }
    cp_irq : coverpoint trap_cause iff (trap_irq) {
      bins mtip  = {7};
      bins gpio  = {16};
      bins uart  = {19};
      bins tmr1  = {24};
      bins other = default;
    }
  endgroup

  covergroup cg_gpio;
    option.per_instance = 1;
    cp_en_low  : coverpoint gpio_en[15:0]  { bins none = {0}; bins all = {16'hFFFF}; bins some = default; }
    cp_en_high : coverpoint gpio_en[31:16] { bins none = {0}; bins all = {16'hFFFF}; bins some = default; }
    cp_out     : coverpoint gpio_out       { bins zero = {0}; bins ones = {32'hFFFF_FFFF}; bins some = default; }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    commit_imp = new("commit_imp", this);
    uart_imp   = new("uart_imp", this);
    irq_imp    = new("irq_imp", this);
    i2c_imp    = new("i2c_imp", this);
    spi_imp    = new("spi_imp", this);
    gpio_imp   = new("gpio_imp", this);
    cg_commit  = new();
    cg_uart    = new();
    cg_irq     = new();
    cg_bus     = new();
    cg_trap    = new();
    cg_gpio    = new();
  endfunction

  function void write_commit(commit_item item);
    if (item.tohost) return;
    if (item.trap) begin
      trap_irq   = item.irq;
      trap_cause = item.cause;
      cg_trap.sample();
      return;
    end
    rd    = item.rd;
    wdata = item.data;
    cg_commit.sample();
  endfunction

  function void write_uart(uart_item item);
    uart_data = item.data;
    uart_bits = item.data_bits;
    uart_par  = item.parity;
    uart_stop = item.stop_bits;
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

  function void write_gpio(gpio_item item);
    gpio_out = item.value;
    gpio_en  = item.tx_en;
    cg_gpio.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf("functional: commit %0.1f%% uart %0.1f%% irq %0.1f%% bus %0.1f%% trap %0.1f%% gpio %0.1f%%",
              cg_commit.get_inst_coverage(), cg_uart.get_inst_coverage(), cg_irq.get_inst_coverage(),
              cg_bus.get_inst_coverage(), cg_trap.get_inst_coverage(), cg_gpio.get_inst_coverage()), UVM_LOW)
  endfunction

  function void write_spi(spi_item item);
    spi_bits = item.bits;
    cg_bus.sample();
  endfunction
endclass
