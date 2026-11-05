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
    wait (ctrl.core_rst_n === 1'b1);
    repeat (500) @(posedge ctrl.clk);
    seq.start(env.uart.sqr);
  endtask
endclass
