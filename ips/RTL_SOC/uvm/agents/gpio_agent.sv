class gpio_item extends uvm_sequence_item;
  rand bit [31:0] value;
  bit [31:0]      tx_en;

  `uvm_object_utils_begin(gpio_item)
    `uvm_field_int(value, UVM_ALL_ON)
    `uvm_field_int(tx_en, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "gpio_item");
    super.new(name);
  endfunction
endclass

typedef uvm_sequencer #(gpio_item) gpio_sequencer;

class gpio_driver extends uvm_driver #(gpio_item);
  `uvm_component_utils(gpio_driver)

  virtual gpio_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    vif.gpio_in <= '0;
    forever begin
      seq_item_port.get_next_item(req);
      @(posedge vif.clk);
      vif.gpio_in <= req.value;
      seq_item_port.item_done();
    end
  endtask
endclass

class gpio_monitor extends uvm_monitor;
  `uvm_component_utils(gpio_monitor)

  virtual gpio_if vif;
  uvm_analysis_port #(gpio_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    gpio_item  item;
    bit [31:0] last_out;
    bit [31:0] last_en;
    forever begin
      @(posedge vif.clk);
      if ($isunknown(vif.gpio_out) || $isunknown(vif.gpio_tx_en)) continue;
      if (vif.gpio_out == last_out && vif.gpio_tx_en == last_en) continue;
      last_out = vif.gpio_out;
      last_en  = vif.gpio_tx_en;
      item = gpio_item::type_id::create("item");
      item.value = last_out;
      item.tx_en = last_en;
      `uvm_info("GPIO_MON", $sformatf("out 0x%08h en 0x%08h", last_out, last_en), UVM_HIGH)
      ap.write(item);
    end
  endtask
endclass

class gpio_agent extends uvm_agent;
  `uvm_component_utils(gpio_agent)

  gpio_driver    drv;
  gpio_sequencer sqr;
  gpio_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    virtual gpio_if vif;
    if (!uvm_config_db #(virtual gpio_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "gpio_if not set")
    mon = gpio_monitor::type_id::create("mon", this);
    mon.vif = vif;
    if (get_is_active() == UVM_ACTIVE) begin
      drv = gpio_driver::type_id::create("drv", this);
      sqr = gpio_sequencer::type_id::create("sqr", this);
      drv.vif = vif;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass
