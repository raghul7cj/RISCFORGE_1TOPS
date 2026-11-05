class spi_item extends uvm_sequence_item;
  bit [31:0]   data;
  int unsigned bits;

  `uvm_object_utils_begin(spi_item)
    `uvm_field_int(data, UVM_ALL_ON)
    `uvm_field_int(bits, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "spi_item");
    super.new(name);
  endfunction
endclass

class spi_slave extends uvm_component;
  `uvm_component_utils(spi_slave)

  virtual spi_if vif;
  soc_cfg        cfg;
  uvm_analysis_port #(spi_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(virtual spi_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "spi_if not set")
    if (!uvm_config_db #(soc_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "soc_cfg not set")
  endfunction

  task run_phase(uvm_phase phase);
    spi_item     item;
    bit [31:0]   tx;
    bit [31:0]   rx;
    int unsigned n;
    vif.sdi <= 1'b0;
    forever begin
      @(negedge vif.csn);
      tx = cfg.spi_rdata;
      rx = '0;
      n  = 0;
      vif.sdi <= tx[31];
      fork
        forever begin
          @(posedge vif.sck);
          rx = {rx[30:0], vif.sdo};
          n++;
          @(negedge vif.sck);
          tx = {tx[30:0], tx[31]};
          vif.sdi <= tx[31];
        end
        @(posedge vif.csn);
      join_any
      disable fork;
      vif.sdi <= 1'b0;
      if (n == 0) continue;
      item = spi_item::type_id::create("item");
      item.data = rx;
      item.bits = n;
      `uvm_info("SPI", $sformatf("frame %0d bits, mosi 0x%08h", n, rx), UVM_MEDIUM)
      ap.write(item);
    end
  endtask
endclass
