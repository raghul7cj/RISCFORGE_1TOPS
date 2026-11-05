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
