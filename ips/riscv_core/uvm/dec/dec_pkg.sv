interface dec_if(input logic clk);
  logic        valid;
  logic [31:0] instr, imm;
  logic        reg_write, alu_src, mem_write, lui_src, is_lui, illegal, csr_valid, csr_imm, is_mret;
  logic [1:0]  imm_src, result_src, jump, csr_op;
  logic [3:0]  branch, alu_ctl;
  logic [4:0]  lsunit;
endinterface

package dec_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  `include "dec_ref.svh"

  class dec_item extends uvm_sequence_item;
    rand bit [31:0] raw;
    rand bit [3:0]  kind;
    rand bit [2:0]  sel;
    bit             bad;
    bit [31:0]      instr;
    dec_ctrl_t      ctrl;
    bit [31:0]      imm;
    bit [3:0]       alu_ctl;
    bit             illegal;

    `uvm_object_utils(dec_item)
    function new(string name = "dec_item");
      super.new(name);
    endfunction

    function bit [31:0] make_legal();
      bit [31:0] i = raw;
      bit [6:0] f7s[3] = '{7'h00, 7'h20, 7'h01};
      bit [31:0] sys[4] = '{32'h0000_0073, 32'h0010_0073, 32'h3020_0073, 32'h1050_0073};
      case (kind)
        0:  i[6:0] = OP_LUI;
        1:  i[6:0] = OP_AUIPC;
        2:  i[6:0] = OP_JAL;
        3:  begin i[6:0] = OP_JALR; i[14:12] = 3'b000; end
        4, 12: begin i[6:0] = OP_BR; if (i[14:13] == 2'b01) i[14] = 1'b1; end
        5, 13: begin i[6:0] = OP_LD; if (i[14:12] == 3'b011) i[13:12] = 2'b10; else if (i[14:13] == 2'b11) i[13] = 1'b0; end
        6:  begin i[6:0] = OP_ST; i[14:12] = sel % 3; end
        7, 14: begin
          i[6:0] = OP_IMM;
          if (i[14:12] == 3'b001) i[31:25] = 7'h00;
          if (i[14:12] == 3'b101) i[31:25] = sel[0] ? 7'h20 : 7'h00;
        end
        8, 15: begin
          i[6:0] = OP_REG;
          i[31:25] = f7s[sel % 3];
          if (i[31:25] == 7'h20 && !(i[14:12] inside {3'b000, 3'b101})) i[14:12] = i[14] ? 3'b101 : 3'b000;
        end
        9:  begin i[6:0] = OP_FENCE; i[14:13] = 2'b00; end
        10: begin i[6:0] = OP_SYS; if (i[13:12] == 2'b00) i[12] = 1'b1; end
        default: i = sys[sel % 4];
      endcase
      return i;
    endfunction

    function bit [31:0] make_illegal(bit [31:0] i);
      case (sel)
        0: i[1:0] = 2'b00;
        1: i[6:0] = {raw[6:2] ^ 5'b10101, 2'b11};
        2: i[14:12] = (i[6:0] == OP_SYS) ? 3'b100 : (i[6:0] == OP_BR) ? 3'b010 : 3'b111;
        3: i[31:25] = 7'h7F;
        4: i[31:25] = 7'h10;
        5: i = {raw[31:20], 13'h0000, OP_SYS} | 32'h0000_0F80;
        6: i[6:0] = OP_JALR;
        default: i[6:0] = 7'h7F;
      endcase
      if (dec_legal(i)) begin
        i[14:12] = 3'b111;
        if (i[6:0] inside {OP_LUI, OP_AUIPC, OP_JAL, OP_IMM, OP_REG}) i[6:0] = 7'h5B;
      end
      if (dec_legal(i)) i[6:0] = 7'h7F;
      return i;
    endfunction

    function void post_randomize();
      instr = make_legal();
      if (bad) instr = make_illegal(instr);
    endfunction

    function string convert2string();
      return $sformatf("instr=%h illegal=%b imm=%h alu_ctl=%b ctrl=%h", instr, illegal, imm, alu_ctl, ctrl);
    endfunction
  endclass

  class dec_seq extends uvm_sequence #(dec_item);
    `uvm_object_utils(dec_seq)
    int unsigned n = 5000;
    bit bad;
    function new(string name = "dec_seq");
      super.new(name);
    endfunction
    task body();
      repeat (n) begin
        req = dec_item::type_id::create("req");
        req.bad = bad;
        start_item(req);
        if (!req.randomize()) `uvm_fatal("SEQ", "randomize failed")
        finish_item(req);
      end
    endtask
  endclass

  class dec_driver extends uvm_driver #(dec_item);
    `uvm_component_utils(dec_driver)
    virtual dec_if vif;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      vif.valid <= 1'b0;
      forever begin
        seq_item_port.get_next_item(req);
        @(negedge vif.clk);
        vif.instr <= req.instr;
        vif.valid <= 1'b1;
        seq_item_port.item_done();
      end
    endtask
  endclass

  class dec_monitor extends uvm_monitor;
    `uvm_component_utils(dec_monitor)
    virtual dec_if vif;
    uvm_analysis_port #(dec_item) ap;
    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction
    task run_phase(uvm_phase phase);
      forever begin
        @(posedge vif.clk);
        if (vif.valid === 1'b1) begin
          dec_item t = dec_item::type_id::create("t");
          t.instr   = vif.instr;
          t.ctrl    = {vif.reg_write, vif.imm_src, vif.alu_src, vif.mem_write, vif.result_src, vif.branch, vif.jump,
                       vif.lsunit, vif.lui_src, vif.is_lui, vif.csr_valid, vif.csr_imm, vif.csr_op, vif.is_mret};
          t.imm     = vif.imm;
          t.alu_ctl = vif.alu_ctl;
          t.illegal = vif.illegal;
          ap.write(t);
        end
      end
    endtask
  endclass

  class dec_scoreboard extends uvm_subscriber #(dec_item);
    `uvm_component_utils(dec_scoreboard)
    int unsigned n_pass, n_fail, n_ill_pass, n_ill_fail;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    function void write(dec_item t);
      if (!dec_legal(t.instr)) begin
        if (t.illegal === 1'b1) n_ill_pass++;
        else begin
          n_ill_fail++;
          if (n_ill_fail <= 20) `uvm_error("DEC", $sformatf("illegal instruction %h not flagged", t.instr))
        end
        return;
      end
      if (t.ctrl === dec_ref(t.instr) && t.illegal === 1'b0 &&
          (!dec_imm_used(t.instr) || t.imm === dec_imm_ref(t.instr)) &&
          (!dec_aluctl_used(t.instr) || t.alu_ctl === dec_aluctl_ref(t.instr))) n_pass++;
      else begin
        n_fail++;
        if (n_fail <= 20) `uvm_error("DEC", $sformatf("%s expected illegal=0 imm=%h alu_ctl=%b ctrl=%h", t.convert2string(),
                   dec_imm_ref(t.instr), dec_aluctl_ref(t.instr), dec_ref(t.instr)))
      end
    endfunction
    function void report_phase(uvm_phase phase);
      `uvm_info("DEC", $sformatf("legal: checked %0d, pass %0d, fail %0d", n_pass + n_fail, n_pass, n_fail), UVM_NONE)
      if (n_ill_pass + n_ill_fail != 0)
        `uvm_info("DEC", $sformatf("illegal: checked %0d, flagged %0d, missed %0d", n_ill_pass + n_ill_fail, n_ill_pass, n_ill_fail), UVM_NONE)
    endfunction
  endclass

  class dec_coverage extends uvm_subscriber #(dec_item);
    `uvm_component_utils(dec_coverage)
    dec_item t;
    bit lg;

    covergroup cg;
      cp_op: coverpoint t.instr[6:0] {
        bins lui = {OP_LUI}; bins auipc = {OP_AUIPC}; bins jal = {OP_JAL}; bins jalr = {OP_JALR};
        bins branch = {OP_BR}; bins load = {OP_LD}; bins store = {OP_ST}; bins op_imm = {OP_IMM};
        bins op = {OP_REG}; bins fence = {OP_FENCE}; bins system = {OP_SYS}; bins others = default;
      }
      cp_br:   coverpoint t.instr[14:12] iff (t.instr[6:0] == OP_BR && lg) { bins f3[] = {0, 1, 4, 5, 6, 7}; }
      cp_ld:   coverpoint t.instr[14:12] iff (t.instr[6:0] == OP_LD && lg) { bins f3[] = {0, 1, 2, 4, 5}; }
      cp_st:   coverpoint t.instr[14:12] iff (t.instr[6:0] == OP_ST && lg) { bins f3[] = {0, 1, 2}; }
      cp_imm:  coverpoint t.instr[14:12] iff (t.instr[6:0] == OP_IMM && lg) { bins f3[] = {[0 : 7]}; }
      cp_srai: coverpoint t.instr[30] iff (t.instr[6:0] == OP_IMM && t.instr[14:12] == 3'b101 && lg);
      cp_f3:   coverpoint t.instr[14:12] iff (t.instr[6:0] == OP_REG && lg) { bins f3[] = {[0 : 7]}; }
      cp_f7:   coverpoint t.instr[31:25] iff (t.instr[6:0] == OP_REG && lg) { bins base = {7'h00}; bins alt = {7'h20}; bins mext = {7'h01}; }
      x_op:    cross cp_f3, cp_f7 { ignore_bins na = binsof(cp_f7.alt) && !binsof(cp_f3) intersect {0, 5}; }
      cp_sys:  coverpoint t.instr iff (t.instr[6:0] == OP_SYS && t.instr[14:12] == 3'b000 && lg) {
        bins ecall = {32'h0000_0073}; bins ebreak = {32'h0010_0073}; bins mret = {32'h3020_0073}; bins wfi = {32'h1050_0073};
      }
      cp_csr:  coverpoint t.instr[14:12] iff (t.instr[6:0] == OP_SYS && lg) { bins f3[] = {1, 2, 3, 5, 6, 7}; }
      cp_sign: coverpoint t.instr[31] iff (dec_imm_used(t.instr) && lg);
      x_sign:  cross cp_op, cp_sign { ignore_bins na = binsof(cp_op) intersect {OP_REG, OP_FENCE, OP_SYS}; }
      cp_rd0:  coverpoint (t.instr[11:7] == 5'd0) iff (t.ctrl.reg_write && lg);
      cp_ill:  coverpoint t.illegal;
      cp_legal: coverpoint lg;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg = new();
    endfunction
    function void write(dec_item t);
      this.t = t;
      lg = dec_legal(t.instr);
      cg.sample();
    endfunction
    function void report_phase(uvm_phase phase);
      `uvm_info("COV", $sformatf("decoder functional coverage %0.2f%%", cg.get_coverage()), UVM_NONE)
    endfunction
  endclass

  class dec_env extends uvm_env;
    `uvm_component_utils(dec_env)
    uvm_sequencer #(dec_item) sqr;
    dec_driver     drv;
    dec_monitor    mon;
    dec_scoreboard scb;
    dec_coverage   cov;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      virtual dec_if vif;
      if (!uvm_config_db #(virtual dec_if)::get(this, "", "vif", vif)) `uvm_fatal("ENV", "no vif")
      sqr = uvm_sequencer #(dec_item)::type_id::create("sqr", this);
      drv = dec_driver::type_id::create("drv", this);
      mon = dec_monitor::type_id::create("mon", this);
      scb = dec_scoreboard::type_id::create("scb", this);
      cov = dec_coverage::type_id::create("cov", this);
      drv.vif = vif;
      mon.vif = vif;
    endfunction
    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
      mon.ap.connect(scb.analysis_export);
      mon.ap.connect(cov.analysis_export);
    endfunction
  endclass

  class dec_test extends uvm_test;
    `uvm_component_utils(dec_test)
    dec_env env;
    bit bad;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      env = dec_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
      dec_seq seq = dec_seq::type_id::create("seq");
      seq.bad = bad;
      void'($value$plusargs("N=%d", seq.n));
      phase.raise_objection(this);
      seq.start(env.sqr);
      @(posedge env.drv.vif.clk);
      env.drv.vif.valid <= 1'b0;
      @(posedge env.drv.vif.clk);
      phase.drop_objection(this);
    endtask
  endclass

  class dec_illegal_test extends dec_test;
    `uvm_component_utils(dec_illegal_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
      bad = 1'b1;
    endfunction
  endclass
endpackage

module dec_tb;
  import uvm_pkg::*;
  import dec_pkg::*;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  dec_if ifc(clk);
  Control_Unit_Top dut(
    .Op(ifc.instr[6:0]), .funct7(ifc.instr[31:25]), .rs2(ifc.instr[24:20]), .rs1(ifc.instr[19:15]), .rd(ifc.instr[11:7]),
    .funct3(ifc.instr[14:12]), .funct7_30(ifc.instr[30]),
    .RegWrite(ifc.reg_write), .ImmSrc(ifc.imm_src), .ALUSrc(ifc.alu_src), .MemWrite(ifc.mem_write),
    .ResultSrc(ifc.result_src), .Branch(ifc.branch), .ALUControl(ifc.alu_ctl), .Jump(ifc.jump), .lsunit(ifc.lsunit),
    .LUISrcE(ifc.lui_src), .isLUIE(ifc.is_lui), .illegal_instr(ifc.illegal), .csr_valid(ifc.csr_valid),
    .csr_imm_mode(ifc.csr_imm), .csr_op(ifc.csr_op), .is_mret(ifc.is_mret));
  Sign_Extend imm_gen(.In(ifc.instr), .ImmSrc(ifc.imm_src), .Imm_Ext(ifc.imm), .LUI(ifc.is_lui));
  initial begin
    uvm_config_db #(virtual dec_if)::set(null, "*", "vif", ifc);
    run_test("dec_test");
  end
endmodule
