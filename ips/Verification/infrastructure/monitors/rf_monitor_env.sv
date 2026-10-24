`timescale 1ns/1ps

`ifndef RF_MONITOR_ENV_SV
`define RF_MONITOR_ENV_SV

import tb_pkg::*;

// =============================================================================
// 2. rf_monitor_env
// =============================================================================
class rf_monitor_env;

  // ---- the one shared timebase ----
  virtual rf_timebase_if tb;

  // ---- monitor interfaces ----
  virtual rf_fetch_if  if_fetch;
  virtual rf_retire_if if_retire;
  virtual rf_lsu_if    if_lsu;
  virtual rf_axil_if   if_axil;
  virtual rf_apb_if    if_apb;
  virtual rf_irq_if    if_irq;
  virtual rf_pin_if    if_pin;

  // ---- monitors ----
  rf_fetch_monitor  m_fetch;
  rf_retire_monitor m_retire;
  rf_lsu_monitor    m_lsu;
  rf_axil_monitor   m_axil;
  rf_apb_monitor    m_apb;
  rf_irq_monitor    m_irq;
  rf_pin_monitor    m_pin;

  rf_trace_db db;

  // knobs
  bit          verbose;
  int unsigned dump_depth;

  function new();
    db         = new();
    verbose    = 0;
    dump_depth = 24;
  endfunction

  // ---------------------------------------------------------------------
  // XSim 2022.2 cannot name an interface type in a class formal list, so the
  // whole set arrives through the rf_if_ports bundle declared in
  // tb/rf_monitor_if.sv. On VCS / Xcelium the eight interfaces could be passed
  // individually.
  function void build(rf_if_ports ports);
    this.tb       = ports.tb;
    this.if_fetch = ports.fetch;
    this.if_retire= ports.retire;
    this.if_lsu   = ports.lsu;
    this.if_axil  = ports.axil;
    this.if_apb   = ports.apb;
    this.if_irq   = ports.irq;
    this.if_pin   = ports.pin;

    m_fetch  = new(ports, db);
    m_retire = new(ports, db);
    m_lsu    = new(ports, db);
    m_axil   = new(ports, db);
    m_apb    = new(ports, db);
    m_irq    = new(ports, db);
    m_pin    = new(ports, db);

    // RISCFORGE has no retired-instruction net; the retire monitor borrows the
    // fetch monitor's PC -> instruction shadow to populate retire_txn_t.instr.
    m_retire.fetch_mon = m_fetch;
  endfunction

  // ---------------------------------------------------------------------
  // NOTE: the shared timebase is fanned out in MODULE scope
  // (tb/rf_mon_probe.sv :: fanout_timebase), NOT from here.
  //
  // XSim 2022.2 does not support assigning to an interface VARIABLE through a
  // virtual interface handle from inside a class - the write is silently
  // dropped, which would leave every transaction stamped with cycle 0 and make
  // the post-mortem useless. Module-scope continuous/procedural assignment to
  // an interface variable is supported, so the fan-out lives there.
  //
  // The monitors therefore only ever READ vif.mon_cb.tb_cycle.

  // ---------------------------------------------------------------------
  task automatic start();
    fork
      m_fetch .run();
      m_retire.run();
      m_lsu   .run();
      m_axil  .run();
      m_apb   .run();
      m_irq   .run();
      m_pin   .run();
    join_none
  endtask

  // ---------------------------------------------------------------------
  function void set_enable(bit en);
    m_fetch .enable = en;
    m_retire.enable = en;
    m_lsu   .enable = en;
    m_axil  .enable = en;
    m_apb   .enable = en;
    m_irq   .enable = en;
    m_pin   .enable = en;
  endfunction

  function void report_first_fatal(int layer, string check_id, string msg,
                                  longint unsigned cyc, logic [31:0] pc);
    db.note_fatal(layer, check_id, msg, cyc, pc);
  endfunction

  // ---------------------------------------------------------------------
  // S1.11 post-mortem report: newest-N window per monitor, ordered by cycle,
  // plus a join section that lines LSU / AXI / APB / RETIRE against each other
  // for the last few MMIO accesses. One page. Names the check and the layer.
  function string postmortem(int n = 24);
    string s;
    s = "\n";
    s = {s, "================================================================================\n"};
    s = {s, "            RISCFORGE SoC POST-MORTEM MONITOR DUMP\n"};
    s = {s, "================================================================================\n"};

    if (db.n_fatal != 0) begin
      s = {s, $sformatf("  FIRST FATAL : %s   layer=%d(%s)  cycle=%0d  pc=0x%08h\n",
                       db.fatal_check_id, db.fatal_layer, layer_name(db.fatal_layer),
                       db.fatal_cycle, db.fatal_pc)};
      s = {s, $sformatf("  DETAIL      : %s\n", db.fatal_msg)};
    end else begin
      s = {s, "  FIRST FATAL : none\n"};
    end

    s = {s, "\n---- MONITOR TOTALS ------------------------------------------------\n"};
    s = {s, m_fetch .banner(), "\n"};
    s = {s, m_retire.banner(), "\n"};
    s = {s, m_lsu   .banner(), "\n"};
    s = {s, m_axil  .banner(), "\n"};
    s = {s, m_apb   .banner(), "\n"};
    s = {s, m_irq   .banner(), "\n"};
    s = {s, m_pin   .banner(), "\n"};

    s = {s, "\n---- CYCLIC HISTORY (newest first) ----------------------------------\n"};
    s = {s, m_fetch .dump_recent(n), "\n"};
    s = {s, m_retire.dump_recent(n), "\n"};
    s = {s, m_lsu   .dump_recent(n), "\n"};
    s = {s, m_axil  .dump_recent(n), "\n"};
    s = {s, m_apb   .dump_recent(n), "\n"};
    s = {s, m_irq   .dump_recent(n), "\n"};

    s = {s, "\n---- CROSS-LAYER JOIN (newest MMIO accesses) -----------------------\n"};
    s = {s, join_mmio((n < 8) ? n : 8)};

    return s;
  endfunction

  // PATH-01..06 evidence: for each recent MMIO access, show the LSU event, the
  // AXI-Lite event and the APB transfer it should have produced.
  function string join_mmio(int n);
    string s;
    int unsigned cnt;
    cnt = 0;
    for (int i = db.q_lsu.size()-1; i >= 0 && cnt < n; i--) begin
      if (db.q_lsu[i].is_mmio) begin
        s = {s, $sformatf("  PC=0x%08h  %s  addr=0x%08h  slot=%0d(%s)\n",
                          db.q_lsu[i].pc, db.q_lsu[i].is_store ? "ST" : "LD",
                          db.q_lsu[i].addr, db.q_lsu[i].apb_slot,
                          apb_slot_name(db.q_lsu[i].apb_slot))};
        s = {s, $sformatf("      LSU  : t=%0d be=%b %s\n",
                          db.q_lsu[i].timestamp, db.q_lsu[i].be,
                          db.q_lsu[i].is_store
                            ? $sformatf("wdata=0x%08h", db.q_lsu[i].wdata)
                            : $sformatf("rdata=0x%08h", db.q_lsu[i].rdata))};
        s = {s, axi_side_of(db.q_lsu[i])};
        s = {s, apb_side_of(db.q_lsu[i])};
        cnt++;
      end
    end
    if (cnt == 0) s = "  (no MMIO accesses observed - scoreboard would be VACUOUS)\n";
    return s;
  endfunction

  function string axi_side_of(lsu_txn_t l);
    axi_txn_t a;
    a = db.axil_at(l.addr, l.timestamp + 64);
    if (a.timestamp == 0) return "      AXIL : *** NO AXI TRANSACTION ***\n";
    return $sformatf("      AXIL : t=%0d %s be=%b data=0x%08h resp=%s latency=%0d\n",
                     a.timestamp, a.is_write ? "WR" : "RD", a.strb, a.data,
                     axi_resp_name(a.resp),
                     a.is_write ? a.aw_to_b : a.ar_to_r);
  endfunction

  function string apb_side_of(lsu_txn_t l);
    apb_txn_t p;
    p = db.apb_on_slot(l.apb_slot, l.timestamp + 64);
    if (p.timestamp == 0)
      return $sformatf("      APB  : *** NO APB TRANSFER ON SLOT %0d ***\n", l.apb_slot);
    return $sformatf("      APB  : t=%0d slot=%0d %s paddr=0x%08h pstrb=%b prdata=0x%08h ws=%0d%s\n",
                     p.timestamp, p.slot, p.pwrite ? "WR" : "RD",
                     p.paddr, p.pstrb, p.prdata, p.wait_states,
                     p.pslverr ? " SLVERR" : "");
  endfunction

  // ---------------------------------------------------------------------
  function void write_postmortem(string path = "monitor_postmortem.txt",
                                 int n = 24);
    int fd;
    fd = $fopen(path, "w");
    if (fd == 0) begin
      $display("[MON] cannot open %s", path);
      return;
    end
    $fdisplay(fd, "%s", postmortem(n));
    $fclose(fd);
    $display("[MON] post-mortem written to %s", path);
  endfunction

endclass

`endif // RF_MONITOR_ENV_SV