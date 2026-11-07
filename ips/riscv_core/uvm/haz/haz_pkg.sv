package haz_types_pkg;
  `include "haz_ref.svh"
endpackage

interface haz_if(input logic clk);
  logic                                      valid;
  logic [$bits(haz_types_pkg::haz_in_t)-1:0]  in;
  logic [$bits(haz_types_pkg::haz_out_t)-1:0] out;
endinterface

package haz_pkg;
  import uvm_pkg::*;
  import haz_types_pkg::*;
  `include "uvm_macros.svh"

  class haz_item extends uvm_sequence_item;
    rand haz_in_t x;
    haz_out_t     y;

    constraint c_rst  { x.rst dist {1 := 15, 0 := 1}; }
    constraint c_regs {
      x.rd_m  dist {0 := 1, [1 : 3] :/ 6, [4 : 31] :/ 1};
      x.rd_w  dist {0 := 1, [1 : 3] :/ 6, [4 : 31] :/ 1};
      x.rd_e  dist {0 := 1, [1 : 3] :/ 6, [4 : 31] :/ 1};
      x.rs1_e dist {0 := 1, [1 : 3] :/ 6, [4 : 31] :/ 1};
      x.rs2_e dist {0 := 1, [1 : 3] :/ 6, [4 : 31] :/ 1};
      x.rs1_d dist {0 := 1, [1 : 3] :/ 6, [4 : 31] :/ 1};
      x.rs2_d dist {0 := 1, [1 : 3] :/ 6, [4 : 31] :/ 1};
    }
    constraint c_csr {
      x.csr_raddr_d inside {12'h300, 12'h305, 12'h341, 12'hB00};
      x.csr_addr_e  inside {12'h300, 12'h305, 12'h341, 12'hB00};
      x.csr_addr_m  inside {12'h300, 12'h305, 12'h341, 12'hB00};
      x.csr_addr_w  inside {12'h300, 12'h305, 12'h341, 12'hB00};
    }
    constraint c_ctl {
      x.wb_redirect  dist {1 := 1, 0 := 9};
      x.mem_stall    dist {1 := 1, 0 := 3};
      x.stall_mul    dist {1 := 1, 0 := 5};
      x.pcsrc_e      dist {1 := 1, 0 := 4};
      x.flush_onehot dist {4'b0000 := 8, 4'b0001 := 1, 4'b0010 := 1, 4'b0100 := 1, 4'b1000 := 1};
      x.exc_e        dist {1 := 1, 0 := 4};
      x.exc_m        dist {1 := 1, 0 := 4};
    }

    `uvm_object_utils(haz_item)
    function new(string name = "haz_item");
      super.new(name);
    endfunction

    function string convert2string();
      return $sformatf("in=%p out=%p", x, y);
    endfunction
  endclass

  class haz_seq extends uvm_sequence #(haz_item);
    `uvm_object_utils(haz_seq)
    int unsigned n = 5000;
    function new(string name = "haz_seq");
      super.new(name);
    endfunction
    task body();
      repeat (n) begin
        req = haz_item::type_id::create("req");
        start_item(req);
        if (!req.randomize()) `uvm_fatal("SEQ", "randomize failed")
        finish_item(req);
      end
    endtask
  endclass

  class haz_driver extends uvm_driver #(haz_item);
    `uvm_component_utils(haz_driver)
    virtual haz_if vif;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      vif.valid <= 1'b0;
      forever begin
        seq_item_port.get_next_item(req);
        @(negedge vif.clk);
        vif.in    <= req.x;
        vif.valid <= 1'b1;
        seq_item_port.item_done();
      end
    endtask
  endclass

  class haz_monitor extends uvm_monitor;
    `uvm_component_utils(haz_monitor)
    virtual haz_if vif;
    uvm_analysis_port #(haz_item) ap;
    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction
    task run_phase(uvm_phase phase);
      forever begin
        @(posedge vif.clk);
        if (vif.valid === 1'b1) begin
          haz_item t = haz_item::type_id::create("t");
          t.x = vif.in;
          t.y = vif.out;
          ap.write(t);
        end
      end
    endtask
  endclass

  class haz_scoreboard extends uvm_subscriber #(haz_item);
    `uvm_component_utils(haz_scoreboard)
    int unsigned n_pass, n_fail;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    function void write(haz_item t);
      haz_out_t e = haz_ref(t.x);
      if (t.y === e) n_pass++;
      else begin
        n_fail++;
        if (n_fail <= 20) `uvm_error("HAZ", $sformatf("%s expected %p", t.convert2string(), e))
      end
      if (t.y.fwd_a != 2'b00 && t.x.rs1_e == 5'd0) `uvm_error("HAZ", "forwarding into x0 on A")
      if (t.y.fwd_b != 2'b00 && t.x.rs2_e == 5'd0) `uvm_error("HAZ", "forwarding into x0 on B")
      if (t.x.mem_stall && !t.x.wb_redirect && !t.y.stall_e) `uvm_error("HAZ", "EX not held during memory stall")
    endfunction
    function void report_phase(uvm_phase phase);
      `uvm_info("HAZ", $sformatf("checked %0d, pass %0d, fail %0d", n_pass + n_fail, n_pass, n_fail), UVM_NONE)
    endfunction
  endclass

  class haz_coverage extends uvm_subscriber #(haz_item);
    `uvm_component_utils(haz_coverage)
    haz_in_t  x;
    haz_out_t y;
    bit lu, cg_gpr, raw, both_a, both_b;

    covergroup cg;
      cp_fwd_a: coverpoint y.fwd_a { bins none = {0}; bins wb = {1}; bins mem = {2}; illegal_bins bad = {3}; }
      cp_fwd_b: coverpoint y.fwd_b { bins none = {0}; bins wb = {1}; bins mem = {2}; illegal_bins bad = {3}; }
      cp_both_a: coverpoint both_a { bins yes = {1}; }
      cp_both_b: coverpoint both_b { bins yes = {1}; }
      cp_x0:    coverpoint (x.rs1_e == 0 && x.rd_m == 0 && x.reg_write_m) { bins yes = {1}; }
      cp_rst:   coverpoint x.rst;
      cp_lu:    coverpoint lu;
      cp_lu_rs: coverpoint {x.rs1_d == x.rd_e, x.rs2_d == x.rd_e} iff (lu) { bins rs1 = {2'b10}; bins rs2 = {2'b01}; bins both = {2'b11}; }
      cp_lu_x0: coverpoint (x.result_src_e == 2'b01 && x.rd_e == 0 && x.rs1_d == 0) { bins yes = {1}; }
      cp_gpr:   coverpoint cg_gpr;
      cp_raw_e: coverpoint (x.csr_valid_d && x.csr_we_e && x.csr_raddr_d == x.csr_addr_e) { bins yes = {1}; }
      cp_raw_m: coverpoint (x.csr_valid_d && x.csr_we_m && x.csr_raddr_d == x.csr_addr_m) { bins yes = {1}; }
      cp_raw_w: coverpoint (x.csr_valid_d && x.csr_we_w && x.csr_raddr_d == x.csr_addr_w) { bins yes = {1}; }
      cp_mem:   coverpoint x.mem_stall;
      cp_mul:   coverpoint x.stall_mul;
      cp_wb:    coverpoint x.wb_redirect;
      cp_pc:    coverpoint x.pcsrc_e;
      cp_exc_e: coverpoint (x.valid_e && x.exc_e);
      cp_exc_m: coverpoint (x.valid_m && x.exc_m);
      cp_one:   coverpoint x.flush_onehot { bins none = {0}; bins d = {1}; bins e = {2}; bins m = {4}; bins w = {8}; }
      x_lu_mem:  cross cp_lu, cp_mem;
      x_gpr_mem: cross cp_gpr, cp_mem;
      x_raw_mem: cross cp_raw_e, cp_mem;
      x_mul_mem: cross cp_mul, cp_mem;
      x_wb_mem:  cross cp_wb, cp_mem;
      x_wb_lu:   cross cp_wb, cp_lu;
      x_pc_lu:   cross cp_pc, cp_lu;
      x_fwd:     cross cp_fwd_a, cp_fwd_b;
      cp_stall_f: coverpoint y.stall_f;
      cp_stall_e: coverpoint y.stall_e;
      cp_flush_d: coverpoint y.flush_d;
      cp_flush_e: coverpoint y.flush_e;
      cp_flush_m: coverpoint y.flush_m;
      cp_flush_w: coverpoint y.flush_w;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg = new();
    endfunction
    function void write(haz_item t);
      x = t.x;
      y = t.y;
      lu     = haz_load_use(x);
      cg_gpr = haz_csr_gpr(x);
      both_a = x.rst && x.rs1_e != 0 && x.reg_write_m && x.reg_write_w && x.rd_m == x.rs1_e && x.rd_w == x.rs1_e;
      both_b = x.rst && x.rs2_e != 0 && x.reg_write_m && x.reg_write_w && x.rd_m == x.rs2_e && x.rd_w == x.rs2_e;
      cg.sample();
    endfunction
    function void report_phase(uvm_phase phase);
      `uvm_info("COV", $sformatf("hazard functional coverage %0.2f%%", cg.get_coverage()), UVM_NONE)
    endfunction
  endclass

  class haz_env extends uvm_env;
    `uvm_component_utils(haz_env)
    uvm_sequencer #(haz_item) sqr;
    haz_driver     drv;
    haz_monitor    mon;
    haz_scoreboard scb;
    haz_coverage   cov;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      virtual haz_if vif;
      if (!uvm_config_db #(virtual haz_if)::get(this, "", "vif", vif)) `uvm_fatal("ENV", "no vif")
      sqr = uvm_sequencer #(haz_item)::type_id::create("sqr", this);
      drv = haz_driver::type_id::create("drv", this);
      mon = haz_monitor::type_id::create("mon", this);
      scb = haz_scoreboard::type_id::create("scb", this);
      cov = haz_coverage::type_id::create("cov", this);
      drv.vif = vif;
      mon.vif = vif;
    endfunction
    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
      mon.ap.connect(scb.analysis_export);
      mon.ap.connect(cov.analysis_export);
    endfunction
  endclass

  class haz_test extends uvm_test;
    `uvm_component_utils(haz_test)
    haz_env env;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      env = haz_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
      haz_seq seq = haz_seq::type_id::create("seq");
      void'($value$plusargs("N=%d", seq.n));
      phase.raise_objection(this);
      seq.start(env.sqr);
      @(posedge env.drv.vif.clk);
      env.drv.vif.valid <= 1'b0;
      @(posedge env.drv.vif.clk);
      phase.drop_objection(this);
    endtask
  endclass
endpackage

module haz_tb;
  import uvm_pkg::*;
  import haz_pkg::*;
  import haz_types_pkg::*;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  haz_if ifc(clk);
  haz_in_t    x;
  logic [1:0] fwd_a, fwd_b;
  logic       stall_f, stall_d, stall_e, stall_m, flush_d, flush_e, flush_m, flush_w;
  assign x = ifc.in;
  assign ifc.out = {fwd_a, fwd_b, stall_f, stall_d, stall_e, stall_m, flush_d, flush_e, flush_m, flush_w};
  hazard_unit dut(
    .rst(x.rst), .RegWriteM(x.reg_write_m), .RegWriteW(x.reg_write_w), .RD_M(x.rd_m), .RD_W(x.rd_w),
    .Rs1_E(x.rs1_e), .Rs2_E(x.rs2_e), .Rs1_D(x.rs1_d), .Rs2_D(x.rs2_d), .RdE(x.rd_e),
    .ForwardAE(fwd_a), .ForwardBE(fwd_b), .ResultSrcE(x.result_src_e), .PCSrcE(x.pcsrc_e),
    .StallF(stall_f), .StallD(stall_d), .StallE(stall_e), .StallM(stall_m),
    .FlushD(flush_d), .FlushE(flush_e), .FlushM(flush_m), .FlushW(flush_w),
    .illegal_instr(1'b0), .csr_valid_D(x.csr_valid_d), .csr_raddr_D(x.csr_raddr_d),
    .csr_raddr_E(12'd0), .csr_raddr_W(12'd0), .csr_addr_E(x.csr_addr_e), .csr_addr_M(x.csr_addr_m),
    .csr_addr_W(x.csr_addr_w), .csr_write_en_W(x.csr_we_w), .csr_write_en_M(x.csr_we_m), .csr_write_en_E(x.csr_we_e),
    .flush_pipeline_onehot(x.flush_onehot), .valid_E(x.valid_e), .exc_valid_E(x.exc_e),
    .valid_M(x.valid_m), .exc_valid_M(x.exc_m), .wb_redirect(x.wb_redirect), .stallMUL(x.stall_mul),
    .mem_stall_i(x.mem_stall));
  initial begin
    uvm_config_db #(virtual haz_if)::set(null, "*", "vif", ifc);
    run_test("haz_test");
  end
endmodule
