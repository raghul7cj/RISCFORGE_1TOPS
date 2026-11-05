class soc_core_test extends soc_base_test;
  `uvm_component_utils(soc_core_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass

class soc_hello_test extends soc_base_test;
  `uvm_component_utils(soc_hello_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    if (cfg.uart_expect == "") cfg.uart_expect = "hello\n";
  endfunction
endclass

class soc_uart_echo_test extends soc_base_test;
  `uvm_component_utils(soc_uart_echo_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    if (cfg.uart_expect == "") cfg.uart_expect = "ping";
  endfunction

  task main_stim();
    uart_send_seq seq = uart_send_seq::type_id::create("seq");
    seq.text = "ping";
    wait_core_run(500);
    seq.start(env.uart.sqr);
  endtask
endclass

class soc_gpio_test extends soc_base_test;
  `uvm_component_utils(soc_gpio_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    cfg.check_gpio  = 1'b1;
    cfg.gpio_expect = 32'h0000_A5A5;
  endfunction

  task main_stim();
    gpio_set_seq seq = gpio_set_seq::type_id::create("seq");
    seq.value = 32'h5A5A_0000;
    seq.start(env.gpio.sqr);
  endtask
endclass

class soc_timer_test extends soc_base_test;
  `uvm_component_utils(soc_timer_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    cfg.irq_expect = 13'h0022;
  endfunction
endclass

class soc_spi_test extends soc_base_test;
  `uvm_component_utils(soc_spi_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    cfg.check_spi  = 1'b1;
    cfg.spi_expect = 32'hDEAD_BEEF;
    cfg.spi_rdata  = 32'hCAFE_F00D;
  endfunction
endclass

class soc_i2c_test extends soc_base_test;
  `uvm_component_utils(soc_i2c_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    cfg.check_i2c  = 1'b1;
    cfg.i2c_addr   = 7'h50;
    cfg.i2c_expect = 8'h3C;
    cfg.i2c_rdata  = 8'h96;
    cfg.irq_expect = 13'h0400;
  endfunction
endclass

class soc_fault_test extends soc_base_test;
  `uvm_component_utils(soc_fault_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    cfg.allow_lsu_err = 1'b1;
  endfunction
endclass

class soc_irq_test extends soc_base_test;
  `uvm_component_utils(soc_irq_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    cfg.irq_expect = 13'h0322;
  endfunction

  task main_stim();
    gpio_set_seq  gpio_seq = gpio_set_seq::type_id::create("gpio_seq");
    uart_send_seq uart_seq = uart_send_seq::type_id::create("uart_seq");
    wait_phase(1);
    repeat (50) @(posedge ctrl.clk);
    gpio_seq.value = 32'h0001_0000;
    gpio_seq.start(env.gpio.sqr);
    wait_phase(2);
    repeat (50) @(posedge ctrl.clk);
    uart_seq.text = "Z";
    uart_seq.start(env.uart.sqr);
  endtask
endclass

class soc_warm_reset_test extends soc_base_test;
  `uvm_component_utils(soc_warm_reset_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task main_stim();
    wait_phase(1);
    repeat (20) @(posedge ctrl.clk);
    soft_reset();
  endtask
endclass

class soc_flash_boot_test extends soc_base_test;
  `uvm_component_utils(soc_flash_boot_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    cfg.cold_boot = 1'b1;
    cfg.boot_clks = 2_000_000;
    if (cfg.uart_expect == "") cfg.uart_expect = "hello\n";
  endfunction
endclass
