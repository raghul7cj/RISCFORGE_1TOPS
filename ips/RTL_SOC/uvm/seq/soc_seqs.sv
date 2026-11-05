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
