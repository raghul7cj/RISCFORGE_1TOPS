class uart_item extends uvm_sequence_item;
  rand bit [7:0] data;

  `uvm_object_utils_begin(uart_item)
    `uvm_field_int(data, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "uart_item");
    super.new(name);
  endfunction
endclass

typedef uvm_sequencer #(uart_item) uart_sequencer;

class uart_driver extends uvm_driver #(uart_item);
  `uvm_component_utils(uart_driver)

  virtual uart_if vif;
  soc_cfg         cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    vif.sin <= 1'b1;
    forever begin
      seq_item_port.get_next_item(req);
      send_byte(req.data);
      seq_item_port.item_done();
    end
  endtask

  task send_byte(bit [7:0] data);
    vif.sin <= 1'b0;
    wait_bit();
    for (int i = 0; i < 8; i++) begin
      vif.sin <= data[i];
      wait_bit();
    end
    vif.sin <= 1'b1;
    wait_bit();
  endtask

  task wait_bit();
    repeat (cfg.uart_bit_clks) @(posedge vif.clk);
  endtask
endclass

class uart_monitor extends uvm_monitor;
  `uvm_component_utils(uart_monitor)

  virtual uart_if vif;
  soc_cfg         cfg;
  uvm_analysis_port #(uart_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    uart_item  item;
    bit [7:0]  data;
    forever begin
      @(negedge vif.sout);
      repeat (cfg.uart_bit_clks / 2) @(posedge vif.clk);
      if (vif.sout !== 1'b0) continue;
      for (int i = 0; i < 8; i++) begin
        repeat (cfg.uart_bit_clks) @(posedge vif.clk);
        data[i] = vif.sout;
      end
      repeat (cfg.uart_bit_clks) @(posedge vif.clk);
      if (vif.sout !== 1'b1)
        `uvm_error("UART_MON", "stop bit error")
      item = uart_item::type_id::create("item");
      item.data = data;
      `uvm_info("UART_MON", $sformatf("rx 0x%02h '%c'", data, data), UVM_HIGH)
      ap.write(item);
    end
  endtask
endclass

class uart_agent extends uvm_agent;
  `uvm_component_utils(uart_agent)

  uart_driver    drv;
  uart_sequencer sqr;
  uart_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    virtual uart_if vif;
    soc_cfg         cfg;
    if (!uvm_config_db #(virtual uart_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "uart_if not set")
    if (!uvm_config_db #(soc_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "soc_cfg not set")
    mon = uart_monitor::type_id::create("mon", this);
    mon.vif = vif;
    mon.cfg = cfg;
    if (get_is_active() == UVM_ACTIVE) begin
      drv = uart_driver::type_id::create("drv", this);
      sqr = uart_sequencer::type_id::create("sqr", this);
      drv.vif = vif;
      drv.cfg = cfg;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass
