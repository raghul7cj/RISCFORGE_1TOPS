class i2c_item extends uvm_sequence_item;
  bit       rw;
  bit [6:0] addr;
  bit [7:0] data;

  `uvm_object_utils_begin(i2c_item)
    `uvm_field_int(rw,   UVM_ALL_ON)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_int(data, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "i2c_item");
    super.new(name);
  endfunction
endclass

class i2c_slave extends uvm_component;
  `uvm_component_utils(i2c_slave)

  localparam int BIT_OK    = 0;
  localparam int BIT_STOP  = 1;
  localparam int BIT_START = 2;

  virtual i2c_if vif;
  soc_cfg        cfg;
  uvm_analysis_port #(i2c_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(virtual i2c_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "i2c_if not set")
    if (!uvm_config_db #(soc_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "soc_cfg not set")
  endfunction

  task run_phase(uvm_phase phase);
    vif.scl_drv <= 1'b1;
    vif.sda_drv <= 1'b1;
    forever begin
      wait_start();
      do_frame();
    end
  endtask

  task wait_start();
    forever begin
      @(negedge vif.sda);
      if (vif.scl === 1'b1) return;
    end
  endtask

  task read_bit(output bit b, output int ev);
    @(posedge vif.scl);
    b  = vif.sda;
    ev = BIT_OK;
    fork
      @(negedge vif.scl);
      begin
        @(vif.sda);
        if (vif.scl === 1'b1) ev = vif.sda ? BIT_STOP : BIT_START;
        else @(negedge vif.scl);
      end
    join_any
    disable fork;
  endtask

  task read_byte(output bit [7:0] data, output int ev);
    bit b;
    for (int i = 7; i >= 0; i--) begin
      read_bit(b, ev);
      data[i] = b;
      if (ev != BIT_OK) return;
    end
  endtask

  task send_ack();
    vif.sda_drv <= 1'b0;
    @(negedge vif.scl);
    if (cfg.i2c_stretch != 0) begin
      vif.scl_drv <= 1'b0;
      repeat (cfg.i2c_stretch) @(posedge vif.clk);
      vif.sda_drv <= 1'b1;
      vif.scl_drv <= 1'b1;
    end else begin
      vif.sda_drv <= 1'b1;
    end
  endtask

  task send_byte(bit [7:0] data, output bit nack);
    for (int i = 7; i >= 0; i--) begin
      vif.sda_drv <= data[i];
      @(negedge vif.scl);
    end
    vif.sda_drv <= 1'b1;
    @(posedge vif.scl);
    nack = vif.sda;
    @(negedge vif.scl);
  endtask

  task do_frame();
    bit [7:0] head;
    bit [7:0] data;
    bit       nack;
    int       ev;
    i2c_item  item;
    forever begin
      read_byte(head, ev);
      if (ev == BIT_START) continue;
      if (ev == BIT_STOP) return;
      if (head[7:1] != cfg.i2c_addr) return;
      send_ack();
      if (head[0]) begin
        do begin
          send_byte(cfg.i2c_rdata, nack);
          item = i2c_item::type_id::create("item");
          item.rw   = 1'b1;
          item.addr = head[7:1];
          item.data = cfg.i2c_rdata;
          ap.write(item);
        end while (!nack);
        return;
      end
      forever begin
        read_byte(data, ev);
        if (ev != BIT_OK) break;
        send_ack();
        item = i2c_item::type_id::create("item");
        item.rw   = 1'b0;
        item.addr = head[7:1];
        item.data = data;
        `uvm_info("I2C", $sformatf("write 0x%02h to 0x%02h", data, head[7:1]), UVM_MEDIUM)
        ap.write(item);
      end
      if (ev == BIT_STOP) return;
    end
  endtask
endclass
