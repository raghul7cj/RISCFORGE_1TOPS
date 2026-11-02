// =============================================================================
// RISCFORGE 1TOPS — SoC transaction tracer (testbench only, never synthesised)
// =============================================================================
// Bound into riscforge_soc_subsystem by soc_tracer_bind.sv, so no RTL file and
// no testbench file changes. Writes one text line per event to a log file that
// ips/debug_trace/soc_trace.py joins with the firmware ELF:
//
//   PC -> instruction word -> assembly -> C file:line
//
// What is recorded, per clock (all sampled at posedge, i.e. the values of the
// cycle that is ending):
//
//   RET        an instruction entered WB for the first time and did not trap
//              (pc, fetched word as seen in ID, rd, value written)
//   TRAP       wb_trap_mret_commit_controller committed a trap (cause, mtval)
//   LSU_REQ    MEM stage started a non-DSRAM data access (MMIO or unmapped).
//              Opens transaction t=N. Only one can be open: hybrid_mem_interface
//              holds mem_stall until the AXI response is back.
//   HS         an AXI-Lite VALID/READY handshake on one of three ports, tagged
//              with the open (or most recent) transaction:
//                HMI = core_axi_req/resp     hybrid_mem_interface master port
//                XS  = xbar_slv_req/resp[0]  after axi_lite_timeout_monitor
//                XM  = xbar_mst_req/resp[2]  crossbar -> axi_lite_to_apb
//   APB_SETUP  PSEL=1 PENABLE=0 on an APB slot (slot NUM_APB = SPI behind the
//   APB_DONE   ACCESS phase completed (PREADY seen by the bridge). Both the
//              slave-side and bridge-side responses are logged, so an answer
//              made up by apb_timeout_monitor is visible.        bootloader)
//   LSU_DONE   MEM stage released the access (raw rdata, ls_unit-formatted
//              rdata, mem_err). LSU_ABORT if mem_req dropped first.
//   PROTO      AXI or APB protocol violation seen on any of the ports above
//   TMO        apb_timeout_monitor / axi_lite_timeout_monitor fired
//   MBOX       store to the DSRAM mailbox words (regtest result protocol)
//   STUCK      a transaction has been open for TRACE_STUCK cycles (repeats x4)
//   NO_RETIRE  nothing retired for TRACE_HANG cycles (repeats x4)
//   STATE/PIPE handshake state of every hop + PC of every pipeline stage;
//              PIPE ... src=ring is the last RING_DEPTH cycles before a trap,
//              a hang or the end of the simulation
//
// Plusargs
//   +TRACE_FILE=<path>     log file              (default soc_trace.log)
//   +TRACE_NO_RETIRE       drop RET lines (smaller log, no EX-stage check)
//   +TRACE_SRAM            also log every DSRAM access
//   +TRACE_STUCK=<n>       open-transaction watchdog, cycles   (default 256)
//   +TRACE_HANG=<n>        no-retire watchdog, cycles          (default 5000)
//   +TRACE_RING_DUMPS=<n>  max ring dumps on traps             (default 16)
// =============================================================================
`timescale 1ns/1ps

module soc_tracer
  import soc_tracer_pkg::*;
#(
  parameter int unsigned NUM_APB        = 6,
  parameter int unsigned NUM_XBAR_RULES = 3,
  // $bits() of the SoC's own structs, passed by the bind. 0 = not checked.
  parameter int unsigned SOC_AXI_REQ_W  = 0,
  parameter int unsigned SOC_AXI_RESP_W = 0,
  parameter int unsigned SOC_APB_REQ_W  = 0,
  parameter int unsigned SOC_APB_RESP_W = 0,
  parameter int unsigned SOC_RULE_W     = 0,
  // Must match hybrid_mem_interface's parameters in riscforge_soc_subsystem
  parameter logic [31:0] DSRAM_BASE     = 32'h0002_0000,
  parameter logic [31:0] DSRAM_LIMIT    = 32'h0002_7FFF,
  parameter logic [31:0] MMIO_BASE      = 32'h4000_0000,
  parameter logic [31:0] MMIO_LIMIT     = 32'h4FFF_FFFF,
  // regtest result words (ips/mem_files/regtest/link.ld .result)
  parameter logic [31:0] MBOX_BASE      = 32'h0002_0000,
  parameter logic [31:0] MBOX_LIMIT     = 32'h0002_003F,
  parameter int unsigned RING_DEPTH     = 32
)(
  input  logic                           clk_i,
  input  logic                           sys_rst_ni,
  input  logic                           core_rst_ni,
  input  logic                           periph_rst_ni,
  input  logic                           spi_rst_ni,
  input  logic                           boot_done_i,

  // IF / ID
  input  logic [31:0]                    pc_f,
  input  logic [31:0]                    pc_d,
  input  logic [31:0]                    instr_d,
  input  logic                           valid_d,
  // EX
  input  logic [31:0]                    pc_e,
  input  logic                           valid_e,
  // MEM
  input  logic [31:0]                    pc_m,
  input  logic                           valid_m,
  input  logic [4:0]                     lsunit_m,
  input  logic [31:0]                    alu_result_m,
  input  logic [31:0]                    write_data_m,
  input  logic                           mem_hold_wb,     // memory_cycle.core_stall_gated
  input  logic [31:0]                    lsu_fmt_rdata,   // memory_cycle.lsu_core_rdata
  // WB
  input  logic [31:0]                    pc_w,
  input  logic                           valid_w,
  input  logic                           exc_valid_w,
  input  logic                           regwrite_w,      // top.RegWriteW_gated
  input  logic [4:0]                     rd_w,
  input  logic [31:0]                    result_w,
  // Hazard unit
  input  logic                           stall_f, stall_d, stall_e, stall_m,
  input  logic                           flush_d, flush_e, flush_m, flush_w,
  input  logic                           mem_stall, mul_stall, pcsrc_e,
  input  logic                           trap_redirect,
  // Trap commit
  input  logic                           trap_valid,
  input  logic [30:0]                    trap_cause,
  input  logic [31:0]                    trap_pc,
  input  logic [31:0]                    trap_addr,
  input  logic                           trap_is_irq,
  input  logic                           mret_commit,

  // LSU bus (top.v <-> hybrid_mem_interface)
  input  logic                           lsu_req,
  input  logic                           lsu_we,
  input  logic [31:0]                    lsu_addr,
  input  logic [31:0]                    lsu_wdata,
  input  logic [3:0]                     lsu_be,
  input  logic [31:0]                    lsu_rdata,
  input  logic                           lsu_stall,
  input  logic                           lsu_err,
  // hybrid_mem_interface FSMs
  input  logic [1:0]                     hmi_wr_state,
  input  logic [1:0]                     hmi_rd_state,

  // AXI-Lite ports
  input  trc_axi_req_t                   hmi_req,
  input  trc_axi_resp_t                  hmi_resp,
  input  trc_axi_req_t                   xs_req,
  input  trc_axi_resp_t                  xs_resp,
  input  trc_axi_req_t                   xm_req,
  input  trc_axi_resp_t                  xm_resp,

  // APB bridge
  input  logic                           bridge_state,    // axi_lite_to_apb.apb_state_q
  input  trc_apb_req_t  [NUM_APB-1:0]    apb_req,
  input  trc_apb_resp_t [NUM_APB-1:0]    apb_resp_slv,    // from the slaves
  input  trc_apb_resp_t [NUM_APB-1:0]    apb_resp_mst,    // as seen by the bridge
  input  trc_apb_req_t                   spi_req,         // bootloader -> apb_spi_master
  input  trc_apb_resp_t                  spi_resp,

  // Timeout monitors
  input  logic [NUM_APB-1:0]             tmo_apb,
  input  logic                           tmo_axi_wr,
  input  logic                           tmo_axi_rd,

  // Address maps
  input  trc_rule_t [NUM_XBAR_RULES-1:0] xbar_map,
  input  trc_rule_t [NUM_APB-1:0]        apb_map
);

  localparam int unsigned NSLOT  = NUM_APB + 1;   // APB slots + SPI passthrough
  localparam int unsigned SPI_PT = NUM_APB;
  localparam int unsigned NPORT  = 3;             // HMI, XS, XM
  localparam int unsigned NCH    = 5;             // AW, W, B, AR, R

  // ---------------------------------------------------------------------------
  //  Configuration / file
  // ---------------------------------------------------------------------------
  int              fd;
  longint unsigned cyc;
  bit              en_retire, en_sram;
  longint unsigned stuck_lim, hang_lim;
  int unsigned     ring_dumps_left;
  realtime         t_cyc0;

  initial begin
    string fname;
    if (SOC_AXI_REQ_W  != 0 && SOC_AXI_REQ_W  != $bits(trc_axi_req_t))
      $fatal(1, "[TRACER] axi_req_t is %0d bits in the SoC, %0d in soc_tracer_pkg", SOC_AXI_REQ_W,  $bits(trc_axi_req_t));
    if (SOC_AXI_RESP_W != 0 && SOC_AXI_RESP_W != $bits(trc_axi_resp_t))
      $fatal(1, "[TRACER] axi_resp_t is %0d bits in the SoC, %0d in soc_tracer_pkg", SOC_AXI_RESP_W, $bits(trc_axi_resp_t));
    if (SOC_APB_REQ_W  != 0 && SOC_APB_REQ_W  != $bits(trc_apb_req_t))
      $fatal(1, "[TRACER] apb_req_t is %0d bits in the SoC, %0d in soc_tracer_pkg", SOC_APB_REQ_W,  $bits(trc_apb_req_t));
    if (SOC_APB_RESP_W != 0 && SOC_APB_RESP_W != $bits(trc_apb_resp_t))
      $fatal(1, "[TRACER] apb_resp_t is %0d bits in the SoC, %0d in soc_tracer_pkg", SOC_APB_RESP_W, $bits(trc_apb_resp_t));
    if (SOC_RULE_W     != 0 && SOC_RULE_W     != $bits(trc_rule_t))
      $fatal(1, "[TRACER] rule_t is %0d bits in the SoC, %0d in soc_tracer_pkg", SOC_RULE_W, $bits(trc_rule_t));

    if (!$value$plusargs("TRACE_FILE=%s", fname))        fname           = "soc_trace.log";
    if (!$value$plusargs("TRACE_STUCK=%d", stuck_lim))   stuck_lim       = 256;
    if (!$value$plusargs("TRACE_HANG=%d", hang_lim))     hang_lim        = 5000;
    if (!$value$plusargs("TRACE_RING_DUMPS=%d", ring_dumps_left)) ring_dumps_left = 16;
    en_retire = !$test$plusargs("TRACE_NO_RETIRE");
    en_sram   =  $test$plusargs("TRACE_SRAM");

    fd = $fopen(fname, "w");
    if (fd == 0) $fatal(1, "[TRACER] cannot open %s for writing", fname);
    $fdisplay(fd, "# soc_tracer v1  (ips/debug_trace/soc_trace.py reads this file)");
    $display("[TRACER] SoC transaction trace -> %s", fname);
  end

  // ---------------------------------------------------------------------------
  //  State
  // ---------------------------------------------------------------------------
  // Transactions
  int unsigned     tid;              // id of the most recent non-DSRAM access
  bit              txn_open;
  longint unsigned txn_start;
  longint unsigned txn_next_stuck;
  logic            lsu_req_q, lsu_stall_q;

  // Retirement
  bit              wb_new;           // MEM/WB was (re)loaded at this edge
  logic            trap_valid_q;
  longint unsigned last_retire_cyc;
  longint unsigned next_hang;
  bit [31:0]       imap [bit [31:0]];   // pc -> word last seen in ID

  // Resets / boot
  logic            sys_rst_q, core_rst_q, periph_rst_q, spi_rst_q, boot_done_q;
  bit              maps_logged;

  // Pipeline ring buffer
  trc_pipe_t       ring     [RING_DEPTH];
  longint unsigned ring_cyc [RING_DEPTH];
  int unsigned     ring_wr, ring_cnt;

  // AXI handshake trackers [port][channel]
  bit              hs_wait  [NPORT][NCH];
  longint unsigned hs_since [NPORT][NCH];
  logic [63:0]     hs_pl    [NPORT][NCH];

  // APB trackers [slot]
  localparam int P_IDLE = 0, P_SETUP = 1, P_ACCESS = 2;
  int              ap_phase [NSLOT];
  longint unsigned ap_setup [NSLOT];
  trc_apb_req_t    ap_req   [NSLOT];

  // ---------------------------------------------------------------------------
  //  Formatting helpers
  // ---------------------------------------------------------------------------
  task automatic ev(input string s);
    $fdisplay(fd, "@%0d %s", cyc, s);
  endtask

  function automatic string tag();
    return $sformatf("t=%0d o=%0d", tid, txn_open);
  endfunction

  function automatic string ns_now();
    return $sformatf("ns=%0.1f", $realtime);
  endfunction

  function automatic string pname(input int p);
    case (p)
      0:       return "HMI";
      1:       return "XS";
      default: return "XM";
    endcase
  endfunction

  function automatic string cname(input int c);
    case (c)
      0:       return "AW";
      1:       return "W";
      2:       return "B";
      3:       return "AR";
      default: return "R";
    endcase
  endfunction

  function automatic string bub(input logic v);
    return (v === 1'b1) ? "" : "~";
  endfunction

  function automatic string flags4(input logic [3:0] v, input string names);
    string s;
    s = "";
    for (int i = 0; i < 4; i++)
      s = {s, (v[3-i] === 1'b1) ? names.substr(i, i) : "-"};
    return s;
  endfunction

  function automatic trc_pipe_t pipe_now();
    trc_pipe_t p;
    p.pc_f = pc_f;  p.pc_d = pc_d;  p.pc_e = pc_e;  p.pc_m = pc_m;  p.pc_w = pc_w;
    p.v_d  = valid_d; p.v_e = valid_e; p.v_m = valid_m; p.v_w = valid_w;
    p.stall = {stall_f, stall_d, stall_e, stall_m};
    p.flush = {flush_d, flush_e, flush_m, flush_w};
    p.mem_stall = mem_stall;  p.mul_stall = mul_stall;
    p.pcsrc = pcsrc_e;        p.trap_redirect = trap_redirect;
    p.lsu_req = lsu_req;      p.lsu_we = lsu_we;
    p.lsu_stall = lsu_stall;  p.lsu_err = lsu_err;
    p.lsu_addr = lsu_addr;
    return p;
  endfunction

  function automatic string pipe_str(input trc_pipe_t p);
    return $sformatf("F=%08h D=%08h%s E=%08h%s M=%08h%s W=%08h%s st=%s fl=%s ms=%0b mul=%0b br=%0b trp=%0b lsu=%0b%0b%0b%0b la=%08h",
                     p.pc_f, p.pc_d, bub(p.v_d), p.pc_e, bub(p.v_e), p.pc_m, bub(p.v_m),
                     p.pc_w, bub(p.v_w), flags4(p.stall, "FDEM"), flags4(p.flush, "DEMW"),
                     p.mem_stall, p.mul_stall, p.pcsrc, p.trap_redirect,
                     p.lsu_req, p.lsu_we, p.lsu_stall, p.lsu_err, p.lsu_addr);
  endfunction

  function automatic string hs_flags(input trc_axi_req_t q, input trc_axi_resp_t s);
    return $sformatf("aw%0b%0b,w%0b%0b,b%0b%0b,ar%0b%0b,r%0b%0b",
                     q.aw_valid, s.aw_ready, q.w_valid, s.w_ready, s.b_valid, q.b_ready,
                     q.ar_valid, s.ar_ready, s.r_valid, q.r_ready);
  endfunction

  task automatic dump_ring(input string why, input bit force_dump);
    int unsigned idx;
    if (!force_dump) begin
      if (ring_dumps_left == 0) return;
      ring_dumps_left--;
    end
    ev($sformatf("RING why=%s n=%0d", why, ring_cnt));
    for (int unsigned k = ring_cnt; k > 0; k--) begin
      idx = (ring_wr + RING_DEPTH - k) % RING_DEPTH;
      $fdisplay(fd, "@%0d PIPE %s src=ring", ring_cyc[idx], pipe_str(ring[idx]));
    end
  endtask

  task automatic dump_state(input string why);
    string a;
    a = "";
    for (int i = 0; i < NUM_APB; i++)
      a = {a, $sformatf("%s%0d:%0b%0b%0b%0b", (i == 0) ? "" : ",", i,
                        apb_req[i].psel, apb_req[i].penable,
                        apb_resp_slv[i].pready, apb_resp_mst[i].pready)};
    ev($sformatf("STATE why=%s %s hmi_wr=%0d hmi_rd=%0d bridge=%0d HMI=%s XS=%s XM=%s APB=%s SPI=%0b%0b%0b lsu=%0b%0b%0b%0b la=%08h %s",
                 why, tag(), hmi_wr_state, hmi_rd_state, bridge_state,
                 hs_flags(hmi_req, hmi_resp), hs_flags(xs_req, xs_resp), hs_flags(xm_req, xm_resp),
                 a, spi_req.psel, spi_req.penable, spi_resp.pready,
                 lsu_req, lsu_we, lsu_stall, lsu_err, lsu_addr, ns_now()));
    ev($sformatf("PIPE %s src=now", pipe_str(pipe_now())));
  endtask

  // ---------------------------------------------------------------------------
  //  AXI-Lite: one channel. Logs the handshake and checks the VALID rules.
  // ---------------------------------------------------------------------------
  task automatic hs(input int p, input int c, input logic v, input logic r,
                    input logic [63:0] pl, input string pl_str);
    if (v === 1'b1) begin
      if (!hs_wait[p][c]) begin
        hs_wait[p][c]  = 1'b1;
        hs_since[p][c] = cyc;
        hs_pl[p][c]    = pl;
      end else if (pl !== hs_pl[p][c]) begin
        ev($sformatf("PROTO %s bus=AXI port=%s ch=%s msg=payload_changed_while_VALID_waited_for_READY %s",
                     tag(), pname(p), cname(c), ns_now()));
        hs_pl[p][c] = pl;
      end
      if (r === 1'b1) begin
        ev($sformatf("HS %s port=%s ch=%s %s wait=%0d", tag(), pname(p), cname(c), pl_str,
                     cyc - hs_since[p][c]));
        hs_wait[p][c] = 1'b0;
      end
    end else if (hs_wait[p][c]) begin
      ev($sformatf("PROTO %s bus=AXI port=%s ch=%s msg=VALID_dropped_before_READY %s",
                   tag(), pname(p), cname(c), ns_now()));
      hs_wait[p][c] = 1'b0;
    end
  endtask

  task automatic axi_port(input int p, input trc_axi_req_t q, input trc_axi_resp_t s);
    hs(p, 0, q.aw_valid, s.aw_ready, 64'(q.aw),
       $sformatf("addr=%08h prot=%0d", q.aw.addr, q.aw.prot));
    hs(p, 1, q.w_valid,  s.w_ready,  64'(q.w),
       $sformatf("data=%08h strb=%h", q.w.data, q.w.strb));
    hs(p, 2, s.b_valid,  q.b_ready,  64'(s.b),
       $sformatf("resp=%0d", s.b.resp));
    hs(p, 3, q.ar_valid, s.ar_ready, 64'(q.ar),
       $sformatf("addr=%08h prot=%0d", q.ar.addr, q.ar.prot));
    hs(p, 4, s.r_valid,  q.r_ready,  64'(s.r),
       $sformatf("data=%08h resp=%0d", s.r.data, s.r.resp));
  endtask

  // ---------------------------------------------------------------------------
  //  APB: one slot. Logs SETUP / completed ACCESS and checks the APB rules.
  // ---------------------------------------------------------------------------
  task automatic apb_slot(input int i, input trc_apb_req_t q,
                          input trc_apb_resp_t rs, input trc_apb_resp_t rm);
    if (q.psel === 1'b1) begin
      if (q.penable !== 1'b1) begin
        if (ap_phase[i] == P_ACCESS)
          ev($sformatf("PROTO %s bus=APB slot=%0d msg=SETUP_before_previous_ACCESS_completed %s", tag(), i, ns_now()));
        else if (ap_phase[i] == P_SETUP)
          ev($sformatf("PROTO %s bus=APB slot=%0d msg=SETUP_held_more_than_one_cycle %s", tag(), i, ns_now()));
        ev($sformatf("APB_SETUP %s slot=%0d paddr=%08h write=%0d pwdata=%08h pstrb=%h pprot=%0d",
                     tag(), i, q.paddr, q.pwrite, q.pwdata, q.pstrb, q.pprot));
        ap_phase[i] = P_SETUP;
        ap_setup[i] = cyc;
        ap_req[i]   = q;
      end else begin
        if (ap_phase[i] == P_IDLE) begin
          ev($sformatf("PROTO %s bus=APB slot=%0d msg=ACCESS_without_SETUP %s", tag(), i, ns_now()));
          ap_setup[i] = cyc - 1;
          ap_req[i]   = q;
        end else if ({q.paddr, q.pwrite, q.pwdata, q.pstrb} !==
                     {ap_req[i].paddr, ap_req[i].pwrite, ap_req[i].pwdata, ap_req[i].pstrb}) begin
          ev($sformatf("PROTO %s bus=APB slot=%0d msg=PADDR_PWRITE_PWDATA_PSTRB_changed_during_transfer %s",
                       tag(), i, ns_now()));
          ap_req[i] = q;
        end
        ap_phase[i] = P_ACCESS;
        if (rm.pready === 1'b1) begin
          ev($sformatf("APB_DONE %s slot=%0d write=%0d prdata=%08h pslverr=%0d slv_pready=%0b slv_prdata=%08h slv_pslverr=%0b waits=%0d",
                       tag(), i, q.pwrite, rm.prdata, rm.pslverr,
                       rs.pready, rs.prdata, rs.pslverr, cyc - ap_setup[i] - 1));
          ap_phase[i] = P_IDLE;
        end
      end
    end else if (ap_phase[i] != P_IDLE) begin
      ev($sformatf("PROTO %s bus=APB slot=%0d msg=PSEL_dropped_before_PREADY %s", tag(), i, ns_now()));
      ap_phase[i] = P_IDLE;
    end
  endtask

  task automatic log_rst(input string name, input logic now, inout logic prev);
    if (now !== prev) ev($sformatf("RST name=%s val=%0b %s", name, now, ns_now()));
    prev = now;
  endtask

  // ---------------------------------------------------------------------------
  //  Per-cycle step
  // ---------------------------------------------------------------------------
  task automatic step();
    bit          lsu_start, is_dsram, in_mbox;
    int unsigned npsel;
    bit [31:0]   iw;

    // One-time: clock, configuration and address maps
    if (cyc == 0) t_cyc0 = $realtime;
    if (cyc == 1) ev($sformatf("CLK t0=%0.3f period=%0.3f", t_cyc0, $realtime - t_cyc0));
    if (!maps_logged && sys_rst_ni === 1'b1) begin
      ev($sformatf("CFG dsram=%08h-%08h mmio=%08h-%08h mbox=%08h-%08h napb=%0d spi_slot=%0d",
                   DSRAM_BASE, DSRAM_LIMIT, MMIO_BASE, MMIO_LIMIT, MBOX_BASE, MBOX_LIMIT,
                   NUM_APB, SPI_PT));
      for (int i = 0; i < NUM_XBAR_RULES; i++)
        ev($sformatf("MAP bus=XBAR rule=%0d idx=%0d start=%08h end=%08h",
                     i, xbar_map[i].idx, xbar_map[i].start_addr, xbar_map[i].end_addr));
      for (int i = 0; i < NUM_APB; i++)
        ev($sformatf("MAP bus=APB rule=%0d idx=%0d start=%08h end=%08h",
                     i, apb_map[i].idx, apb_map[i].start_addr, apb_map[i].end_addr));
      maps_logged = 1'b1;
    end

    // Resets / boot
    log_rst("sys",    sys_rst_ni,    sys_rst_q);
    log_rst("core",   core_rst_ni,   core_rst_q);
    log_rst("periph", periph_rst_ni, periph_rst_q);
    log_rst("spi",    spi_rst_ni,    spi_rst_q);
    if (boot_done_i !== boot_done_q) ev($sformatf("BOOT done=%0b %s", boot_done_i, ns_now()));
    boot_done_q = boot_done_i;

    // Ring buffer
    ring[ring_wr]     = pipe_now();
    ring_cyc[ring_wr] = cyc;
    ring_wr           = (ring_wr + 1) % RING_DEPTH;
    if (ring_cnt < RING_DEPTH) ring_cnt++;

    // ID: remember the word each PC was fetched as
    if (valid_d === 1'b1 && !$isunknown(pc_d) && !$isunknown(instr_d))
      imap[pc_d] = instr_d;

    // WB: retire / trap (only on the first cycle an instruction sits in WB;
    // MEM/WB holds its contents while a later access stalls MEM)
    if (core_rst_ni === 1'b1) begin
      if (wb_new && valid_w === 1'b1 && exc_valid_w !== 1'b1) begin
        last_retire_cyc = cyc;
        next_hang       = hang_lim;
        if (en_retire) begin
          iw = imap.exists(pc_w) ? imap[pc_w] : 32'h0;
          ev($sformatf("RET pc=%08h instr=%08h known=%0b rd=%0d val=%08h mret=%0b",
                       pc_w, iw, imap.exists(pc_w),
                       (regwrite_w === 1'b1) ? rd_w : 5'd0, result_w, mret_commit));
        end
      end
      if (trap_valid === 1'b1 && (trap_valid_q !== 1'b1 || wb_new)) begin
        ev($sformatf("TRAP %s pc=%08h cause=%0d irq=%0b tval=%08h %s",
                     tag(), trap_pc, trap_cause, trap_is_irq, trap_addr, ns_now()));
        dump_ring("trap", 1'b0);
      end
    end

    // MEM: start of a data access
    lsu_start = (core_rst_ni === 1'b1) && (lsu_req === 1'b1) &&
                !(lsu_req_q === 1'b1 && lsu_stall_q === 1'b1);
    is_dsram  = (lsu_addr >= DSRAM_BASE) && (lsu_addr <= DSRAM_LIMIT);
    in_mbox   = (lsu_addr >= MBOX_BASE)  && (lsu_addr <= MBOX_LIMIT);
    if (lsu_start) begin
      if (!is_dsram) begin
        if (txn_open)
          ev($sformatf("PROTO %s bus=LSU msg=new_access_while_previous_still_open %s", tag(), ns_now()));
        tid++;
        txn_open       = 1'b1;
        txn_start      = cyc;
        txn_next_stuck = stuck_lim;
        iw = imap.exists(pc_m) ? imap[pc_m] : 32'h0;
        ev($sformatf("LSU_REQ %s pc=%08h instr=%08h known=%0b lsunit=%02h we=%0b addr=%08h be=%h wdata=%08h rs2=%08h %s",
                     tag(), pc_m, iw, imap.exists(pc_m), lsunit_m, lsu_we, lsu_addr, lsu_be,
                     lsu_wdata, write_data_m, ns_now()));
      end else if (lsu_we === 1'b1 && in_mbox) begin
        ev($sformatf("MBOX pc=%08h addr=%08h be=%h wdata=%08h", pc_m, lsu_addr, lsu_be, lsu_wdata));
      end else if (en_sram) begin
        ev($sformatf("SRAM pc=%08h we=%0b addr=%08h be=%h wdata=%08h", pc_m, lsu_we, lsu_addr, lsu_be, lsu_wdata));
      end
    end

    // Bus hops
    axi_port(0, hmi_req, hmi_resp);
    axi_port(1, xs_req,  xs_resp);
    axi_port(2, xm_req,  xm_resp);
    npsel = 0;
    for (int i = 0; i < NUM_APB; i++) begin
      apb_slot(i, apb_req[i], apb_resp_slv[i], apb_resp_mst[i]);
      if (apb_req[i].psel === 1'b1) npsel++;
    end
    if (npsel > 1)
      ev($sformatf("PROTO %s bus=APB slot=-1 msg=%0d_PSEL_lines_high_at_once %s", tag(), npsel, ns_now()));
    // SPI behind the bootloader: only runtime (core) traffic, not the boot FSM
    if (boot_done_i === 1'b1) apb_slot(SPI_PT, spi_req, spi_resp, spi_resp);

    // Timeout monitors
    for (int i = 0; i < NUM_APB; i++)
      if (tmo_apb[i] === 1'b1) begin
        ev($sformatf("TMO %s kind=APB slot=%0d %s", tag(), i, ns_now()));
        dump_state("apb_timeout");
      end
    if (tmo_axi_wr === 1'b1) begin
      ev($sformatf("TMO %s kind=AXI_WR slot=-1 %s", tag(), ns_now()));
      dump_state("axi_wr_timeout");
    end
    if (tmo_axi_rd === 1'b1) begin
      ev($sformatf("TMO %s kind=AXI_RD slot=-1 %s", tag(), ns_now()));
      dump_state("axi_rd_timeout");
    end

    // MEM: end of the open access
    if (txn_open) begin
      if (lsu_req === 1'b1 && lsu_stall !== 1'b1) begin
        ev($sformatf("LSU_DONE %s pc=%08h rdata=%08h fmt=%08h err=%0b cycles=%0d",
                     tag(), pc_m, lsu_rdata, lsu_fmt_rdata, lsu_err, cyc - txn_start + 1));
        txn_open = 1'b0;
      end else if (lsu_req !== 1'b1) begin
        ev($sformatf("LSU_ABORT %s pc=%08h cycles=%0d hmi_wr=%0d hmi_rd=%0d %s",
                     tag(), pc_m, cyc - txn_start + 1, hmi_wr_state, hmi_rd_state, ns_now()));
        dump_state("lsu_abort");
        txn_open = 1'b0;
      end
    end

    // Watchdogs
    if (txn_open && (cyc - txn_start) >= txn_next_stuck) begin
      ev($sformatf("STUCK %s cycles=%0d %s", tag(), cyc - txn_start, ns_now()));
      dump_state("stuck");
      dump_ring("stuck", 1'b1);
      txn_next_stuck = txn_next_stuck * 4;
    end
    if (core_rst_ni === 1'b1 && (cyc - last_retire_cyc) >= next_hang) begin
      ev($sformatf("NO_RETIRE %s cycles=%0d %s", tag(), cyc - last_retire_cyc, ns_now()));
      dump_state("no_retire");
      dump_ring("no_retire", 1'b1);
      next_hang = next_hang * 4;
    end

    // Bookkeeping for the next cycle. MEM/WB loads (or is flushed) at the
    // coming edge unless memory_cycle holds it for a stalled access.
    if (core_rst_ni !== 1'b1) begin
      wb_new          = 1'b0;
      last_retire_cyc = cyc;
      next_hang       = hang_lim;
    end else begin
      wb_new = (flush_w === 1'b1) || (mem_hold_wb !== 1'b1);
    end
    lsu_req_q    = lsu_req;
    lsu_stall_q  = lsu_stall;
    trap_valid_q = trap_valid;
  endtask

  always @(posedge clk_i) begin
    step();
    cyc++;
  end

  // ---------------------------------------------------------------------------
  //  End of simulation: where was everything?
  // ---------------------------------------------------------------------------
  final begin
    if (fd != 0) begin
      ev($sformatf("END %s last_retire=%0d %s", tag(), last_retire_cyc, ns_now()));
      dump_state(txn_open ? "end_with_open_access" : "end");
      dump_ring("end", 1'b1);
      $fclose(fd);
    end
  end

endmodule : soc_tracer
