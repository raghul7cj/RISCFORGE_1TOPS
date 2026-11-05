class soc_env extends uvm_env;
  `uvm_component_utils(soc_env)

  uart_agent     uart;
  gpio_agent     gpio;
  spi_slave      spi;
  i2c_slave      i2c;
  irq_monitor    irq;
  trace_monitor  trace;
  soc_scoreboard scb;
  soc_coverage   cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    uart  = uart_agent::type_id::create("uart", this);
    gpio  = gpio_agent::type_id::create("gpio", this);
    spi   = spi_slave::type_id::create("spi", this);
    i2c   = i2c_slave::type_id::create("i2c", this);
    irq   = irq_monitor::type_id::create("irq", this);
    trace = trace_monitor::type_id::create("trace", this);
    scb   = soc_scoreboard::type_id::create("scb", this);
    cov   = soc_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    uart.mon.ap.connect(scb.uart_imp);
    gpio.mon.ap.connect(scb.gpio_imp);
    spi.ap.connect(scb.spi_imp);
    i2c.ap.connect(scb.i2c_imp);
    irq.ap.connect(scb.irq_imp);
    trace.ap.connect(scb.commit_imp);

    uart.mon.ap.connect(cov.uart_imp);
    spi.ap.connect(cov.spi_imp);
    i2c.ap.connect(cov.i2c_imp);
    irq.ap.connect(cov.irq_imp);
    trace.ap.connect(cov.commit_imp);
    gpio.mon.ap.connect(cov.gpio_imp);
  endfunction
endclass
