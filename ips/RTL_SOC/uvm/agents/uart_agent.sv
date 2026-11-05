class uart_item extends uvm_sequence_item;
  rand bit [7:0] data;
  bit            bad_parity;
  bit            bad_stop;
  bit            is_break;
  bit            par_err;
  bit            frame_err;
  bit            stop2_err;
  int unsigned   data_bits;
  int unsigned   parity;
  int unsigned   stop_bits;

  `uvm_object_utils_begin(uart_item)
    `uvm_field_int(data, UVM_ALL_ON)
    `uvm_field_int(bad_parity, UVM_ALL_ON)
    `uvm_field_int(bad_stop, UVM_ALL_ON)
    `uvm_field_int(is_break, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "uart_item");
    super.new(name);
  endfunction
endclass

typedef uvm_sequencer #(uart_item) uart_sequencer;

function automatic bit uart_parity_bit(bit [7:0] data, int unsigned bits, int unsigned mode);
  bit p = 0;
  for (int i = 0; i < bits; i++) p ^= data[i];
  case (mode)
    1: return ~p;
    2: return p;
    3: return 1'b1;
    4: return 1'b0;
    default: return 1'b0;
  endcase
endfunction

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
      if (req.is_break) send_break();
      else send_byte(req);
      seq_item_port.item_done();
    end
  endtask

  task send_byte(uart_item it);
    bit p;
    vif.sin <= 1'b0;
    wait_bit();
    for (int i = 0; i < cfg.uart_data_bits; i++) begin
      vif.sin <= it.data[i];
      wait_bit();
    end
    if (cfg.uart_parity != 0) begin
      p = uart_parity_bit(it.data, cfg.uart_data_bits, cfg.uart_parity);
      vif.sin <= it.bad_parity ? ~p : p;
      wait_bit();
    end
    vif.sin <= it.bad_stop ? 1'b0 : 1'b1;
    wait_bit();
    vif.sin <= 1'b1;
    repeat (cfg.uart_stop_bits) wait_bit();
  endtask

  task send_break();
    vif.sin <= 1'b0;
    repeat (2 * (cfg.uart_data_bits + 4)) wait_bit();
    vif.sin <= 1'b1;
    repeat (2) wait_bit();
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
    uart_item item;
    bit [7:0] data;
    bit       p;
    forever begin
      @(negedge vif.sout);
      repeat (cfg.uart_bit_clks / 2) @(posedge vif.clk);
      if (vif.sout !== 1'b0) continue;
      item = uart_item::type_id::create("item");
      item.data_bits = cfg.uart_data_bits;
      item.parity    = cfg.uart_parity;
      item.stop_bits = cfg.uart_stop_bits;
      data = '0;
      for (int i = 0; i < cfg.uart_data_bits; i++) begin
        repeat (cfg.uart_bit_clks) @(posedge vif.clk);
        data[i] = vif.sout;
      end
      if (cfg.uart_parity != 0) begin
        repeat (cfg.uart_bit_clks) @(posedge vif.clk);
        p = vif.sout;
        item.par_err = (p != uart_parity_bit(data, cfg.uart_data_bits, cfg.uart_parity));
      end
      repeat (cfg.uart_bit_clks) @(posedge vif.clk);
      item.frame_err = (vif.sout !== 1'b1);
      if (cfg.uart_stop_bits == 2) begin
        repeat (cfg.uart_bit_clks) @(posedge vif.clk);
        item.stop2_err = (vif.sout !== 1'b1);
      end
      item.data = data;
      `uvm_info("UART_MON", $sformatf("rx 0x%02h '%c' %0d%0d%0d", data, data,
                cfg.uart_data_bits, cfg.uart_parity, cfg.uart_stop_bits), UVM_HIGH)
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
