interface alu_if(input logic clk);
  logic        valid;
  logic [31:0] a, b, res;
  logic [3:0]  ctl;
  logic        zero;
  logic [2:0]  flags;
endinterface

package alu_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  `include "alu_ref.svh"

  class alu_item extends uvm_sequence_item;
    rand bit [31:0] a, b;
    rand bit [3:0]  ctl;
    rand bit        same;
    bit [31:0]      res;
    bit             zero;
    bit [2:0]       flags;

    constraint c_same { same dist {1 := 1, 0 := 5}; }
    constraint c_a { a dist {32'h0 := 2, 32'h1 := 1, 32'h7FFF_FFFF := 1, 32'h8000_0000 := 1, 32'hFFFF_FFFF := 2,
                             [32'h2 : 32'h7FFF_FFFE] :/ 4, [32'h8000_0001 : 32'hFFFF_FFFE] :/ 4}; }
    constraint c_b { if (same) b == a;
                     else b dist {32'h0 := 2, 32'h1 := 1, [32'h2 : 32'h1F] :/ 3, 32'h7FFF_FFFF := 1, 32'h8000_0000 := 1,
                                  32'hFFFF_FFFF := 2, [32'h20 : 32'h7FFF_FFFE] :/ 3, [32'h8000_0001 : 32'hFFFF_FFFE] :/ 3}; }
    constraint c_ctl { ctl dist {4'b0000 := 3, 4'b0001 := 3, 4'b0100 := 3, 4'b0101 := 3, 4'b0110 := 3, 4'b0111 := 3,
                                 4'b1000 := 3, 4'b1001 := 3, 4'b1010 := 3, 4'b1100 := 3, 4'b1111 := 3,
                                 4'b0010 := 1, 4'b0011 := 1, 4'b1011 := 1, 4'b1101 := 1, 4'b1110 := 1}; }

    `uvm_object_utils(alu_item)
    function new(string name = "alu_item");
      super.new(name);
    endfunction

    function string convert2string();
      return $sformatf("a=%h b=%h ctl=%b res=%h zero=%b flags=%b", a, b, ctl, res, zero, flags);
    endfunction
  endclass

  class alu_seq extends uvm_sequence #(alu_item);
    `uvm_object_utils(alu_seq)
    int unsigned n = 5000;
    function new(string name = "alu_seq");
      super.new(name);
    endfunction
    task body();
      repeat (n) begin
        req = alu_item::type_id::create("req");
        start_item(req);
        if (!req.randomize()) `uvm_fatal("SEQ", "randomize failed")
        finish_item(req);
      end
    endtask
  endclass

  class alu_driver extends uvm_driver #(alu_item);
    `uvm_component_utils(alu_driver)
    virtual alu_if vif;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      vif.valid <= 1'b0;
      forever begin
        seq_item_port.get_next_item(req);
        @(negedge vif.clk);
        vif.a     <= req.a;
        vif.b     <= req.b;
        vif.ctl   <= req.ctl;
        vif.valid <= 1'b1;
        seq_item_port.item_done();
      end
    endtask
  endclass

  class alu_monitor extends uvm_monitor;
    `uvm_component_utils(alu_monitor)
    virtual alu_if vif;
    uvm_analysis_port #(alu_item) ap;
    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction
    task run_phase(uvm_phase phase);
      forever begin
        @(posedge vif.clk);
        if (vif.valid === 1'b1) begin
          alu_item t = alu_item::type_id::create("t");
          t.a = vif.a; t.b = vif.b; t.ctl = vif.ctl;
          t.res = vif.res; t.zero = vif.zero; t.flags = vif.flags;
          ap.write(t);
        end
      end
    endtask
  endclass

  class alu_scoreboard extends uvm_subscriber #(alu_item);
    `uvm_component_utils(alu_scoreboard)
    int unsigned n_pass, n_fail;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    function void write(alu_item t);
      bit [31:0] r; bit z; bit [2:0] f;
      alu_ref(t.a, t.b, t.ctl, r, z, f);
      if (t.res === r && t.zero === z && t.flags === f) n_pass++;
      else begin
        n_fail++;
        if (n_fail <= 20) `uvm_error("ALU", $sformatf("%s expected res=%h zero=%b flags=%b", t.convert2string(), r, z, f))
      end
    endfunction
    function void report_phase(uvm_phase phase);
      `uvm_info("ALU", $sformatf("checked %0d, pass %0d, fail %0d", n_pass + n_fail, n_pass, n_fail), UVM_NONE)
    endfunction
  endclass

  class alu_coverage extends uvm_subscriber #(alu_item);
    `uvm_component_utils(alu_coverage)
    alu_item t;

    covergroup cg;
      cp_ctl: coverpoint t.ctl {
        bins add = {4'b0000}; bins sub = {4'b0001}; bins and_ = {4'b0100}; bins or_ = {4'b0101};
        bins jalr = {4'b0110}; bins xor_ = {4'b0111}; bins sll = {4'b1000}; bins srl = {4'b1001};
        bins sra = {4'b1010}; bins sltu = {4'b1100}; bins slt = {4'b1111};
        bins unused = {4'b0010, 4'b0011, 4'b1011, 4'b1101, 4'b1110};
      }
      cp_a: coverpoint t.a {
        bins zero = {0}; bins one = {1}; bins max_pos = {32'h7FFF_FFFF}; bins min_neg = {32'h8000_0000};
        bins all_ones = {32'hFFFF_FFFF}; bins pos = {[2 : 32'h7FFF_FFFE]}; bins neg = {[32'h8000_0001 : 32'hFFFF_FFFE]};
      }
      cp_b: coverpoint t.b {
        bins zero = {0}; bins one = {1}; bins max_pos = {32'h7FFF_FFFF}; bins min_neg = {32'h8000_0000};
        bins all_ones = {32'hFFFF_FFFF}; bins pos = {[2 : 32'h7FFF_FFFE]}; bins neg = {[32'h8000_0001 : 32'hFFFF_FFFE]};
      }
      cp_shamt: coverpoint t.b[4:0] { bins zero = {0}; bins max = {31}; bins mid[3] = {[1 : 30]}; }
      cp_zero:  coverpoint t.zero;
      cp_eq:    coverpoint t.flags[2];
      cp_lt:    coverpoint t.flags[1];
      cp_ltu:   coverpoint t.flags[0];
      cp_carry: coverpoint (({1'b0, t.a} + {1'b0, t.b}) >> 32) iff (t.ctl == 4'b0000) { bins no = {0}; bins yes = {1}; }
      cp_ovf:   coverpoint ((t.a[31] == t.b[31]) && (t.res[31] != t.a[31])) iff (t.ctl == 4'b0000) { bins no = {0}; bins yes = {1}; }
      x_ctl_a:  cross cp_ctl, cp_a { ignore_bins u = binsof(cp_ctl.unused); }
      x_ctl_b:  cross cp_ctl, cp_b { ignore_bins u = binsof(cp_ctl.unused); }
      x_ctl_zero: cross cp_ctl, cp_zero { ignore_bins u = binsof(cp_ctl.unused); }
      x_shift:  cross cp_ctl, cp_shamt { ignore_bins o = !binsof(cp_ctl) intersect {4'b1000, 4'b1001, 4'b1010}; }
      x_cmp:    cross cp_lt, cp_ltu;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg = new();
    endfunction
    function void write(alu_item t);
      this.t = t;
      cg.sample();
    endfunction
    function void report_phase(uvm_phase phase);
      `uvm_info("COV", $sformatf("ALU functional coverage %0.2f%%", cg.get_coverage()), UVM_NONE)
    endfunction
  endclass

  class alu_env extends uvm_env;
    `uvm_component_utils(alu_env)
    uvm_sequencer #(alu_item) sqr;
    alu_driver     drv;
    alu_monitor    mon;
    alu_scoreboard scb;
    alu_coverage   cov;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      virtual alu_if vif;
      if (!uvm_config_db #(virtual alu_if)::get(this, "", "vif", vif)) `uvm_fatal("ENV", "no vif")
      sqr = uvm_sequencer #(alu_item)::type_id::create("sqr", this);
      drv = alu_driver::type_id::create("drv", this);
      mon = alu_monitor::type_id::create("mon", this);
      scb = alu_scoreboard::type_id::create("scb", this);
      cov = alu_coverage::type_id::create("cov", this);
      drv.vif = vif;
      mon.vif = vif;
    endfunction
    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
      mon.ap.connect(scb.analysis_export);
      mon.ap.connect(cov.analysis_export);
    endfunction
  endclass

  class alu_test extends uvm_test;
    `uvm_component_utils(alu_test)
    alu_env env;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      env = alu_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
      alu_seq seq = alu_seq::type_id::create("seq");
      void'($value$plusargs("N=%d", seq.n));
      phase.raise_objection(this);
      seq.start(env.sqr);
      repeat (2) @(posedge env.drv.vif.clk);
      phase.drop_objection(this);
    endtask
  endclass
endpackage

module alu_tb;
  import uvm_pkg::*;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  alu_if ifc(clk);
  ALU dut(.A(ifc.a), .B(ifc.b), .ALUControl(ifc.ctl), .Result(ifc.res), .Zero(ifc.zero), .flags(ifc.flags));
  initial begin
    uvm_config_db #(virtual alu_if)::set(null, "*", "vif", ifc);
    run_test("alu_test");
  end
endmodule
