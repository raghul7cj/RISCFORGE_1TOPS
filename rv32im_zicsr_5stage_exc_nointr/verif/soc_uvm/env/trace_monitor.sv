class commit_item extends uvm_sequence_item;
  bit [31:0] pc;
  bit [4:0]  rd;
  bit [31:0] data;
  bit        tohost;

  `uvm_object_utils_begin(commit_item)
    `uvm_field_int(pc,     UVM_ALL_ON)
    `uvm_field_int(rd,     UVM_ALL_ON)
    `uvm_field_int(data,   UVM_ALL_ON)
    `uvm_field_int(tohost, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "commit_item");
    super.new(name);
  endfunction
endclass

class trace_monitor extends uvm_monitor;
  `uvm_component_utils(trace_monitor)

  virtual trace_if vif;
  soc_cfg          cfg;
  uvm_analysis_port #(commit_item) ap;
  int              fd;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(virtual trace_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "trace_if not set")
    if (!uvm_config_db #(soc_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "soc_cfg not set")
  endfunction

  task run_phase(uvm_phase phase);
    commit_item item;
    fd = $fopen("rtl_trace.log", "w");
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n !== 1'b1) continue;
      if (vif.wb_en && vif.wb_rd != 0) begin
        item = commit_item::type_id::create("item");
        item.pc   = vif.wb_pc;
        item.rd   = vif.wb_rd;
        item.data = vif.wb_data;
        $fdisplay(fd, "0x%08h x%0d 0x%08h", item.pc, item.rd, item.data);
        ap.write(item);
      end
      if (vif.mem_req && vif.mem_we && vif.mem_addr == cfg.tohost_addr) begin
        item = commit_item::type_id::create("item");
        item.tohost = 1'b1;
        item.data   = vif.mem_wdata;
        ap.write(item);
      end
    end
  endtask

  function void final_phase(uvm_phase phase);
    if (fd) $fclose(fd);
  endfunction
endclass
