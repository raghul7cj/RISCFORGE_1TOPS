class uart_send_seq extends uvm_sequence #(uart_item);
  `uvm_object_utils(uart_send_seq)

  string text = "ping";

  function new(string name = "uart_send_seq");
    super.new(name);
  endfunction

  task body();
    foreach (text[i]) begin
      req = uart_item::type_id::create("req");
      start_item(req);
      req.data = text[i];
      finish_item(req);
    end
  endtask
endclass

class gpio_set_seq extends uvm_sequence #(gpio_item);
  `uvm_object_utils(gpio_set_seq)

  bit [31:0] value;

  function new(string name = "gpio_set_seq");
    super.new(name);
  endfunction

  task body();
    req = gpio_item::type_id::create("req");
    start_item(req);
    req.value = value;
    finish_item(req);
  endtask
endclass

class uart_byte_seq extends uvm_sequence #(uart_item);
  `uvm_object_utils(uart_byte_seq)

  bit [7:0] data;
  bit       bad_parity;
  bit       bad_stop;
  bit       is_break;
  bit       no_idle;
  int       count = 1;

  function new(string name = "uart_byte_seq");
    super.new(name);
  endfunction

  task body();
    for (int i = 0; i < count; i++) begin
      req = uart_item::type_id::create("req");
      start_item(req);
      req.data       = data + i;
      req.bad_parity = bad_parity;
      req.bad_stop   = bad_stop;
      req.is_break   = is_break;
      req.no_idle    = no_idle;
      finish_item(req);
    end
  endtask
endclass
