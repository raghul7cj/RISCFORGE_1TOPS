class irq_item extends uvm_sequence_item;
  bit [12:0] rise;

  `uvm_object_utils_begin(irq_item)
    `uvm_field_int(rise, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "irq_item");
    super.new(name);
  endfunction
endclass

class irq_monitor extends uvm_monitor;
  `uvm_component_utils(irq_monitor)

  virtual irq_if vif;
  uvm_analysis_port #(irq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(virtual irq_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "irq_if not set")
  endfunction

  task run_phase(uvm_phase phase);
    irq_item  item;
    bit [12:0] now;
    bit [12:0] last;
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n !== 1'b1) continue;
      now = {vif.spi, vif.i2c, vif.gpio, vif.uart, vif.timer1, vif.timer0};
      if ((now & ~last) != 0) begin
        item = irq_item::type_id::create("item");
        item.rise = now & ~last;
        `uvm_info("IRQ", $sformatf("rise 0x%04h", item.rise), UVM_MEDIUM)
        ap.write(item);
      end
      last = now;
    end
  endtask
endclass
