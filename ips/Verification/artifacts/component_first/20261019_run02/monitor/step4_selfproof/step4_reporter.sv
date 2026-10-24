// =============================================================================
//  step4_reporter.sv : the failure reporter  (all the logic)
// =============================================================================
//  Implements Integration Guide section 3, "First failing check":
//
//    "When a check fires, the failure reporter records the cycle, check ID,
//     expected and actual values, and freezes the ring buffers that hold the last
//     transactions of every monitor. It blames the lowest layer that failed first
//     and marks later failures as downstream. The output is a one-page report
//     with the last retired instructions disassembled."
//
//  BLAME RULE
//    - the first check to fire is the blame;
//    - a later failure at a STRICTLY LOWER layer number is more fundamental, so
//      blame moves to it (reassignment) and the page is emitted again;
//    - every later failure at the same or a higher layer is a consequence, and is
//      recorded but suppressed.
//
//  WHY A REPORTER RATHER THAN $error IN EACH ACTION BLOCK
//  A bare $error prints a line and carries on.  With three buses in the path you
//  get hundreds of lines and the first one is usually a symptom three layers up
//  rather than the cause.  Draining one mailbox here is what makes the report
//  point at a cause.
//
//  WHY ALL THE STRINGS ARE HERE
//  Checkers send numbers.  A check ID then always reads the same way wherever it
//  fires, and the triage bucket keyed on that ID cannot drift from the prose.
// =============================================================================

`include "step4_cfg.svh"

module step4_reporter #(
  parameter string REPORT_FILE = `STEP4_REPORT_FILE,
  parameter string PCMAP_FILE  = `STEP4_PCMAP_FILE,
  parameter bit    USE_ISSUE   = 1
) (
  input logic clk,
  input logic rst_n,
step4_hub hub
);

  import step4_pkg::*;
  import step4_disasm_pkg::*;

  localparam int unsigned RING_DEPTH   = `STEP4_RING_DEPTH;
  localparam int unsigned RETIRE_DEPTH = `STEP4_RETIRE_DEPTH;
  localparam int unsigned MAX_FINDINGS = `STEP4_MAX_FINDINGS;
  // EVT_NCH / EVT_REGION / EVT_SLOTS come from step4_pkg: this module and the
  // three forwarders must agree on the geometry of the one shared `hub.evt`
  // array. See step4_pkg.sv (EVT_CH_AXI / EVT_CH_APB / EVT_CH_SB / EVT_NCH /
  // EVT_REGION) and step4_hub.sv.

  localparam string RULE =
    "================================================================================";

  int  rep_fd = 0;
  bit  halt_on_fatal = 0;
  bit  dsd_done = 0;         // pc map loaded

  // PC -> "function  file:line", from the Step 1 map when one is available.
  string pcmap [logic [31:0]];

  // ===========================================================================
  //  Setup
  // ===========================================================================
  task automatic init(input string name = "unnamed");
    hub.test_name = name;
    void'($value$plusargs("step4_halt=%d", halt_on_fatal));
    if (USE_ISSUE != 0) begin
      rep_fd = $fopen(REPORT_FILE, "w");
      if (rep_fd == 0)
        $display("[STEP4] WARNING: cannot open %0s for writing", REPORT_FILE);
      else
        $fdisplay(rep_fd, "%0s", RULE);
    end
    if (PCMAP_FILE != "") load_pcmap(PCMAP_FILE);
  endtask

  task automatic load_pcmap(input string fname);
    int    fd, code;
    logic [31:0] a;
    string  nm;
    fd = $fopen(fname, "r");
    if (fd == 0) begin
      $display("[STEP4] pc map %0s not readable -- using the built-in decoder", fname);
      return;
    end
    forever begin
      code = $fscanf(fd, "%h %s", a, nm);
      if (code != 2) break;
      pcmap[a] = nm;
    end
    $fclose(fd);
    dsd_done = 1'b1;
    $display("[STEP4] loaded %0d pc-map symbols from %0s", pcmap.size(), fname);
  endtask

  function automatic void reg_loc(input int ix, input string nm);
    if (ix >= 0 && ix <= LOC_MAX) hub.loc_name[ix] = nm;
  endfunction

  // ===========================================================================
  //  The mailbox drain: where blame is decided
  // ===========================================================================
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int unsigned ch = 0; ch < EVT_NCH; ch++) hub.evt_wp[ch] <= 0;
    end
    else begin
      // Drain every mailbox in full. With one region per checker there is no
      // longer a shared read pointer to keep in step with a shared write pointer,
      // and `.vld` is the single ownership flag: the reporter clears it on the
      // posedge, the owning forwarder sets it on the negedge. Draining all slots
      // also makes the blame deterministic for a fixed seed instead of dependent
      // on how far the old free-running pointer had wandered.
      for (int unsigned ch = 0; ch < EVT_NCH; ch++) begin
        for (int unsigned k = 0; k < EVT_REGION; k++) begin
          automatic int unsigned slot = ch*EVT_REGION + k;
          if (hub.evt[slot].vld) begin
            absorb(hub.evt[slot]);
            hub.evt[slot].vld = 1'b0; // Blocking clear prevents duplicate absorb
          end
        end
      end
    end
  end

  task automatic absorb(input step4_evt_t e);
    if (!hub.fatal_seen) begin
      // ---- first fatal: this is the blame, freeze, report now ----
      hub.fatal_seen  = 1'b1;
      hub.blame_layer = e.layer;
      hub.blame_cid   = e.cid;
      hub.blame_where = where_of(e);
      hub.frozen      = 1'b1;
      hub.report_req  = 1'b1;
      store(e, F_PRIMARY);
      emit_one_page("FIRST FATAL");
    end
    else if (e.layer < hub.blame_layer) begin
      // ---- a more fundamental layer spoke late: move the blame ----
      hub.blame_layer = e.layer;
      hub.blame_cid   = e.cid;
      hub.blame_where = where_of(e);
      hub.report_req  = 1'b1;
      store(e, F_REASSIGN);
      emit_one_page("BLAME REASSIGNED TO A LOWER LAYER");
    end
    else begin
      store(e, F_DOWNSTREAM);
    end
  endtask

  task automatic store(input step4_evt_t e, input finding_state_t st);
    if (hub.n_find < MAX_FINDINGS) begin
      hub.findings[hub.n_find] = e;
      hub.findings[hub.n_find].state = st;
      // BLOCKING increments. These were non-blocking, and the drain loop can
      // call store() up to EVT_SLOTS times in ONE time step: `n_find` therefore
      // read back unchanged on calls 2..N, so every finding in a cycle was
      // written to the same findings[k] slot and only the last survived. The
      // printed "N recorded, M downstream" line and final_verdict were wrong by
      // up to EVT_SLOTS-1 per cycle. Blocking is safe here because absorb() is
      // the only writer of n_find and this task has no other callers.
      hub.n_find = hub.n_find + 1;
      case (st)
        F_PRIMARY  : ;
        F_REASSIGN : hub.n_reas = hub.n_reas + 1;
        default    : hub.n_down = hub.n_down + 1;
      endcase
    end
  endtask

  // ===========================================================================
  //  Check-ID registry
  // ===========================================================================
  function automatic string cid_id(input int ix);
    case (ix)
      CID_AXIL_AW_STABLE    : return AXIL_AW_STABLE;
      CID_AXIL_W_STABLE     : return AXIL_W_STABLE;
      CID_AXIL_B_STABLE     : return AXIL_B_STABLE;
      CID_AXIL_AR_STABLE    : return AXIL_AR_STABLE;
      CID_AXIL_R_STABLE     : return AXIL_R_STABLE;
      CID_AXIL_VALID_HELD   : return AXIL_VALID_HELD;
      CID_AXIL_NO_X         : return AXIL_NO_X;
      CID_AXIL_RESP_LEGAL   : return AXIL_RESP_LEGAL;
      CID_AXIL_B_HAS_REQ    : return AXIL_W_AFTER_AW;
      CID_AXIL_NO_STALL     : return AXIL_NO_STALL;
      CID_AXIL_R_ANSWERED   : return AXIL_ERR_GONE;
      CID_APB_ENABLE_CON    : return APB_ENABLE_CON;
      CID_APB_ENABLE_SEQ    : return APB_ENABLE_SEQ;
      CID_APB_SETUP_STABLE  : return APB_SETUP_STABLE;
      CID_APB_COMPLETE      : return APB_COMPLETE;
      CID_APB_RDATA_ONLY_RD : return APB_READ_ONLY;
      CID_APB_ERR_IN_ACCESS : return APB_ERR_RSP;
      CID_APB_ALIGNED       : return APB_ALIGNED;
      CID_APB_ONE_SLOT      : return APB_ONE_SLOT;
      CID_APB_NO_X_ADDR     : return APB_NO_X;
      CID_APB_NO_X_CTRL     : return APB_NO_X;
      CID_PATH_NO_LOSS      : return PATH_NO_LOSS;
      CID_PATH_WDATA        : return PATH_WDATA;
      CID_PATH_STRB         : return PATH_STRB;
      CID_PATH_SLOT         : return PATH_SLOT;
      CID_PATH_ADDR         : return PATH_ADDR;
      CID_PATH_DIR          : return PATH_DIR;
      CID_PATH_RDATA        : return PATH_RDATA;
      CID_PATH_RESP         : return PATH_RESP;
      CID_PATH_NO_EXTRA_APB : return PATH_NO_EXTRA_APB;
      CID_PATH_HOLE         : return PATH_HOLE;
      CID_PATH_ZERO_STRB    : return PATH_ZERO_STRB;
      CID_PATH_ORDER        : return PATH_ORDER;
      CID_PATH_LATENCY      : return PATH_LATENCY;
      CID_REG_SUBWORD_ERR   : return REG_SUBWORD_ERR;
      default               : return "UNKNOWN-0000";
    endcase
  endfunction

  //  The location string.  For the APB checks word a carries the slot index, so
  //  one rendering serves both the per-slot loops and the fabric-wide checks.
  function automatic string where_of(input step4_evt_t e);
    string nm;
    nm = (e.loc <= LOC_MAX && hub.loc_name[e.loc] != "") ? hub.loc_name[e.loc] : "?";
    if (e.a[7:0] < NUM_APB_SLAVES)
      return $sformatf("%0s/APB[%0d]/%0s", nm, e.a[7:0], slot_name(e.a[7:0]));
    return nm;
  endfunction

  function automatic void render(input step4_evt_t e, output string e_str,
                                 output string a_str);
    case (e.cid)
      // ---- AXI ----
      // a = payload now, b = payload before
      CID_AXIL_AW_STABLE:
        begin
          e_str = $sformatf("AW payload stable while aw_valid=1, aw_ready=0: addr=0x%08h prot=%03b",
                            e.a[31:0], e.a[7:0]);
          a_str = $sformatf("AW payload moved under stall: addr 0x%08h -> 0x%08h, prot %03b -> %03b",
                            e.b[31:0], e.a[31:0], e.b[7:0], e.a[7:0]);
        end
      CID_AXIL_W_STABLE:
        begin
          e_str = $sformatf("W payload stable while stalled: data=0x%08h strb=%04b",
                            e.a[31:0], e.a[7:0]);
          a_str = $sformatf("W payload moved under stall: data 0x%08h -> 0x%08h, strb %04b -> %04b",
                            e.b[31:0], e.a[31:0], e.b[7:0], e.a[7:0]);
        end
      CID_AXIL_B_STABLE:
        begin
          e_str = $sformatf("B.RESP stable while stalled: %0s", resp_name(e.a[1:0]));
          a_str = $sformatf("B.RESP moved under stall: %0s -> %0s",
                            resp_name(e.b[1:0]), resp_name(e.a[1:0]));
        end
      CID_AXIL_AR_STABLE:
        begin
          e_str = $sformatf("AR payload stable while stalled: addr=0x%08h prot=%03b",
                            e.a[31:0], e.a[7:0]);
          a_str = $sformatf("AR payload moved under stall: addr 0x%08h -> 0x%08h",
                            e.b[31:0], e.a[31:0]);
        end
      CID_AXIL_R_STABLE:
        begin
          e_str = $sformatf("R payload stable while stalled: data=0x%08h resp=%0s",
                            e.a[31:0], resp_name(e.a[3:2]));
          a_str = $sformatf("R payload moved under stall: data 0x%08h -> 0x%08h, resp %0s -> %0s",
                            e.b[31:0], e.a[31:0], resp_name(e.b[3:2]), resp_name(e.a[3:2]));
        end
      CID_AXIL_VALID_HELD:
        begin
          e_str = "VALID stays asserted until READY";
          case (e.c[7:0])
            1: a_str = "AW dropped aw_valid before aw_ready";
            2: a_str = "W  dropped w_valid before w_ready";
            3: a_str = "B  dropped b_valid before b_ready";
            4: a_str = "AR dropped ar_valid before ar_ready";
            5: a_str = "R  dropped r_valid before r_ready";
            default: a_str = "a channel dropped VALID before READY";
          endcase
        end
      CID_AXIL_NO_X:
        begin
          e_str = "payload known whenever VALID is asserted";
          a_str = $sformatf("payload contains X/Z: 0x%08h", e.a);
        end
      CID_AXIL_RESP_LEGAL:
        begin
          e_str = "response is OKAY, SLVERR or DECERR";
          a_str = $sformatf("response is %0s -- EXOKAY is not defined for AXI4-Lite",
                            resp_name(e.a[1:0]));
        end
      CID_AXIL_B_HAS_REQ:
        begin
          e_str = "both AW and W handshaked before the write response";
          a_str = $sformatf("B accepted with aw_seen=%0b w_seen=%0b", e.a[0], e.a[1]);
        end
      CID_AXIL_NO_STALL:
        begin
          e_str = $sformatf("%0s accepted within %0d cycles",
                            (e.c[7:0] != 0) ? "the response" : "the request", e.d);
          a_str = $sformatf("%0s still stalled after %0d cycles",
                            (e.c[7:0] != 0) ? "the response" : "the request", e.d);
        end
      CID_AXIL_R_ANSWERED:
        begin
          e_str = $sformatf("read of 0x%08h answered within %0d cycles", e.a, e.d);
          a_str = $sformatf("read of 0x%08h was accepted and never answered", e.a);
        end

      // ---- APB ----
      CID_APB_ENABLE_CON:
        begin
          e_str = $sformatf("PENABLE implies PSEL on APB[%0d] (%0s)", e.a[7:0], slot_name(e.a[7:0]));
          a_str = $sformatf("PENABLE=1 while PSEL=0 on APB[%0d] (%0s)", e.a[7:0], slot_name(e.a[7:0]));
        end
      CID_APB_ENABLE_SEQ:
        begin
          e_str = $sformatf("APB[%0d] leaves setup: PENABLE next cycle, or PSEL drops", e.a[7:0]);
          a_str = $sformatf("APB[%0d] held PSEL=1 PENABLE=0 for a second cycle", e.a[7:0]);
        end
      CID_APB_SETUP_STABLE:
        begin
          e_str = $sformatf("APB[%0d] payload held into the access phase: PADDR=0x%08h PWDATA=0x%08h PSTRB=%04b",
                            e.a[7:0], e.d, e.b, e.c[3:0]);
          a_str = $sformatf("APB[%0d] payload changed: PADDR 0x%08h -> 0x%08h, PSTRB %04b -> %04b",
                            e.a[7:0], e.d, e.a[31:8], e.b, e.c[3:0]);
        end
      CID_APB_COMPLETE:
        begin
          e_str = $sformatf("APB[%0d] (%0s) completes within %0d wait states at PADDR 0x%08h",
                            e.a[7:0], slot_name(e.a[7:0]), e.d, e.b);
          a_str = $sformatf("APB[%0d] still not ready after %0d cycles", e.a[7:0], e.d);
        end
      CID_APB_RDATA_ONLY_RD:
        begin
          e_str = $sformatf("APB[%0d] completed read returns known PRDATA", e.a[7:0]);
          a_str = $sformatf("APB[%0d] read completed with PRDATA=0x%08h (X/Z present)",
                            e.a[7:0], e.b);
        end
      CID_APB_ERR_IN_ACCESS:
        begin
          e_str = $sformatf("APB[%0d] asserts PSLVERR only in the access phase", e.a[7:0]);
          a_str = $sformatf("APB[%0d] PSLVERR=1 while PSEL=0 PENABLE=0", e.a[7:0]);
        end
      CID_APB_ALIGNED:
        begin
          e_str = $sformatf("APB[%0d] PADDR is word aligned (the bridge applies aligned_addr)", e.a[7:0]);
          a_str = $sformatf("APB[%0d] PADDR=0x%08h has PADDR[1:0]=%02b -- the peripheral decodes the wrong register",
                            e.a[7:0], e.b, e.b[1:0]);
        end
      CID_APB_ONE_SLOT:
        begin
          e_str = "at most one APB PSEL asserted across the six slots";
          a_str = $sformatf("PSEL=0x%02b -- more than one peripheral is being addressed at once", e.a[5:0]);
        end
      CID_APB_NO_X_ADDR:
        begin
          e_str = "PADDR known whenever PSEL is asserted";
          a_str = $sformatf("PADDR contains X/Z while PSEL=0x%02b", e.a[5:0]);
        end
      CID_APB_NO_X_CTRL:
        begin
          e_str = "PWDATA/PSTRB known on a write with PSEL asserted";
          a_str = $sformatf("PWDATA/PSTRB contains X/Z on a write: 0x%08h", e.a);
        end

      // ---- PATH ----
      CID_PATH_NO_LOSS:
        begin
          e_str = $sformatf("the access to 0x%08h reaches the AXI fabric as one transaction", e.a);
          a_str = $sformatf("no AW/W or AR was ever issued for 0x%08h", e.a);
        end
      CID_PATH_WDATA:
        begin
          e_str = $sformatf("write data survives the path unchanged: 0x%08h", e.b);
          a_str = $sformatf("write data 0x%08h, expected 0x%08h", e.c, e.b);
        end
      CID_PATH_STRB:
        begin
          e_str = $sformatf("byte strobes survive the path unchanged: %04b", e.b[3:0]);
          a_str = $sformatf("byte strobes %04b, expected %04b -- a byte lane was dropped or duplicated",
                            e.c[3:0], e.b[3:0]);
        end
      CID_PATH_SLOT:
        begin
          e_str = $sformatf("the transfer lands on APB[%0d] (%0s), the slot the address map gives",
                            e.a[7:0], slot_name(e.a[7:0]));
          a_str = $sformatf("the transfer for 0x%08h landed on APB[%0d] (%0s)",
                            e.b, e.c[7:0], slot_name(e.c[7:0]));
        end
      CID_PATH_ADDR:
        begin
          e_str = $sformatf("PADDR equals the 4-byte-aligned AXI address: 0x%08h", e.a);
          a_str = $sformatf("PADDR 0x%08h for an access to 0x%08h", e.b, e.c);
        end
      CID_PATH_DIR:
        begin
          e_str = $sformatf("APB PWRITE matches the AXI direction: %0b", e.a[0]);
          a_str = $sformatf("APB PWRITE=%0b, the access was a %0s", e.b[0], e.a[0] ? "write" : "read");
        end
      CID_PATH_RDATA:
        begin
          e_str = $sformatf("AXI RDATA equals the APB PRDATA read from the slot: 0x%08h", e.b);
          a_str = $sformatf("AXI RDATA 0x%08h, the APB slave returned 0x%08h", e.c, e.b);
        end
      CID_PATH_RESP:
        begin
          e_str = "APB PSLVERR reaches the core as RESP_SLVERR";
          a_str = $sformatf("the APB slave raised PSLVERR but the AXI response was %0s",
                            resp_name(e.a[1:0]));
        end
      CID_PATH_NO_EXTRA_APB:
        begin
          e_str = $sformatf("exactly one APB transfer per AXI transaction (0x%08h)", e.a);
          a_str = "the AXI transaction completed without the expected APB transfer";
        end
      CID_PATH_HOLE:
        begin
          e_str = $sformatf("an unmapped MMIO address (0x%08h) returns RESP_DECERR", e.a);
          a_str = $sformatf("returned %0s", resp_name(e.b[1:0]));
        end
      CID_PATH_ZERO_STRB:
        begin
          e_str = "a write with every byte strobe clear is a silent no-op and returns RESP_OKAY";
          a_str = $sformatf("returned %0s", resp_name(e.a[1:0]));
        end
      CID_PATH_ORDER:
        begin
          e_str = "one MMIO access outstanding at a time";
          a_str = $sformatf("0x%08h issued while 0x%08h is still in flight", e.a, e.b);
        end
      CID_PATH_LATENCY:
        begin
          e_str = $sformatf("0x%08h completes within %0d cycles for APB[%0d] (%0s)",
                            e.a, e.d, e.c[7:0], slot_name(e.c[7:0]));
          a_str = $sformatf("took %0d cycles", e.b);
        end

      CID_REG_SUBWORD_ERR:
        begin
          e_str = "a sub-word write (PSTRB != 4'hF) is answered with PSLVERR";
          a_str = $sformatf("PSTRB=%04b came back %0s", e.a[3:0], resp_name(e.b[1:0]));
        end

      default:
        begin
          e_str = "check passed no context";
          a_str = "unclassified failure";
        end
    endcase
  endfunction

  // ===========================================================================
  //  Ring pushes, called by the monitors
  // ===========================================================================
  task automatic push_lsu(input logic [31:0] addr, input bit is_write,
                          input logic [31:0] wdata, input logic [3:0] strb);
    step4_rec_t r;
    if (hub.frozen) return;
    r = REC_ZERO;
    r.kind     = REC_LSU;
    r.is_write = is_write;
    r.addr     = addr;
    r.wdata    = wdata;
    r.strb     = strb;
    r.cycle_lo = hub.cyc[15:0];
    r.slot     = NUM_APB_SLAVES;
    hub.ring_lsu[hub.wp_lsu] = r;
    hub.wp_lsu = (hub.wp_lsu + 1) % RING_DEPTH;
    if (hub.cnt_lsu < RING_DEPTH) hub.cnt_lsu <= hub.cnt_lsu + 1;
    hub.stats.lsu_reqs = hub.stats.lsu_reqs + 1;
  endtask

  task automatic push_axi(input rec_kind_t k, input bit is_write,
                          input logic [31:0] addr, input logic [31:0] wdata,
                          input logic [3:0] strb, input logic [31:0] rdata,
                          input logic [1:0] resp, input bit ok);
    step4_rec_t r;
    if (hub.frozen) return;
    r = REC_ZERO;
    r.kind     = k;
    r.is_write = is_write;
    r.addr     = addr;
    r.wdata    = wdata;
    r.rdata    = rdata;
    r.strb     = strb;
    r.resp     = resp;
    r.ok       = ok;
    r.cycle_lo = hub.cyc[15:0];
    r.slot     = NUM_APB_SLAVES;
    hub.ring_axi[hub.wp_axi] = r;
    hub.wp_axi = (hub.wp_axi + 1) % RING_DEPTH;
    if (hub.cnt_axi < RING_DEPTH) hub.cnt_axi <= hub.cnt_axi + 1;
    if (k == REC_AXI_REQ) begin
      if (is_write) hub.stats.axi_wrs = hub.stats.axi_wrs + 1;
      else          hub.stats.axi_rds = hub.stats.axi_rds + 1;
    end
    else begin
      if (resp == RESP_SLVERR) hub.stats.resp_slverr = hub.stats.resp_slverr + 1;
      if (resp == RESP_DECERR) hub.stats.resp_decerr = hub.stats.resp_decerr + 1;
    end
  endtask

  task automatic push_apb(input int unsigned slot, input logic [31:0] paddr,
                          input bit pwrite, input logic [31:0] pwdata,
                          input logic [3:0] pstrb, input logic [31:0] prdata,
                          input bit pslverr, input bit is_timeout);
    step4_rec_t r;
    if (hub.frozen) return;
    r = REC_ZERO;
    r.kind       = is_timeout ? REC_APB_TO : REC_APB_XFER;
    r.is_write   = pwrite;
    r.addr       = paddr;
    r.wdata      = pwdata;
    r.rdata      = prdata;
    r.strb       = pstrb;
    r.resp       = {1'b0, pslverr};
    r.slot       = slot;
    r.ok         = !is_timeout && !pslverr;
    r.cycle_lo   = hub.cyc[15:0];
    hub.ring_apb[hub.wp_apb] = r;
    hub.wp_apb = (hub.wp_apb + 1) % RING_DEPTH;
    if (hub.cnt_apb < RING_DEPTH) hub.cnt_apb <= hub.cnt_apb + 1;
    hub.stats.apb_xfers[slot] = hub.stats.apb_xfers[slot] + 1;
    if (is_timeout) hub.stats.apb_timeouts = hub.stats.apb_timeouts + 1;
  endtask

  task automatic push_retire(input logic [31:0] pc, input logic [31:0] inst);
    if (hub.frozen) return;
    hub.ret_pc[hub.wp_ret] = pc;
    hub.ret_in[hub.wp_ret] = inst;
    hub.wp_ret = (hub.wp_ret + 1) % RETIRE_DEPTH;
    if (hub.cnt_ret < RETIRE_DEPTH) hub.cnt_ret <= hub.cnt_ret + 1;
    hub.stats.retired = hub.stats.retired + 1;
  endtask

  // ===========================================================================
  //  Re-arm.  NOT for production: a real test lets the freeze hold, so the
  //  evidence cannot be overwritten.  Only the Step 4 self-proof calls this, to
  //  run each fault case from a clean slate.
  // ===========================================================================
  task automatic arm_run(input string name);
    hub.test_name  = name;
    hub.fatal_seen = 0;
    hub.frozen     = 0;
    hub.report_req = 0;
    hub.n_find = 0; hub.n_down = 0; hub.n_reas = 0;
    hub.wp_lsu = 0; hub.cnt_lsu = 0;
    hub.wp_axi = 0; hub.cnt_axi = 0;
    hub.wp_apb = 0; hub.cnt_apb = 0;
    hub.wp_ret = 0; hub.cnt_ret = 0;
    for (int unsigned ch = 0; ch < EVT_NCH; ch++) begin
      hub.evt_wp[ch]  = 0;
      hub.evt_ovf[ch] = 0;
    end
    for (int unsigned i = 0; i < EVT_SLOTS; i++) hub.evt[i].vld = 0;
    clear_stats(hub.stats);
  endtask

  function automatic string first_id();
    return (hub.n_find > 0) ? cid_id(hub.findings[0].cid) : "";
  endfunction

  function automatic bit saw(input int ix);
    for (int unsigned i = 0; i < hub.n_find; i++)
      if (hub.findings[i].cid == ix) return 1'b1;
    return 1'b0;
  endfunction

  function automatic string blame_id();
    return cid_id(hub.blame_cid);
  endfunction

  function automatic bit is_fatal();
    return hub.fatal_seen;
  endfunction

  // ===========================================================================
  //  Report formatting
  // ===========================================================================
  function automatic string fmt_rec(input step4_rec_t r);
    return $sformatf("c%-6d %-4s %-2s addr=0x%08h wdata=0x%08h rdata=0x%08h strb=%04b slot=%-9s %0s",
                     r.cycle_lo, rec_name(r.kind), (r.is_write ? "W" : "R"),
                     r.addr, r.wdata, r.rdata, r.strb,
                     (r.slot < NUM_APB_SLAVES) ? slot_name(r.slot) : "-",
                     r.ok ? "ok" : "BAD");
  endfunction

  task automatic emit_ring(input string title, input int unsigned which,
                           input int unsigned wp, input int unsigned cnt);
    $display("  %-38s (%0d of %0d retained)", title, cnt, RING_DEPTH);
    if (rep_fd != 0)
      $fdisplay(rep_fd, "  %-38s (%0d of %0d retained)", title, cnt, RING_DEPTH);
    for (int unsigned k = 0; k < cnt; k++) begin
      step4_rec_t r;
      string      ln;
      if      (which == 0) r = hub.ring_lsu[(wp + RING_DEPTH - cnt + k) % RING_DEPTH];
      else if (which == 1) r = hub.ring_axi[(wp + RING_DEPTH - cnt + k) % RING_DEPTH];
      else                 r = hub.ring_apb[(wp + RING_DEPTH - cnt + k) % RING_DEPTH];
      ln = $sformatf("    #%-3d %0s", k, fmt_rec(r));
      $display("%0s", ln);
      if (rep_fd != 0) $fdisplay(rep_fd, "%0s", ln);
    end
  endtask

  task automatic emit_retire();
    $display("  LAST RETIRED INSTRUCTIONS  (%0d of %0d, oldest first)",
             hub.cnt_ret, RETIRE_DEPTH);
    if (rep_fd != 0)
      $fdisplay(rep_fd, "  LAST RETIRED INSTRUCTIONS  (%0d of %0d, oldest first)",
                hub.cnt_ret, RETIRE_DEPTH);
    for (int unsigned k = 0; k < hub.cnt_ret; k++) begin
      int unsigned idx = (hub.wp_ret + RETIRE_DEPTH - hub.cnt_ret + k) % RETIRE_DEPTH;
      logic [31:0] pc  = hub.ret_pc[idx];
      logic [31:0] ins = hub.ret_in[idx];
      string sym, ln;
      if (pcmap.exists(pc))                              sym = pcmap[pc];
      else if (pcmap.exists(pc & 32'hFFFF_FFFC))         sym = pcmap[pc & 32'hFFFF_FFFC];
      else                                                sym = "";
      ln = $sformatf("    #%-3d 0x%08h  %08h  %0s%0s", k, pc, ins, disasm(ins),
                     (sym != "") ? $sformatf("   ; %0s", sym) : "");
      $display("%0s", ln);
      if (rep_fd != 0) $fdisplay(rep_fd, "%0s", ln);
    end
  endtask

  task automatic emit_layer_status();
    $display("  LAYER STATUS");
    if (rep_fd != 0) $fdisplay(rep_fd, "  LAYER STATUS");
    for (int i = 1; i <= 7; i++) begin
      layer_t    L  = layer_t'(i);
      string     st;
      string     id = "-";
      for (int unsigned j = 0; j < hub.n_find; j++)
        if (hub.findings[j].layer == L) begin id = cid_id(hub.findings[j].cid); break; end
      if (hub.blame_layer == L)     st = "BLAME";
      else if (id == "-")            st = "quiet";
      else if (L < hub.blame_layer)  st = "FAIL";
      else                           st = "down";
      $display("    %-12s %-6s %0s", layer_name(L), st, id);
      if (rep_fd != 0)
        $fdisplay(rep_fd, "    %-12s %-6s %0s", layer_name(L), st, id);
    end
  endtask

  task automatic emit_counters();
    $display("  COUNTERS  (vacuity evidence for the pass rule)");
    $display("    lsu_reqs=%0d  axi_wrs=%0d  axi_rds=%0d  retired=%0d",
             hub.stats.lsu_reqs, hub.stats.axi_wrs, hub.stats.axi_rds, hub.stats.retired);
    $display("    apb xfers [I2C T0 UART GPIO SPI T1] = %0d %0d %0d %0d %0d %0d",
             hub.stats.apb_xfers[0], hub.stats.apb_xfers[1], hub.stats.apb_xfers[2],
             hub.stats.apb_xfers[3], hub.stats.apb_xfers[4], hub.stats.apb_xfers[5]);
    // Per-checker mailbox overflow. Reported separately so a lost event is
    // attributable to the forwarder that dropped it, and it is printed
    // unconditionally (not only on a fatal) so a silently-truncating
    // mailbox shows up even in a run that otherwise looks clean.
    $display("    apb_timeouts=%0d  RESP_SLVERR=%0d  RESP_DECERR=%0d",
             hub.stats.apb_timeouts, hub.stats.resp_slverr, hub.stats.resp_decerr);
    $display("    mailbox drops: axi=%0d apb=%0d scoreboard=%0d (total %0d)",
                      hub.evt_ovf[EVT_CH_AXI], hub.evt_ovf[EVT_CH_APB],
                      hub.evt_ovf[EVT_CH_SB],
                      hub.evt_ovf[EVT_CH_AXI] + hub.evt_ovf[EVT_CH_APB] +
                      hub.evt_ovf[EVT_CH_SB]);
    if (rep_fd != 0)
      $fdisplay(rep_fd, "    mailbox drops: axi=%0d apb=%0d scoreboard=%0d",
                hub.evt_ovf[EVT_CH_AXI], hub.evt_ovf[EVT_CH_APB],
                hub.evt_ovf[EVT_CH_SB]);
    if (rep_fd != 0) begin
      $fdisplay(rep_fd, "    lsu_reqs=%0d  axi_wrs=%0d  axi_rds=%0d  retired=%0d",
                hub.stats.lsu_reqs, hub.stats.axi_wrs, hub.stats.axi_rds, hub.stats.retired);
      $fdisplay(rep_fd, "    apb_timeouts=%0d  RESP_SLVERR=%0d  RESP_DECERR=%0d",
                hub.stats.apb_timeouts, hub.stats.resp_slverr, hub.stats.resp_decerr);
    end
  endtask

  //  The one page.  Emitted on first fatal, and again if blame moves down a
  //  layer, so the report on disk names the most fundamental cause seen so far
  //  rather than the first symptom.
  task automatic emit_one_page(input string hdr);
    step4_evt_t bf;
    string e_str, a_str;
    bf = EVT_ZERO;
    // Render the event the blame currently points at, NOT findings[0]. The old
    // code always used findings[0], so after a reassignment to a lower layer the
    // header named check N (via hub.blame_cid) while "expected:"/"actual:" still
    // described check 0 -- i.e. the report contradicted itself. Prefer the
    // recorded instance of blame_cid, and fall back to findings[0] only if that
    // event was not retained (findings[] is capped at MAX_FINDINGS).
    for (int unsigned i = 0; i < hub.n_find; i++) begin
      if (hub.findings[i].cid == hub.blame_cid &&
          hub.findings[i].layer == hub.blame_layer) begin
        bf = hub.findings[i];
        break;
      end
    end
    if (bf.cid == EVT_ZERO.cid && bf.layer == L_NONE && hub.n_find > 0)
      bf = hub.findings[0];
    render(bf, e_str, a_str);

    $display("\n%0s", RULE);
    $display("  RISCFORGE SoC   STEP 4 CHECKERS   --  %0s", hdr);
    $display("%0s", RULE);
    $display("  test            : %0s", hub.test_name);
    $display("  time / cycle    : %0t ps   /  %0d", $time, hub.cyc);
    $display("  VERDICT         : *** BLAME = %0s  (check %0s) ***",
             layer_name(hub.blame_layer), cid_id(hub.blame_cid));
    $display("  blame check     : %0s", cid_id(hub.blame_cid));
    $display("  location        : %0s", hub.blame_where);
    $display("  expected        : %0s", e_str);
    $display("  actual          : %0s", a_str);
    $display("  findings        : %0d recorded, %0d downstream (suppressed), %0d reassignments",
             hub.n_find, hub.n_down, hub.n_reas);
    $display("%0s", RULE);
    emit_layer_status();
    $display("%0s", RULE);
    emit_retire();
    $display("%0s", RULE);
    $display("  FROZEN WINDOWS -- captured at the fatal cycle, not overwritten since");
    $display("%0s", RULE);
    emit_ring("CORE LSU  (hybrid_mem_interface mem_*)", 0, hub.wp_lsu, hub.cnt_lsu);
    emit_ring("AXI4-LITE MASTER 2  (xbar slv[0])",     1, hub.wp_axi, hub.cnt_axi);
    emit_ring("APB BRIDGE  (axi_lite_to_apb)",         2, hub.wp_apb, hub.cnt_apb);
    $display("%0s", RULE);
    emit_counters();
    $display("%0s", RULE);
    $display("  NEXT: read the two lines above, in this order --");
    $display("    1. disassemble the newest retired instruction and check access");
    $display("       width, missing volatile, hidden reads and reordering");
    $display("    2. compare the frozen AXI and APB windows row by row");
    $display("    3. only then open waveforms");
    $display("%0s", RULE);

    if (rep_fd != 0) begin
      $fdisplay(rep_fd, "%0s", RULE);
      $fdisplay(rep_fd, "  test            : %0s", hub.test_name);
      $fdisplay(rep_fd, "  time / cycle    : %0t ps   /  %0d", $time, hub.cyc);
      $fdisplay(rep_fd, "  VERDICT         : *** BLAME = %0s  (check %0s) ***",
                layer_name(hub.blame_layer), cid_id(hub.blame_cid));
      $fdisplay(rep_fd, "  location        : %0s", hub.blame_where);
      $fdisplay(rep_fd, "  expected        : %0s", e_str);
      $fdisplay(rep_fd, "  actual          : %0s", a_str);
      $fdisplay(rep_fd, "  findings        : %0d recorded, %0d downstream, %0d reassign",
                hub.n_find, hub.n_down, hub.n_reas);
      $fdisplay(rep_fd, "%0s", RULE);
      emit_retire();
      $fdisplay(rep_fd, "%0s", RULE);
      emit_ring("CORE LSU", 0, hub.wp_lsu, hub.cnt_lsu);
      emit_ring("AXI4-LITE MASTER 2", 1, hub.wp_axi, hub.cnt_axi);
      emit_ring("APB BRIDGE", 2, hub.wp_apb, hub.cnt_apb);
      $fdisplay(rep_fd, "%0s", RULE);
      emit_counters();
      $fdisplay(rep_fd, "%0s", RULE);
    end
  endtask

  //  End-of-test verdict.  Implements the pass rule from Integration Guide
  //  section 3: the mailbox reports PASS (Step 5+, out of scope here), no checker
  //  failed, AND the checkers actually saw activity.  The last clause is the one
  //  that catches a checker suite wired to the wrong signals.
  task automatic final_verdict(input bit mailbox_pass = 1, input bit mailbox_known = 0);
    if (hub.n_find == 0) begin
      $display("\n%0s", RULE);
      $display("  STEP 4 CHECKER VERDICT : CLEAN");
      if ((hub.stats.lsu_reqs == 0) && (hub.stats.axi_wrs == 0) &&
          (hub.stats.axi_rds == 0)) begin
        $display("  *** VACUOUS PASS -- no MMIO traffic was observed. A checker");
        $display("      suite that never saw a transaction proves nothing. ***");
      end
      else begin
        $display("  evidence: %0d LSU, %0d AXI writes, %0d AXI reads, %0d APB transfers",
                 hub.stats.lsu_reqs, hub.stats.axi_wrs, hub.stats.axi_rds,
                 hub.stats.apb_xfers[0] + hub.stats.apb_xfers[1] +
                 hub.stats.apb_xfers[2] + hub.stats.apb_xfers[3] +
                 hub.stats.apb_xfers[4] + hub.stats.apb_xfers[5]);
      end
      if (!mailbox_known)
        $display("  note: mailbox result not supplied (Step 5+) -- partial verdict only");
      $display("%0s\n", RULE);
    end
    else begin
      $display("\n%0s", RULE);
      $display("  STEP 4 CHECKER VERDICT : FAILED");
      $display("  %0d findings, %0d reassignments, %0d downstream (suppressed)",
               hub.n_find, hub.n_reas, hub.n_down);
      $display("  blame: %0s   check %0s", layer_name(hub.blame_layer), cid_id(hub.blame_cid));
      $display("  full report: %0s", REPORT_FILE);
      $display("%0s\n", RULE);
    end

    if (rep_fd != 0) begin
      $fdisplay(rep_fd, "%0s", RULE);
      $fdisplay(rep_fd, "  STEP 4 CHECKER VERDICT : %0s   blame %0s  check %0s",
                (hub.n_find == 0) ? "CLEAN" : "FAILED",
                layer_name(hub.blame_layer), cid_id(hub.blame_cid));
      $fdisplay(rep_fd, "  %0d findings, %0d reassign, %0d downstream",
                hub.n_find, hub.n_reas, hub.n_down);
      $fclose(rep_fd);
      rep_fd = 0;
    end

    if (hub.fatal_seen && halt_on_fatal == 0 && USE_ISSUE != 0)
      $display("[STEP4] +step4_halt=1 would have stopped here.");
  endtask

endmodule : step4_reporter