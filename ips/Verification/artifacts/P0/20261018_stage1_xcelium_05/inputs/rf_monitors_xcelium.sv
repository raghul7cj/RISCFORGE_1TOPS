// =============================================================================
// Module Name : rf_monitors.sv
// Description : RISCFORGE SoC passive monitor classes.
//
//               One class per observation point, all deriving from
//               rf_monitor_base. Every monitor:
//                 * samples exactly one clocking block at @(posedge clk) with
//                   default input #1step, so all monitors see the SAME
//                   preponed values at the SAME edge (no inter-monitor skew)
//                 * stamps `timestamp` (absolute) and `rel_cycle` (post-reset)
//                 * pushes into a cyclic ring buffer for post-mortem
//                 * honours `freeze` from failure_reporter.freeze_monitors, so
//                   the window around the first fatal survives
//                 * publishes to a shared rf_trace_db for scoreboard/coverage
//
//               Implements INFRA_TRACKING.md S1.1 (LSU) S1.2 (AXI, 5 separate
//               events) S1.3 (APB, one line per completed transfer with wait
//               states) and S1.11 (ring buffers + cycle stamping).
//
// Assumes  : `import tb_pkg::*;` and the interfaces from ../tb/rf_monitor_if.sv
// Style    : no UVM. Plain SV classes + untyped-safe dynamic dispatch, which is
//            what the rest of the RISCFORGE tree does (XSim 2022.2 primary).
// =============================================================================

`ifndef RF_MONITORS_SV
`define RF_MONITORS_SV

`timescale 1ns/1ps

// Compilation-unit scope import: XSim needs the package symbols visible at
// file scope, not only inside a module. tb_pkg must be compiled first.
import tb_pkg::*;

// =============================================================================
// 1. rf_monitor_base
// =============================================================================
class rf_monitor_base;

  string          name;
  int             layer;
  bit             enable;
  bit             freeze;
  rf_trace_db     db;

  longint unsigned n_events;
  longint unsigned n_suppressed;   // events dropped because freeze was set
  longint unsigned first_cycle;
  longint unsigned last_cycle;

  longint unsigned cur_cycle     = 0;
  longint unsigned cur_rel_cycle = 0;

  function new(string name = "mon", int layer = LAYER_PROTOCOL);
    this.name          = name;
    this.layer         = layer;
    this.enable        = 1;
    this.freeze        = 0;
    this.n_events      = 0;
    this.n_suppressed  = 0;
    this.first_cycle   = 0;
    this.last_cycle    = 0;
  endfunction

  virtual function void bind_db(rf_trace_db db_h);
    this.db = db_h;
  endfunction

  // Common bookkeeping for every emitted transaction. XSim 2022.2 rejects
  // `ref` actuals that are packed-struct members, so this returns the
  // timestamp instead of writing through a reference, and the caller assigns
  // all three fields explicitly.
  virtual function longint unsigned tick(int unsigned seq);
    if (first_cycle == 0) first_cycle = cur_cycle;
    last_cycle = cur_cycle;
    n_events++;
    return cur_cycle;
  endfunction

  virtual function void account_drop();
    n_suppressed++;
  endfunction

  // Cycle values come from the shared timebase, sampled into every monitor by
  // its clocking block at construction of the monitor.


  virtual task run(); endtask

  function string banner();
    return $sformatf("== %-10s layer=%d(%s) events=%0d suppressed=%0d span=[%0d..%0d]",
                     name, layer, layer_name(layer), n_events, n_suppressed,
                     first_cycle, last_cycle);
  endfunction
endclass

// =============================================================================
// 2. rf_fetch_monitor   (S1 core: PC / instr / valid / stall)
// =============================================================================
class rf_fetch_monitor extends rf_monitor_base;

  virtual rf_fetch_if vif;

  rf_fetch_ring          ring;
  rf_retire_ring         instr_shadow;   // PC -> instruction word, for retire
  fetch_txn_t            q_fetch[$];

  int  unsigned pc_to_instr[bit[32:0]];   // associative: retired PC -> instr

  longint unsigned n_stall_cycles;
  longint unsigned n_branch;

  function new(rf_if_ports ports, rf_trace_db db);
    super.new("FETCH", LAYER_PATH);
    this.vif  = ports.fetch;
    this.ring = new();
    bind_db(db);
  endfunction

  virtual task run();
    fetch_txn_t t;
    forever begin
      @(vif.mon_cb);

      cur_cycle     = vif.mon_cb.tb_cycle;
      cur_rel_cycle = vif.mon_cb.tb_rel_cycle;
      this.freeze   = vif.mon_cb.freeze;

      if (!enable) continue;

      if (vif.mon_cb.stall_f) n_stall_cycles++;

      // A fetch is accepted when the imem request is issued and not stalled.
      if (vif.mon_cb.fetch_en && !vif.mon_cb.stall_f) begin
        t              = '0;
        t.pc           = vif.mon_cb.pc;
        t.instr        = vif.mon_cb.instr;
        t.valid        = 1'b1;
        t.stall        = 1'b0;
        t.pc_next      = vif.mon_cb.pc_next;
        t.branch_taken = (vif.mon_cb.pc_next != vif.mon_cb.pc_plus4) &&
                         (vif.mon_cb.pc_next != vif.mon_cb.pc);
        t.exc_valid    = vif.mon_cb.exc_valid;
        t.exc_cause    = vif.mon_cb.exc_cause;
        t.exc_tval     = vif.mon_cb.exc_tval;
        t.region       = decode_region(t.pc);

        t.timestamp = tick(q_fetch.size());

        t.rel_cycle = cur_rel_cycle;

        t.seq       = q_fetch.size();
        if (t.branch_taken) n_branch++;

        // Publish BEFORE the freeze gate so the live stream is complete;
        // the ring is what freeze protects.
        q_fetch.push_back(t);
        pc_to_instr[t.pc] = t.instr;
        if (db != null) db.record_fetch(t, freeze);

        ring.push(t, freeze);
      end
    end
  endtask

  function string dump_recent(int n = 16);
    return ring.dump(n, $sformatf("stall_cycles=%0d branches=%0d", n_stall_cycles, n_branch));
  endfunction

  function logic [31:0] lookup_instr(logic [31:0] pc);
    if (pc_to_instr.exists(pc)) return pc_to_instr[pc];
    return 32'h0000_0000;
  endfunction
endclass

// =============================================================================
// 3. rf_retire_monitor  (S1 core: PC / instr / rd / data / trap / irq_ack)
// =============================================================================
// RISCFORGE has no `trap` or `irq_ack` net. The architectural observables are:
//   retire            = valid_W && wb_commit          (commit controller)
//   trap              = trap_commit_valid
//   irq_ack           = trap_commit_is_interrupt      <-- the requested ack
//   mret              = mret_commit / is_mret_W
class rf_retire_monitor extends rf_monitor_base;

  virtual rf_retire_if vif;

  rf_retire_ring  ring;
  retire_txn_t    q_retire[$];

  // Optional link to the fetch monitor. RISCFORGE does NOT carry a retired
  // instruction word on a net, so the PC->instr shadow is the only source;
  // this handle is how the retire trace gets its `instr` field populated.
  rf_fetch_monitor fetch_mon;

  longint unsigned n_commit;
  longint unsigned n_regwrite;
  longint unsigned n_trap;
  longint unsigned n_irq;
  longint unsigned n_mret;
  longint unsigned n_csr;

  function new(rf_if_ports ports, rf_trace_db db);
    super.new("RETIRE", LAYER_PATH);
    this.vif      = ports.retire;
    this.ring     = new();
    this.fetch_mon= null;
    bind_db(db);
  endfunction

  virtual task run();
    retire_txn_t t;
    forever begin
      @(vif.mon_cb);

      cur_cycle     = vif.mon_cb.tb_cycle;
      cur_rel_cycle = vif.mon_cb.tb_rel_cycle;
      this.freeze   = vif.mon_cb.freeze;

      if (!enable) continue;

      // Architectural commit. wb_commit is the single commit point; when it is
      // unavailable, valid_W && (reg_we || trap || mret) is the safe fallback.
      if (vif.mon_cb.valid_w && (vif.mon_cb.wb_commit ||
                                 vif.mon_cb.reg_we   ||
                                 vif.mon_cb.trap     ||
                                 vif.mon_cb.is_mret)) begin
        t             = '0;
        t.pc          = vif.mon_cb.pc_w;
        t.instr       = vif.mon_cb.instr;
        if (t.instr == 32'h0 && fetch_mon != null)
          t.instr = fetch_mon.lookup_instr(vif.mon_cb.pc_w);
        t.rd_addr     = vif.mon_cb.rd_addr;
        t.rd_wdata    = vif.mon_cb.rd_wdata;
        t.reg_we      = vif.mon_cb.reg_we;
        t.trap        = vif.mon_cb.trap;
        t.irq_ack     = vif.mon_cb.trap_is_interrupt;
        t.is_mret     = vif.mon_cb.is_mret;
        t.csr_we      = vif.mon_cb.csr_we;
        t.csr_addr    = vif.mon_cb.csr_addr;
        t.csr_wdata   = vif.mon_cb.csr_wdata;
        t.exc_cause   = vif.mon_cb.exc_cause;
        t.exc_tval    = vif.mon_cb.exc_tval;
        t.exc_pc      = vif.mon_cb.exc_pc;
        t.cause       = vif.mon_cb.trap_cause;
        t.irq_src     = irq_src_of_mcause31({1'b1, vif.mon_cb.trap_cause});
        t.irq_class   = (t.irq_src == RF_IRQ_NONE) ? 2'd0 : irq_class(t.irq_src);

        t.timestamp = tick(q_retire.size());

        t.rel_cycle = cur_rel_cycle;

        t.seq       = q_retire.size();

        if (vif.mon_cb.reg_we)  n_regwrite++;
        if (vif.mon_cb.trap)    n_trap++;
        if (t.irq_ack)          n_irq++;
        if (vif.mon_cb.is_mret) n_mret++;
        if (vif.mon_cb.csr_we)  n_csr++;
        n_commit++;

        q_retire.push_back(t);
        if (db != null) db.record_retire(t, freeze);
        ring.push(t, freeze);
      end
    end
  endtask

  function string dump_recent(int n = 16);
    return ring.dump(n, $sformatf("commit=%0d regwe=%0d trap=%0d irq=%0d mret=%0d csr=%0d",
                                  n_commit, n_regwrite, n_trap, n_irq, n_mret, n_csr));
  endfunction
endclass

// =============================================================================
// 4. rf_lsu_monitor  (S1 core: addr / wdata / rdata / wstrb / is_mmio)
// =============================================================================
// Mirrors lsu_monitor.sv's transaction contract:
//   {timestamp, addr, wdata, rdata, be, we, is_mmio}
// plus pc / lsunit / wait-state counting and region+slot decode.
class rf_lsu_monitor extends rf_monitor_base;

  virtual rf_lsu_if vif;

  rf_lsu_ring ring;
  lsu_txn_t   q_lsu[$];

  longint unsigned n_req;
  longint unsigned n_load;
  longint unsigned n_store;
  longint unsigned n_mmio;
  longint unsigned n_err;

  // in-flight request tracking (req -> completion)
  logic        f_req, f_we, f_err;
  logic [31:0] f_addr, f_wdata, f_rdata;
  logic [3:0]  f_be;
  logic [31:0] f_pc;
  logic [4:0]  f_lsunit;
  int  unsigned f_req_cycle;

  function new(rf_if_ports ports, rf_trace_db db);
    super.new("LSU", LAYER_PATH);
    this.vif  = ports.lsu;
    this.ring = new();
    bind_db(db);
    clear_pending();
  endfunction

  function void clear_pending();
    f_req       = 0;
    f_we        = 0;
    f_err       = 0;
    f_addr      = '0;
    f_wdata     = '0;
    f_rdata     = '0;
    f_be        = '0;
    f_pc        = '0;
    f_lsunit    = '0;
    f_req_cycle = 0;
  endfunction

  virtual task run();
    lsu_txn_t t;
    forever begin
      @(vif.mon_cb);

      cur_cycle     = vif.mon_cb.tb_cycle;
      cur_rel_cycle = vif.mon_cb.tb_rel_cycle;
      this.freeze   = vif.mon_cb.freeze;

      if (!enable) continue;

      // ---- launch ----
      if (vif.mon_cb.valid_m && vif.mon_cb.req && !f_req) begin
        f_req       = 1'b1;
        f_we        = vif.mon_cb.we;
        f_err       = vif.mon_cb.err;
        f_addr      = vif.mon_cb.addr;
        f_wdata     = vif.mon_cb.wdata;
        f_rdata     = '0;
        f_be        = vif.mon_cb.be;
        f_pc        = vif.mon_cb.pc_m;
        f_lsunit    = vif.mon_cb.lsunit;
        f_req_cycle = cur_cycle;
        n_req++;
        if (f_err) n_err++;
      end

      // ---- completion: req deasserted, or error, or a stall cycle with data ----
      if (f_req && (!vif.mon_cb.req || vif.mon_cb.err || vif.mon_cb.stall)) begin
        if (vif.mon_cb.req) begin
          f_rdata = vif.mon_cb.rdata;
          f_err   = vif.mon_cb.err;
        end
        t = '0;
        t.pc           = f_pc;
        t.lsunit       = f_lsunit;
        t.op           = rf_lsu_op_e'(f_lsunit[2:0]);
        t.is_load      = ~f_we;
        t.is_store     = f_we;
        t.addr         = f_addr;
        t.wdata        = f_wdata;
        t.rdata        = f_rdata;
        t.be           = f_be;
        t.we           = f_we;
        t.err          = f_err;
        t.is_mmio      = is_mmio_addr(f_addr);
        t.wait_cycles  = int'(cur_cycle - f_req_cycle);
        t.region       = decode_region(f_addr);
        t.apb_slot     = get_expected_apb_slot(f_addr);

        t.timestamp = tick(q_lsu.size());

        t.rel_cycle = cur_rel_cycle;

        t.seq       = q_lsu.size();

        if (t.is_store) n_store++; else n_load++;
        if (t.is_mmio)  n_mmio++;

        q_lsu.push_back(t);
        if (db != null) db.record_lsu(t, freeze);
        ring.push(t, freeze);

        clear_pending();
      end
    end
  endtask

  function string dump_recent(int n = 16);
    return ring.dump(n, $sformatf("req=%0d load=%0d store=%0d mmio=%0d err=%0d",
                                  n_req, n_load, n_store, n_mmio, n_err));
  endfunction
endclass

// =============================================================================
// 5. rf_axil_monitor  (S1.2 - AW, W, B, AR, R as FIVE independent events)
// =============================================================================
// A single AXI-Lite class emits one axi_evt_t per handshake AND one correlated
// axi_txn_t per completed transfer. Correlation uses per-channel latches:
//   write: AW latches addr, W latches data/strb, B closes and produces WR txn
//   read : AR latches addr,  R closes and produces RD txn
// A stall cycle (VALID&&!READY) updates the *_wait counters.
class rf_axil_monitor extends rf_monitor_base;

  virtual rf_axil_if vif;

  rf_axil_ring  ring;
  axi_evt_t     q_evt[$];
  axi_txn_t     q_txn[$];

  longint unsigned n_aw, n_w, n_b, n_ar, n_r;
  longint unsigned n_stall_aw, n_stall_w, n_stall_b, n_stall_ar, n_stall_r;

  // correlation state
  int  unsigned aw_wait_cnt, w_wait_cnt, b_wait_cnt, ar_wait_cnt, r_wait_cnt;
  logic        aw_hs, w_hs, b_hs, ar_hs, r_hs;
  logic [31:0] aw_addr_q, ar_addr_q;
  logic [31:0] w_data_q,  r_data_q;
  logic [3:0]  w_strb_q;
  logic [2:0]  aw_prot_q, ar_prot_q;
  logic [1:0]  b_resp_q,  r_resp_q;
  longint unsigned aw_cycle_q, w_cycle_q, ar_cycle_q, granted_cycle_q;

  function new(rf_if_ports ports, rf_trace_db db);
    super.new("AXILITE", LAYER_PROTOCOL);
    this.vif  = ports.axil;
    this.ring = new();
    bind_db(db);
    clear_correl();
  endfunction

  function void clear_correl();
    aw_wait_cnt = 0; w_wait_cnt = 0; b_wait_cnt = 0; ar_wait_cnt = 0; r_wait_cnt = 0;
    aw_hs = 0; w_hs = 0; b_hs = 0; ar_hs = 0; r_hs = 0;
    aw_addr_q = '0; ar_addr_q = '0; w_data_q = '0; r_data_q = '0; w_strb_q = '0;
    aw_prot_q = '0; ar_prot_q = '0; b_resp_q = '0; r_resp_q = '0;
    aw_cycle_q = 0; w_cycle_q = 0; ar_cycle_q = 0; granted_cycle_q = 0;
  endfunction

  task automatic emit_evt(rf_axi_chan_e ch, logic v, logic r, int unsigned wait_cnt);
    axi_evt_t e;
    e = '0;
    e.timestamp     = tick(q_evt.size());
    e.seq           = q_evt.size();
    e.chan          = ch;
    e.valid         = v;
    e.ready         = r;
    e.wait_cycles   = int'(wait_cnt);
    case (ch)
      RF_AXI_CH_AW: begin e.addr = aw_addr_q; e.prot = aw_prot_q; end
      RF_AXI_CH_W:  begin e.data = w_data_q;  e.strb = w_strb_q;   end
      RF_AXI_CH_B:  begin e.resp = b_resp_q;                        end
      RF_AXI_CH_AR: begin e.addr = ar_addr_q; e.prot = ar_prot_q; end
      RF_AXI_CH_R:  begin e.data = r_data_q;  e.resp = r_resp_q;   end
      default: ;
    endcase
    q_evt.push_back(e);
    if (db != null) db.record_axi_evt(e, freeze);
  endtask

  virtual task run();
    axi_txn_t t;
    forever begin
      @(vif.mon_cb);

      cur_cycle     = vif.mon_cb.tb_cycle;
      cur_rel_cycle = vif.mon_cb.tb_rel_cycle;
      this.freeze   = vif.mon_cb.freeze;

      if (!enable) continue;

      // ---- AW ----
      aw_hs = vif.mon_cb.awvalid && vif.mon_cb.awready;
      if (aw_hs) begin
        aw_addr_q   = vif.mon_cb.awaddr;
        aw_prot_q   = vif.mon_cb.awprot;
        aw_cycle_q  = cur_cycle;
        aw_wait_cnt = 0;
        n_aw++;
        emit_evt(RF_AXI_CH_AW, 1'b1, 1'b1, aw_wait_cnt);
      end else if (vif.mon_cb.awvalid) begin
        aw_wait_cnt++;
        n_stall_aw++;
        emit_evt(RF_AXI_CH_AW, 1'b1, 1'b0, aw_wait_cnt);
      end

      // ---- W ----
      w_hs = vif.mon_cb.wvalid && vif.mon_cb.wready;
      if (w_hs) begin
        w_data_q   = vif.mon_cb.wdata;
        w_strb_q   = vif.mon_cb.wstrb;
        w_cycle_q  = cur_cycle;
        w_wait_cnt = 0;
        n_w++;
        emit_evt(RF_AXI_CH_W, 1'b1, 1'b1, w_wait_cnt);
      end else if (vif.mon_cb.wvalid) begin
        w_wait_cnt++;
        n_stall_w++;
        emit_evt(RF_AXI_CH_W, 1'b1, 1'b0, w_wait_cnt);
      end

      // ---- B  (completes a WRITE) ----
      b_hs = vif.mon_cb.bvalid && vif.mon_cb.bready;
      if (b_hs) begin
        b_resp_q   = vif.mon_cb.bresp;
        b_wait_cnt = 0;
        n_b++;
        emit_evt(RF_AXI_CH_B, 1'b1, 1'b1, b_wait_cnt);

        t            = '0;
        t.addr       = aw_addr_q;
        t.data       = w_data_q;
        t.strb       = w_strb_q;
        t.resp       = b_resp_q;
        t.is_write   = 1'b1;
        t.prot       = aw_prot_q;
        t.aw_hs      = aw_hs;
        t.w_hs       = w_hs;
        t.b_hs       = 1'b1;
        t.aw_wait    = int'(cur_cycle - aw_cycle_q);
        t.w_wait     = int'(cur_cycle - w_cycle_q);
        t.b_wait     = b_wait_cnt;
        t.aw_to_w    = int'(w_cycle_q - aw_cycle_q);
        t.aw_to_b    = int'(cur_cycle - aw_cycle_q);
        t.is_mmio    = is_mmio_addr(aw_addr_q);
        t.apb_slot   = get_expected_apb_slot(aw_addr_q);
        t.decoded    = (t.apb_slot != int'(RF_APB_NONE));
        t.timestamp = tick(q_txn.size());
        t.rel_cycle = cur_rel_cycle;
        t.seq       = q_txn.size();
        q_txn.push_back(t);
        if (db != null) db.record_axi(t, freeze);
        ring.push(t, freeze);
        granted_cycle_q = cur_cycle;
      end else if (vif.mon_cb.bvalid) begin
        b_wait_cnt++;
        n_stall_b++;
        emit_evt(RF_AXI_CH_B, 1'b1, 1'b0, b_wait_cnt);
      end

      // ---- AR ----
      ar_hs = vif.mon_cb.arvalid && vif.mon_cb.arready;
      if (ar_hs) begin
        ar_addr_q   = vif.mon_cb.araddr;
        ar_prot_q   = vif.mon_cb.arprot;
        ar_cycle_q  = cur_cycle;
        ar_wait_cnt = 0;
        n_ar++;
        emit_evt(RF_AXI_CH_AR, 1'b1, 1'b1, ar_wait_cnt);
      end else if (vif.mon_cb.arvalid) begin
        ar_wait_cnt++;
        n_stall_ar++;
        emit_evt(RF_AXI_CH_AR, 1'b1, 1'b0, ar_wait_cnt);
      end

      // ---- R  (completes a READ) ----
      r_hs = vif.mon_cb.rvalid && vif.mon_cb.rready;
      if (r_hs) begin
        r_data_q   = vif.mon_cb.rdata;
        r_resp_q   = vif.mon_cb.rresp;
        r_wait_cnt = 0;
        n_r++;
        emit_evt(RF_AXI_CH_R, 1'b1, 1'b1, r_wait_cnt);

        t            = '0;
        t.addr       = ar_addr_q;
        t.data       = r_data_q;
        t.strb       = 4'hF;
        t.resp       = r_resp_q;
        t.is_write   = 1'b0;
        t.prot       = ar_prot_q;
        t.ar_to_r    = int'(cur_cycle - ar_cycle_q);
        t.is_mmio    = is_mmio_addr(ar_addr_q);
        t.apb_slot   = get_expected_apb_slot(ar_addr_q);
        t.decoded    = (t.apb_slot != int'(RF_APB_NONE));
        t.timestamp = tick(q_txn.size());
        t.rel_cycle = cur_rel_cycle;
        t.seq       = q_txn.size();
        q_txn.push_back(t);
        if (db != null) db.record_axi(t, freeze);
        ring.push(t, freeze);
        granted_cycle_q = cur_cycle;
      end else if (vif.mon_cb.rvalid) begin
        r_wait_cnt++;
        n_stall_r++;
        emit_evt(RF_AXI_CH_R, 1'b1, 1'b0, r_wait_cnt);
      end
    end
  endtask

  function string dump_recent(int n = 16);
    return ring.dump(n, $sformatf("AW=%0d W=%0d B=%0d AR=%0d R=%0d stalls(AW/W/B/AR/R)=%0d/%0d/%0d/%0d/%0d",
                                  n_aw, n_w, n_b, n_ar, n_r,
                                  n_stall_aw, n_stall_w, n_stall_b, n_stall_ar, n_stall_r));
  endfunction
endclass

// =============================================================================
// 6. rf_apb_monitor  (S1.3 - one line per COMPLETED transfer + wait states)
// =============================================================================
// APB phases per slot:
//   setup  : PSEL && !PENABLE                -> latches paddr/pwrite/pwdata
//   access : PSEL && PENABLE  (waits)        -> wait-state counter increments
//   done   : PSEL && PENABLE && PREADY       -> emits one apb_txn_t
// Each of the 6 slots gets its OWN state, so independent slot activity is not
// conflated. This mirrors apb_monitor.sv's `psel[i] && penable && pready[i]`.
class rf_apb_monitor extends rf_monitor_base;

  virtual rf_apb_if vif;

  rf_apb_ring ring;
  apb_txn_t   q_apb[$];

  longint unsigned n_xfer[NUM_APB_SLOTS];
  longint unsigned n_wr[NUM_APB_SLOTS];
  longint unsigned n_rd[NUM_APB_SLOTS];
  longint unsigned n_err[NUM_APB_SLOTS];
  longint unsigned max_ws[NUM_APB_SLOTS];

  // per-slot in-flight state
  logic [31:0] f_paddr  [NUM_APB_SLOTS];
  logic [31:0] f_pwdata [NUM_APB_SLOTS];
  logic [3:0]  f_pstrb  [NUM_APB_SLOTS];
  logic        f_pwrite [NUM_APB_SLOTS];
  logic        f_active [NUM_APB_SLOTS];
  logic        f_blocked[NUM_APB_SLOTS];
  longint unsigned f_setup_cycle [NUM_APB_SLOTS];
  longint unsigned f_access_cycle[NUM_APB_SLOTS];
  int  unsigned  f_ws           [NUM_APB_SLOTS];

  function new(rf_if_ports ports, rf_trace_db db);
    super.new("APB", LAYER_PROTOCOL);
    this.vif  = ports.apb;
    this.ring = new();
    bind_db(db);
    clear_slots();
  endfunction

  function void clear_slots();
    for (int i = 0; i < NUM_APB_SLOTS; i++) begin
      n_xfer[i] = 0; n_wr[i] = 0; n_rd[i] = 0; n_err[i] = 0; max_ws[i] = 0;
      f_active[i] = 0; f_blocked[i] = 0; f_setup_cycle[i] = 0; f_access_cycle[i] = 0; f_ws[i] = 0;
      f_paddr[i] = '0; f_pwdata[i] = '0; f_pstrb[i] = '0; f_pwrite[i] = 0;
    end
  endfunction

  virtual task run();
    apb_txn_t t;
    forever begin
      @(vif.mon_cb);

      cur_cycle     = vif.mon_cb.tb_cycle;
      cur_rel_cycle = vif.mon_cb.tb_rel_cycle;
      this.freeze   = vif.mon_cb.freeze;

      if (!enable) continue;

      // Flattened per-slot view of psel/pready/pslverr. PRDATA and PSTRB are read
      // asynchronously off the interface rather than through mon_cb because XSim cannot
      // sample them correctly through a clocking block, and APB keeps them stable
      // across the access phase anyway.
      for (int i = 0; i < NUM_APB_SLOTS; i++) begin
        bit sel_i, rdy_i, err_i;
        sel_i = vif.mon_cb.psel[i];
        rdy_i = vif.mon_cb.pready[i];
        err_i = vif.mon_cb.pslverr[i];

        // A well-behaved bridge gives a full setup phase (PSEL && !PENABLE).
        // Some fabrics present a combined setup+access cycle, so accept that
        // too. `f_blocked[i]` stops us re-arming and fabricating extra
        // transfers while PSEL is still high after a completion (APB drops
        // PENABLE, but a lingering PSEL must not invent transactions).
        if (!sel_i) f_blocked[i] = 1'b0;
        if (sel_i && !f_active[i] && !f_blocked[i]) begin
          f_active[i]      = 1'b1;
          f_paddr[i]       = vif.mon_cb.paddr;
          f_pwdata[i]      = vif.mon_cb.pwdata;
          f_pstrb[i]       = vif.pstrb;
          f_pwrite[i]      = vif.mon_cb.pwrite;
          f_setup_cycle[i] = cur_cycle;
          f_access_cycle[i]= cur_cycle;
          f_ws[i]          = 0;
        end

        // ---- access phase ----
        if (f_active[i] && sel_i && vif.mon_cb.penable && !rdy_i)
          f_ws[i]++;

        // ---- complete: PSEL && PENABLE && PREADY ----
        if (f_active[i] && sel_i && vif.mon_cb.penable && rdy_i) begin
          t                 = '0;
          t.slot            = i;
          t.paddr           = f_paddr[i];
          t.pwdata          = f_pwdata[i];
          t.prdata          = vif.prdata_of(i);
          t.pstrb           = f_pstrb[i];
          t.pwrite          = f_pwrite[i];
          t.pready          = 1'b1;
          t.pslverr         = err_i;
          t.wait_states     = f_ws[i];
          t.setup_cycle     = f_setup_cycle[i];
          t.access_cycle    = f_access_cycle[i];
          t.addr_match      = {f_paddr[i][31:12], 12'h0};

          t.timestamp = tick(q_apb.size());

          t.rel_cycle = cur_rel_cycle;

          t.seq       = q_apb.size();

          n_xfer[i]++;
          if (t.pwrite) n_wr[i]++; else n_rd[i]++;
          if (t.pslverr) n_err[i]++;
          if (t.wait_states > max_ws[i]) max_ws[i] = t.wait_states;

          q_apb.push_back(t);
          if (db != null) db.record_apb(t, freeze);
          ring.push(t, freeze);

          f_active[i] = 0;
          f_ws[i]     = 0;
          f_blocked[i] = 1'b1;      // require PSEL to drop before re-arming
        end

        // ---- abort: PSEL dropped mid-transfer ----
        if (f_active[i] && !sel_i && !rdy_i) begin
          f_active[i] = 0;
          f_ws[i]     = 0;
        end
      end
    end
  endtask

  function string dump_recent(int n = 16);
    string s;
    s = "";
    for (int i = 0; i < NUM_APB_SLOTS; i++)
      s = {s, $sformatf("  slot %d %-6s xfer=%0d wr=%0d rd=%0d slverr=%0d max_ws=%0d\n",
                        i, apb_slot_name(i), n_xfer[i], n_wr[i], n_rd[i],
                        n_err[i], max_ws[i])};
    return {s, ring.dump(n)};
  endfunction
endclass

// =============================================================================
// 7. rf_irq_monitor  (irq_src / irq_pending / irq_grant / irq_ack)
// =============================================================================
// RISCFORGE has NO irq_ack net. The acknowledgement point is the commit of an
// interrupt trap: trap_commit_is_interrupt, sampled on the same clocking block.
// The monitor emits an irq_txn_t on:
//   * assertion  : any raw source rises (or gateway_pend rises)
//   * grant      : irq_pending
//   * ack        : trap_is_interrupt
// and computes assert->grant->ack latency.
class rf_irq_monitor extends rf_monitor_base;

  virtual rf_irq_if vif;

  rf_irq_ring ring;
  irq_txn_t   q_irq[$];

  longint unsigned n_assert, n_grant, n_ack, n_mret;
  longint unsigned grant_cycle_q, ack_cycle_q, assert_cycle_q;
  rf_irq_src_e   src_q;

  // raw edge history for the per-source post-mortem
  logic prev_gpio, prev_i2c, prev_spi0, prev_spi1, prev_uart;
  logic [3:0] prev_t0, prev_t1;
  logic [5:0] prev_pend;
  logic prev_pending;

  function new(rf_if_ports ports, rf_trace_db db);
    super.new("IRQ", LAYER_IRQ);
    this.vif  = ports.irq;
    this.ring = new();
    bind_db(db);
    src_q = RF_IRQ_NONE;
    prev_pending = 1'b0;
  endfunction

  task automatic emit(rf_irq_src_e s, bit asserted, bit granted, bit acked);
    irq_txn_t t;
    int unsigned mb;
    logic      mbit;
    mb   = (s == RF_IRQ_NONE) ? 0 : irq_mip_bit(s);
    mbit = 1'b0;
    if (s != RF_IRQ_NONE) mbit = vif.mon_cb.mie[mb % 32];

    t = '0;
    t.timestamp     = tick(q_irq.size());
    t.rel_cycle     = cur_rel_cycle;
    t.seq           = q_irq.size();
    t.irq_id        = (s == RF_IRQ_NONE) ? 5'd0 : mb[4:0];
    t.src           = s;
    t.asserted      = asserted;
    t.granted       = granted;
    t.acked         = acked;
    t.is_interrupt  = acked;
    t.cause         = vif.mon_cb.trap_cause;
    t.mip           = vif.mon_cb.mip;
    t.mie           = vif.mon_cb.mie;
    t.mie_bit       = mbit;
    t.mstatus_mie   = vif.mon_cb.mstatus_mie;
    t.irq_class     = (s == RF_IRQ_NONE) ? 2'd0 : irq_class(s);
    t.nest_depth    = vif.mon_cb.nest_depth;
    t.gateway_pend_q= vif.mon_cb.gateway_pend_q;
    t.rr_ptrs       = {vif.mon_cb.rr_ptr_c1, vif.mon_cb.rr_ptr_c0};
    t.latency_cycles= (acked && (grant_cycle_q != 0))
                      ? 32'(cur_cycle - grant_cycle_q) : 32'd0;

    q_irq.push_back(t);
    if (db != null) db.record_irq(t, freeze);
    ring.push(t, freeze);
  endtask

  virtual task run();
    forever begin
      @(vif.mon_cb);

      cur_cycle     = vif.mon_cb.tb_cycle;
      cur_rel_cycle = vif.mon_cb.tb_rel_cycle;
      this.freeze   = vif.mon_cb.freeze;

      if (!enable) continue;

      // ---- assertions (rising edges on the raw sources / gateway) ----
      if (vif.mon_cb.gpio_irq && !prev_gpio) begin
        emit(RF_IRQ_GPIO_GLOBAL, 1'b1, 1'b0, 1'b0);
        assert_cycle_q = cur_cycle; n_assert++;
      end
      if (vif.mon_cb.i2c_irq && !prev_i2c) begin
        emit(RF_IRQ_I2C, 1'b1, 1'b0, 1'b0);
        assert_cycle_q = cur_cycle; n_assert++;
      end
      if (vif.mon_cb.spi_irq[0] && !prev_spi0) begin
        emit(RF_IRQ_SPI_EVT0, 1'b1, 1'b0, 1'b0);
        assert_cycle_q = cur_cycle; n_assert++;
      end
      if (vif.mon_cb.spi_irq[1] && !prev_spi1) begin
        emit(RF_IRQ_SPI_EVT1, 1'b1, 1'b0, 1'b0);
        assert_cycle_q = cur_cycle; n_assert++;
      end
      if (vif.mon_cb.uart_irq && !prev_uart) begin
        emit(RF_IRQ_UART, 1'b1, 1'b0, 1'b0);
        assert_cycle_q = cur_cycle; n_assert++;
      end
      if (vif.mon_cb.timer0_irq[0] && !prev_t0[0]) begin
        emit(RF_IRQ_T0_C0_OVF, 1'b1, 1'b0, 1'b0);
        assert_cycle_q = cur_cycle; n_assert++;
      end
      if (vif.mon_cb.timer0_irq[2] && !prev_t0[2]) begin
        emit(RF_IRQ_T0_C1_OVF, 1'b1, 1'b0, 1'b0);
        assert_cycle_q = cur_cycle; n_assert++;
      end
      if (vif.mon_cb.timer0_irq[3] && !prev_t0[3]) begin
        emit(RF_IRQ_T0_C1_CMP, 1'b1, 1'b0, 1'b0);
        assert_cycle_q = cur_cycle; n_assert++;
      end
      if (vif.mon_cb.timer0_irq[1] && !prev_t0[1]) begin
        emit(RF_IRQ_MTIP, 1'b1, 1'b0, 1'b0);   // also drives timer_irq_i
        assert_cycle_q = cur_cycle; n_assert++;
      end
      if (vif.mon_cb.timer1_irq[0] && !prev_t1[0]) begin
        emit(RF_IRQ_T1_C0_OVF, 1'b1, 1'b0, 1'b0);
        assert_cycle_q = cur_cycle; n_assert++;
      end
      if (vif.mon_cb.timer1_irq[1] && !prev_t1[1]) begin
        emit(RF_IRQ_T1_C0_CMP, 1'b1, 1'b0, 1'b0);
        assert_cycle_q = cur_cycle; n_assert++;
      end
      if (vif.mon_cb.timer1_irq[2] && !prev_t1[2]) begin
        emit(RF_IRQ_T1_C1_OVF, 1'b1, 1'b0, 1'b0);
        assert_cycle_q = cur_cycle; n_assert++;
      end
      if (vif.mon_cb.timer1_irq[3] && !prev_t1[3]) begin
        emit(RF_IRQ_T1_C1_CMP, 1'b1, 1'b0, 1'b0);
        assert_cycle_q = cur_cycle; n_assert++;
      end

      // ---- grant (arbiter) ----
      if (vif.mon_cb.irq_pending && !prev_pending) begin
        grant_cycle_q = cur_cycle;
        src_q         = irq_src_of_cause_enc(vif.mon_cb.irq_cause_enc);
        emit(src_q, 1'b1, 1'b1, 1'b0);
        n_grant++;
      end

      // ---- ack (commit of an interrupt trap) ----
      if (vif.mon_cb.trap_is_interrupt) begin
        rf_irq_src_e s;
        s = irq_src_of_mcause31({1'b1, vif.mon_cb.trap_cause});
        emit(s, 1'b1, 1'b1, 1'b1);
        ack_cycle_q = cur_cycle;
        n_ack++;
      end

      if (vif.mon_cb.mret_commit) begin
        irq_txn_t mt;
        n_mret++;
        mt = '0;
        mt.timestamp = tick(q_irq.size());
        mt.rel_cycle = cur_rel_cycle;
        mt.seq       = q_irq.size();
        mt.src       = RF_IRQ_NONE;
        mt.is_mret   = 1'b1;
        mt.nest_depth= vif.mon_cb.nest_depth;
        q_irq.push_back(mt);
        if (db != null) db.record_irq(mt, freeze);
        ring.push(mt, freeze);
      end

      // ---- update edge history ----
      prev_gpio    = vif.mon_cb.gpio_irq;
      prev_i2c     = vif.mon_cb.i2c_irq;
      prev_spi0    = vif.mon_cb.spi_irq[0];
      prev_spi1    = vif.mon_cb.spi_irq[1];
      prev_uart    = vif.mon_cb.uart_irq;
      prev_t0      = vif.mon_cb.timer0_irq;
      prev_t1      = vif.mon_cb.timer1_irq;
      prev_pend    = vif.mon_cb.gateway_pend;
      prev_pending = vif.mon_cb.irq_pending;
    end
  endtask

  function string dump_recent(int n = 16);
    return ring.dump(n, $sformatf("assert=%0d grant=%0d ack=%0d mret=%0d",
                                  n_assert, n_grant, n_ack, n_mret));
  endfunction
endclass

// =============================================================================
// 8. rf_pin_monitor  (UART TX/RX, I2C SCL/SDA, SPI SCLK/CS/MOSI/MISO, GPIO[31:0])
// =============================================================================
// Edge-driven. Each sub-block samples the resolved lines every clock and emits
// one transaction per meaningful event:
//   UART : per byte (start bit + 8 data + stop), tagged TX or RX
//   I2C  : per START/STOP and per 8-bit byte sampled on SCL rising edges
//   SPI  : per SCLK edge plus a transaction marker on CS deassertion
//   GPIO : on any change of gpio_in vs gpio_in_sync, with a moved-bit mask
class rf_pin_monitor extends rf_monitor_base;

  virtual rf_pin_if vif;

  gpio_txn_t     q_gpio[$];
  uart_txn_t     q_uart[$];
  i2c_txn_t      q_i2c[$];
  spi_txn_t      q_spi[$];

  // GPIO previous state for the moved-bit mask
  logic [31:0] prev_gpio_in_sync;

  // I2C byte assembly
  i2c_txn_t      i2c_tx;
  int            i2c_bit_idx;

  // SPI byte assembly
  spi_txn_t      spi_tx;
  int            spi_bit_idx;

  // UART bit assembly
  uart_txn_t     uart_tx;
  int            uart_bit_idx;

  function new(rf_if_ports ports, rf_trace_db db);
    super.new("PIN", LAYER_PIN);
    this.vif = ports.pin;
    bind_db(db);
    prev_gpio_in_sync = '0;
    i2c_tx = '0;   i2c_bit_idx = 0;
    spi_tx = '0;   spi_bit_idx = 0;
    uart_tx = '0;  uart_bit_idx = 0;
  endfunction

  // ---- GPIO ----------------------------------------------------------------
  task automatic sample_gpio();
    gpio_txn_t t;
    logic [31:0] moved;
    moved = vif.mon_cb.gpio_in ^ vif.mon_cb.gpio_in_sync;
    if ((vif.mon_cb.gpio_in_sync != prev_gpio_in_sync) || (moved != '0) ||
        vif.mon_cb.gpio_global_irq || (vif.mon_cb.gpio_pin_irq != '0)) begin
      t             = '0;
      t.timestamp   = tick(q_gpio.size());
      t.rel_cycle   = cur_rel_cycle;
      t.seq         = q_gpio.size();
      t.gpio_in     = vif.mon_cb.gpio_in;
      t.gpio_out    = vif.mon_cb.gpio_out;
      t.gpio_oe     = vif.mon_cb.gpio_oe;
      t.gpio_in_sync= vif.mon_cb.gpio_in_sync;
      t.moved       = moved;
      t.global_irq  = vif.mon_cb.gpio_global_irq;
      t.pin_irq     = vif.mon_cb.gpio_pin_irq;
      prev_gpio_in_sync = vif.mon_cb.gpio_in_sync;
      q_gpio.push_back(t);
      if (db != null) db.record_gpio(t, freeze);
    end
  endtask

  // ---- I2C -----------------------------------------------------------------
  // Emits an event on every SCL/SDA transition, and assembles 8-bit words on
  // SCL rising edges. START/STOP are SDA edges that occur while SCL is high.
  task automatic sample_i2c();
    i2c_txn_t t;
    bit scl, sda, scl_rise, sda_fall, sda_rise, start, stop;

    scl      = vif.mon_cb.scl;
    sda      = vif.mon_cb.sda;
    scl_rise = scl && !vif.mon_cb.scl_d;
    sda_fall = !sda && vif.mon_cb.sda_d;
    sda_rise = sda && !vif.mon_cb.sda_d;
    start    = sda_fall && scl;
    stop     = sda_rise && scl;

    if (start) begin
      i2c_bit_idx = 0;
      i2c_tx.data_byte = '0;
    end

    if (start || stop || scl_rise || sda_fall || sda_rise) begin
      // sample SDA on each SCL rising edge while a word is being assembled
      if (scl_rise && !start && (i2c_bit_idx < 8)) begin
        i2c_tx.data_byte[i2c_bit_idx[2:0]] = sda;
        i2c_bit_idx++;
      end
      t = '0;
      t.timestamp      = tick(q_i2c.size());
      t.rel_cycle      = cur_rel_cycle;
      t.seq            = q_i2c.size();
      t.scl            = scl;
      t.sda            = sda;
      t.scl_oen        = vif.mon_cb.scl_oen;
      t.sda_oen        = vif.mon_cb.sda_oen;
      t.start          = start;
      t.stop           = stop;
      t.scl_rise       = scl_rise;
      t.scl_fall       = (!scl && vif.mon_cb.scl_d);
      t.sda_fall       = sda_fall;
      t.sda_rise       = sda_rise;
      t.data_byte  = i2c_tx.data_byte;
      t.bit_done       = (i2c_bit_idx == 8);

      if (stop) i2c_bit_idx = 0;

      q_i2c.push_back(t);
      if (db != null) db.record_i2c(t, freeze);
    end
  endtask

  // ---- SPI -----------------------------------------------------------------
  // Emits an event per SCLK edge plus a marker whenever spi_events_o fires.
  // CSn are ACTIVE LOW; the master word is assembled on SCLK rising edges.
  task automatic sample_spi();
    spi_txn_t t;
    bit sclk_rise, sclk_fall, cs_active;

    sclk_rise = vif.mon_cb.sclk && !vif.mon_cb.sclk_d;
    sclk_fall = !vif.mon_cb.sclk && vif.mon_cb.sclk_d;
    cs_active = !(vif.mon_cb.csn0 & vif.mon_cb.csn1);

    if (sclk_rise) begin
      if (spi_bit_idx < 8) spi_tx.data_byte[spi_bit_idx[2:0]] = vif.mon_cb.mosi;
      spi_bit_idx = (spi_bit_idx + 1) % 8;
    end

    if (sclk_rise || sclk_fall || (vif.mon_cb.spi_events != 2'b00)) begin
      t               = '0;
      t.timestamp     = tick(q_spi.size());
      t.rel_cycle     = cur_rel_cycle;
      t.seq           = q_spi.size();
      t.sclk_rise     = sclk_rise;
      t.sclk_fall     = sclk_fall;
      t.cs            = {vif.mon_cb.csn1, vif.mon_cb.csn0};
      t.mosi          = vif.mon_cb.mosi;
      t.miso          = vif.mon_cb.miso;
      t.data_byte     = spi_tx.data_byte;
      t.bit_idx       = spi_bit_idx[4:0];
      t.spi_events    = vif.mon_cb.spi_events;
      t.tx_word_done  = !cs_active;

      q_spi.push_back(t);
      if (db != null) db.record_spi(t, freeze);
    end
  endtask

  // ---- UART ----------------------------------------------------------------
  // Deliberately a LINE-LEVEL monitor: it timestamps every edge of the DUT TX
  // line and of the RX line, and measures the start-bit width in clock cycles
  // (which is how a baud-rate mismatch shows up as an IP/VIP failure).
  // Byte-level decode is owned by vip/uart_pin_vip.sv, which oversamples.
  task automatic sample_uart();
    uart_txn_t t;
    longint unsigned prev_start_cycle;
    int          bit_cycles;

    prev_start_cycle = uart_tx.timestamp;
    bit_cycles       = 0;
    if (prev_start_cycle != 0) bit_cycles = int'(cur_cycle - prev_start_cycle);

    if (vif.mon_cb.uart_tx != vif.mon_cb.uart_tx_d) begin
      t             = '0;
      t.timestamp   = tick(q_gpio.size());
      t.rel_cycle   = cur_rel_cycle;
      t.seq         = q_uart.size();
      t.tx          = 1'b1;
      t.start_bit   = (vif.mon_cb.uart_tx == 1'b0);   // 1->0 == START
      t.stop_bit    = (vif.mon_cb.uart_tx == 1'b1) &&
                      (uart_tx.start_bit);           // rising edge out of START
      t.data_byte  = uart_tx.data_byte;
      t.bit_cycles  = bit_cycles;

      if (t.start_bit) begin
        uart_bit_idx    = 0;
        uart_tx.data_byte    = '0;
        uart_tx.timestamp = cur_cycle;
      end else begin
        uart_bit_idx++;
        if (uart_bit_idx < 8) uart_tx.data_byte[uart_bit_idx[2:0]] = vif.mon_cb.uart_tx;
      end
      t.data_byte  = uart_tx.data_byte;

      q_uart.push_back(t);
      if (db != null) db.record_uart(t, freeze);
    end

    if (vif.mon_cb.uart_rx != vif.mon_cb.uart_rx_d) begin
      t             = '0;
      t.timestamp   = tick(q_gpio.size());
      t.rel_cycle   = cur_rel_cycle;
      t.seq         = q_uart.size();
      t.tx          = 1'b0;
      t.start_bit   = (vif.mon_cb.uart_rx == 1'b0);
      t.bit_cycles  = 0;
      q_uart.push_back(t);
      if (db != null) db.record_uart(t, freeze);
    end
  endtask

  virtual task run();
    forever begin
      @(vif.mon_cb);

      cur_cycle     = vif.mon_cb.tb_cycle;
      cur_rel_cycle = vif.mon_cb.tb_rel_cycle;
      this.freeze   = vif.mon_cb.freeze;

      if (!enable) continue;

      sample_gpio();
      sample_i2c();
      sample_spi();
      sample_uart();
    end
  endtask

  function string dump_recent(int n = 16);
    string s;
    s  = $sformatf("gpio_events=%0d i2c_events=%0d spi_events=%0d uart_events=%0d\n",
                   q_gpio.size(), q_i2c.size(), q_spi.size(), q_uart.size());
    for (int i = (q_gpio.size()-n < 0 ? 0 : q_gpio.size()-n); i < q_gpio.size(); i++)
      s = {s, $sformatf("  GPIO cyc %0d in=%08h sync=%08h out=%08h oe=%08h moved=%08h gint=%b pint=%08h\n",
                        q_gpio[i].timestamp, q_gpio[i].gpio_in, q_gpio[i].gpio_in_sync,
                        q_gpio[i].gpio_out, q_gpio[i].gpio_oe, q_gpio[i].moved,
                        q_gpio[i].global_irq, q_gpio[i].pin_irq)};
    return s;
  endfunction
endclass

`endif // RF_MONITORS_SV