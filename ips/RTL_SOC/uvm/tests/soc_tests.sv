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

class soc_timer_full_test extends soc_base_test;
  `uvm_component_utils(soc_timer_full_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    cfg.irq_expect = 13'h0099;
  endfunction
endclass

class soc_uart_full_test extends soc_base_test;
  `uvm_component_utils(soc_uart_full_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    if (cfg.uart_expect == "") cfg.uart_expect = "ABCDEFGH";
  endfunction

  task main_stim();
    uart_send_seq seq = uart_send_seq::type_id::create("seq");
    wait_phase(1);
    repeat (50) @(posedge ctrl.clk);
    seq.text = "12345678";
    seq.start(env.uart.sqr);
  endtask
endclass

class soc_i2c_full_test extends soc_base_test;
  `uvm_component_utils(soc_i2c_full_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    cfg.check_i2c  = 1'b1;
    cfg.i2c_addr   = 7'h50;
    cfg.i2c_expect = 8'h33;
    cfg.i2c_rdata  = 8'h96;
    cfg.irq_expect = 13'h0400;
  endfunction
endclass

class soc_spi_full_test extends soc_base_test;
  `uvm_component_utils(soc_spi_full_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    cfg.spi_rdata = 32'hCAFE_F00D;
  endfunction
endclass

class soc_uart_modes_test extends soc_base_test;
  `uvm_component_utils(soc_uart_modes_test)

  int unsigned bits[6]  = '{8, 7, 6, 5, 8, 8};
  int unsigned par[6]   = '{0, 2, 1, 0, 3, 4};
  int unsigned stop[6]  = '{1, 1, 2, 1, 1, 2};
  int unsigned clks[6]  = '{32, 32, 32, 32, 48, 32};
  bit [7:0]    rx[6]    = '{8'h5A, 8'h35, 8'h1C, 8'h09, 8'hA3, 8'h6B};
  bit [7:0]    tx[12]   = '{8'h41, 8'h42, 8'h63, 8'h64, 8'h2A, 8'h15, 8'h11, 8'h0E, 8'h4D, 8'h4E, 8'h53, 8'h54};

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    cfg.uart_expect = "";
    foreach (tx[i]) cfg.uart_expect = {cfg.uart_expect, string'(tx[i])};
    cfg.timeout_clks = 1_000_000;
  endfunction

  task main_stim();
    uart_byte_seq seq;
    for (int n = 1; n <= 6; n++) begin
      wait_phase(n);
      cfg.uart_data_bits = bits[n-1];
      cfg.uart_parity    = par[n-1];
      cfg.uart_stop_bits = stop[n-1];
      cfg.uart_bit_clks  = clks[n-1];
      repeat (200) @(posedge ctrl.clk);
      seq = uart_byte_seq::type_id::create("seq");
      seq.data = rx[n-1];
      seq.start(env.uart.sqr);
    end
  endtask
endclass

class soc_uart_err_test extends soc_base_test;
  `uvm_component_utils(soc_uart_err_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    cfg.irq_expect   = 13'h0100;
    cfg.timeout_clks = 2_000_000;
  endfunction

  task send(int n, bit [7:0] data, int count, bit badp, bit bads, bit brk);
    uart_byte_seq seq = uart_byte_seq::type_id::create("seq");
    wait_phase(n);
    repeat (200) @(posedge ctrl.clk);
    seq.data       = data;
    seq.count      = count;
    seq.bad_parity = badp;
    seq.bad_stop   = bads;
    seq.is_break   = brk;
    seq.start(env.uart.sqr);
  endtask

  task main_stim();
    cfg.uart_parity = 2;
    send(1, 8'h55, 1, 1, 0, 0);
    send(2, 8'h33, 1, 0, 1, 0);
    cfg.uart_parity = 0;
    send(3, 8'h00, 1, 0, 0, 1);
    send(4, 8'h40, 20, 0, 0, 0);
    send(5, 8'h61, 4, 0, 0, 0);
    send(6, 8'h78, 2, 0, 0, 0);
    send(7, 8'h4B, 1, 0, 0, 0);
  endtask
endclass

class soc_spi_more_test extends soc_base_test;
  `uvm_component_utils(soc_spi_more_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    cfg.spi_rdata  = 32'hCAFE_F00D;
    cfg.irq_expect = 13'h1800;
  endfunction
endclass

class soc_gpio_full_test extends soc_base_test;
  `uvm_component_utils(soc_gpio_full_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    cfg.irq_expect = 13'h0200;
  endfunction

  task drive(int n, bit [31:0] value);
    gpio_set_seq seq = gpio_set_seq::type_id::create("seq");
    wait_phase(n);
    repeat (20) @(posedge ctrl.clk);
    seq.value = value;
    seq.start(env.gpio.sqr);
  endtask

  task main_stim();
    wait_phase(1);
    repeat (50) @(posedge ctrl.clk);
    if (env.gpio.mon.vif.gpio_out !== 32'hFFFF_1231)
      `uvm_error("GPIO", $sformatf("pins out 0x%08h expected 0xFFFF1231", env.gpio.mon.vif.gpio_out))
    if (env.gpio.mon.vif.gpio_tx_en !== 32'h00FF_FFFF)
      `uvm_error("GPIO", $sformatf("pins en 0x%08h expected 0x00FFFFFF", env.gpio.mon.vif.gpio_tx_en))
    drive(2, 32'hA5C3_0F96);
    drive(3, 32'h5A3C_F069);
    drive(4, 32'h0000_0002);
    drive(5, 32'h0000_0005);
  endtask
endclass

class soc_i2c_more_test extends soc_base_test;
  `uvm_component_utils(soc_i2c_more_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_cfg();
    cfg.check_i2c   = 1'b1;
    cfg.i2c_addr    = 7'h50;
    cfg.i2c_expect  = 8'h10;
    cfg.i2c_rdata   = 8'h96;
    cfg.i2c_stretch = 40;
  endfunction
endclass
