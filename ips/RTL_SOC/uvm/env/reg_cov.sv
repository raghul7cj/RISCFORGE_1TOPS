typedef enum {RW, RO, WO} reg_kind_e;
typedef enum {ANY, DLAB0, DLAB1} reg_view_e;

class reg_field;
  string     name;
  int        slot, off, lsb, w;
  reg_kind_e kind;
  reg_view_e view;
  bit [31:0] maxv;
  bit        wr;
  bit [31:0] v;
  bit        hit_zero, hit_max, hit_other, hit_read;

  covergroup cg1;
    option.per_instance = 1;
    cp_w: coverpoint v iff (wr) { bins zero = {0}; bins one = {1}; }
    cp_r: coverpoint wr iff (!wr) { bins read = {0}; }
  endgroup

  covergroup cgn (bit [31:0] mx);
    option.per_instance = 1;
    cp_w: coverpoint v iff (wr) { bins zero = {0}; bins ones = {mx}; bins other = {[1:mx - 1]}; }
    cp_r: coverpoint wr iff (!wr) { bins read = {0}; }
  endgroup

  function new(string name, int slot, int off, int lsb, int w, reg_kind_e kind, reg_view_e view);
    this.name = name;
    this.slot = slot;
    this.off  = off;
    this.lsb  = lsb;
    this.w    = w;
    this.kind = kind;
    this.view = view;
    maxv = (w == 32) ? 32'hFFFF_FFFF : ((32'd1 << w) - 1);
    if (w == 1) begin
      cg1 = new();
      cg1.set_inst_name(name);
      if (kind == RO) cg1.cp_w.option.weight = 0;
      if (kind == WO) cg1.cp_r.option.weight = 0;
    end else begin
      cgn = new(maxv);
      cgn.set_inst_name(name);
      if (kind == RO) cgn.cp_w.option.weight = 0;
      if (kind == WO) cgn.cp_r.option.weight = 0;
    end
  endfunction

  function void sample(bit is_wr, bit [31:0] data);
    wr = is_wr;
    v  = (data >> lsb) & maxv;
    if (wr) begin
      if (v == 0) hit_zero = 1;
      else if (v == maxv) hit_max = 1;
      else hit_other = 1;
    end else begin
      hit_read = 1;
    end
    if (w == 1) cg1.sample();
    else        cgn.sample();
  endfunction

  function int needed();
    int n = 0;
    if (kind != RO) n += (w == 1) ? 2 : 3;
    if (kind != WO) n += 1;
    return n;
  endfunction

  function int got();
    int n = 0;
    if (kind != RO) n += hit_zero + hit_max + ((w == 1) ? 0 : hit_other);
    if (kind != WO) n += hit_read;
    return n;
  endfunction

  function string missing();
    string s = "";
    if (kind != RO && !hit_zero)            s = {s, " write-0"};
    if (kind != RO && !hit_max)             s = {s, (w == 1) ? " write-1" : " write-max"};
    if (kind != RO && w > 1 && !hit_other)  s = {s, " write-other"};
    if (kind != WO && !hit_read)            s = {s, " read"};
    return s;
  endfunction
endclass

class reg_cov extends uvm_component;
  `uvm_component_utils(reg_cov)

  virtual reg_bus_if vif;
  reg_field          fields[$];
  bit                dlab;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void add(string name, int slot, int off, int lsb, int w, reg_kind_e kind, reg_view_e view);
    reg_field f = new(name, slot, off, lsb, w, kind, view);
    fields.push_back(f);
  endfunction

  `include "env/reg_fields.svh"

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(virtual reg_bus_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "reg_bus_if not set")
    add_fields();
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n !== 1'b1) begin
        dlab = 1'b0;
        continue;
      end
      for (int s = 0; s < 6; s++) begin
        if (vif.psel[s] === 1'b1 && vif.penable[s] === 1'b1 && vif.pready[s] === 1'b1) begin
          bit [11:0] o  = {vif.paddr[s][11:2], 2'b00};
          bit        we = vif.pwrite[s];
          bit [31:0] d  = we ? vif.pwdata[s] : vif.prdata[s];
          foreach (fields[i])
            if (fields[i].slot == s && fields[i].off == o &&
                (fields[i].view == ANY || (fields[i].view == DLAB1) == dlab) &&
                !(we && fields[i].kind == RO) && !(!we && fields[i].kind == WO))
              fields[i].sample(we, d);
          if (s == 2 && o == 'h00C && we) dlab = d[7];
        end
      end
    end
  endtask

  function void report_phase(uvm_phase phase);
    int full = 0, need = 0, got = 0, shown = 0;
    foreach (fields[i]) begin
      need += fields[i].needed();
      got  += fields[i].got();
      if (fields[i].got() == fields[i].needed()) full++;
      else if (shown < 40) begin
        `uvm_info("REGCOV", $sformatf("open: %s%s", fields[i].name, fields[i].missing()), UVM_LOW)
        shown++;
      end
    end
    `uvm_info("REGCOV", $sformatf("register fields fully covered %0d of %0d, bins %0d of %0d (%0.1f%%)",
              full, fields.size(), got, need, 100.0 * got / need), UVM_NONE)
  endfunction
endclass
