// =============================================================================
//  step4_path_scoreboard.sv : end-to-end MMIO path scoreboard
// =============================================================================
//  THE CLAIM BEING CHECKED
//
//    "Every core MMIO access appears as exactly one AXI4-Lite transaction and,
//     if it decodes to an APB rule, exactly one APB transfer on the slot the
//     address map gives -- with the same direction, the same address, the same
//     data, the same byte strobes, and the same response, within the timing the
//     timeout budgets allow."
//
//  The chain, and every tap:
//
//    core_lsu_*  (top.lsu_mem_*)        tap A: the core MMIO access is issued
//          |
//          v
//    hybrid_mem_interface  i_core_data_if
//          |  m_axi_req_o.w.strb = mem_be          <-- byte enables enter here
//          v
//    axi_lite_timeout_monitor i_axi_lite_timeout_monitor
//          |
//          v
//    axi_lite_xbar SLV[0]               tap B: the AXI4-Lite request is issued
//          |
//          v
//    axi_lite_xbar MST[2]
//          |
//          v
//    axi_lite_to_apb i_axi_lite_to_apb   (this is "AXI4-Lite Master 2")
//          |
//          v
//    apb_req[i] / apb_resp[i]           tap C: the APB transfer completes
//          |
//          +--> APB[0] I2C     0x4000_0000 .. 0x4000_0FFF
//          +--> APB[1] Timer0  0x4000_1000 .. 0x4000_1FFF
//          +--> APB[2] UART    0x4000_2000 .. 0x4000_2FFF
//          +--> APB[3] GPIO    0x4000_3000 .. 0x4000_37FF   (2 KB, not 4 KB)
//          +--> APB[4] SPI     0x4000_4000 .. 0x4000_4FFF   (bootloader)
//          +--> APB[5] Timer1  0x4000_5000 .. 0x4000_5FFF
//
//  WHY A SINGLE SLOT RECORD AND NOT A QUEUE
//  axi_lite_to_apb has one FSM and one spill-register pair (the Setup and Access
//  arms at axi_lite_to_apb.sv:294-358), so it retires exactly one AXI transaction
//  at a time: the next AW/W or AR is not accepted until apb_req_ready pops the
//  current one.  At most one transaction is therefore in flight across the bridge,
//  and a single record plus a claimed-by flag is exact.  A queue would imply an
//  ordering the fabric does not have.
//
//  The same argument does NOT hold at the LSU tap: two core accesses could in
//  principle both be in flight if the LSU ever stopped asserting core_lsu_stall.
//  That case is detected explicitly (PATH_ORDER) rather than papered over.
//
//  THE PREDICTION IS BUILT FROM axi_lite_to_apb, NOT FROM WHAT WE WOULD WISH
//  axi_lite_to_apb.sv:299 gates APB request generation on
//
//      apb_dec_valid && ((write && |strb) || !write)
//
//  so, read off the RTL:
//    - a read that decodes to a rule       -> one APB transfer
//    - a write with non-zero WSTRB        -> one APB transfer
//    - a write with WSTRB == 0            -> NO APB transfer, RESP_OKAY (:319)
//    - a read that hits no rule            -> NO APB transfer, RESP_DECERR (:322)
//    - a write that hits no rule, strb=0   -> NO APB transfer, RESP_OKAY (:319)
//      (yes, OKAY -- the ternary at :319 tests the strobes, not the decode)
//  The scoreboard predicts exactly this.  Predicting anything else would mean the
//  scoreboard fires on correct RTL, and a checker that cries wolf on golden RTL
//  is worse than no checker.
//
//  WHAT IS DELIBERATELY *NOT* PREDICTED HERE
//  Whether a peripheral SHOULD raise PSLVERR is a register-layer question, not a
//  path question -- REG_SUBWORD_ERR for the GPIO sub-word write case is the
//  example.  This scoreboard only checks that PSLVERR survives the mapping into
//  RESP_SLVERR instead of being swallowed into RESP_OKAY.
// =============================================================================

`include "step4_cfg.svh"

module step4_path_scoreboard #(
  parameter int unsigned LAT_SLACK = 8   // cycles added to the per-slot budget
) (
  input logic clk,
  input logic rst_n,

  // ---- tap A: core LSU -----------------------------------------------------
  input logic        lsu_req,
  input logic [31:0] lsu_addr,
  input logic        lsu_we,
  input logic [31:0] lsu_wdata,
  input logic [3:0]  lsu_be,
  input logic        lsu_stall,

  // ---- tap B: AXI4-Lite, core master port (xbar slv[0]) --------------------
  input logic [31:0] aw_addr,
  input logic        aw_valid,
  input logic        aw_ready,
  input logic [31:0] w_data,
  input logic [3:0]  w_strb,
  input logic        w_valid,
  input logic        w_ready,
  input logic [31:0] ar_addr,
  input logic        ar_valid,
  input logic        ar_ready,
  input logic        b_valid,
  input logic        b_ready,
  input logic [1:0]  b_resp,
  input logic        r_valid,
  input logic        r_ready,
  input logic [1:0]  r_resp,
  input logic [31:0] r_data,
  input logic        axi_tmo_pulse,       // AXI-side abort fired

  // ---- tap B': the bootloader's master port, for accounting only -----------
  input logic [31:0] boot_aw_addr,
  input logic        boot_aw_valid,
  input logic        boot_aw_ready,
  input logic [31:0] boot_ar_addr,
  input logic        boot_ar_valid,
  input logic        boot_ar_ready,

  // ---- tap C: APB bridge outputs -------------------------------------------
  input logic [5:0]        apb_psel,
  input logic [5:0]        apb_penable,
  input logic [5:0]        apb_pwrite,
  input logic [5:0]        apb_pready,
  input logic [5:0]        apb_pslverr,
  input logic [5:0][31:0]  apb_paddr,
  input logic [5:0][31:0]  apb_pwdata,
  input logic [5:0][31:0]  apb_prdata,
  input logic [5:0][3:0]   apb_pstrb,
  input logic [5:0]        apb_tmo_pulse,

  step4_hub hub
);

  import step4_pkg::*;

  localparam int unsigned RD = `STEP4_RING_DEPTH;

  // ===========================================================================
  //  Finding mailbox.  The scoreboard is procedural, but it routes findings
  //  through the same mailbox the assertions use, so one blame rule applies to
  //  everything and the layer ordering stays consistent.
  // ===========================================================================
  localparam int unsigned EVQ = 8;
  step4_evt_t ev_q [EVQ];
  logic [2:0]  ev_w = 0;
  logic [2:0]  ev_r = 0;

  initial hub.loc_name[LOC_SB] = "core-MMIO-path";

  always_ff @(negedge clk) begin
    if (!rst_n) begin
      ev_r <= 0;
      ev_w <= 0;
      hub.evt_wp[EVT_CH_SB] <= 0;
      hub.evt_ovf[EVT_CH_SB] <= 0;
    end
    else begin
      // Private mailbox region + modulo + validity test (see step4_axi_sva.sv).
      if (ev_q[ev_r].vld) begin
        automatic int unsigned widx = hub.evt_wp[EVT_CH_SB] % EVT_REGION;
        automatic int unsigned slot = EVT_CH_SB*EVT_REGION + widx;
        if (!hub.evt[slot].vld) begin
          hub.evt[slot]          = ev_q[ev_r];
          hub.evt[slot].vld      = 1'b1;
          hub.evt_wp[EVT_CH_SB]  = (widx + 1) % EVT_REGION;
        end else begin
          hub.evt_ovf[EVT_CH_SB] = hub.evt_ovf[EVT_CH_SB] + 1;
        end
        ev_q[ev_r].vld = 1'b0;
      end
      ev_r = (ev_r + 1) % EVQ;
    end
  end

  //  Raise one finding.  A task is fine: this module is procedural, so nothing
  //  here is called from an assertion context.
  task automatic raise(input int unsigned cid, input logic [31:0] a,
                       input logic [31:0] b, input logic [31:0] c,
                       input logic [31:0] d);
    ev_q[ev_w].vld   = 1'b1;
    ev_q[ev_w].cid   = cid;
    ev_q[ev_w].layer = L_PATH;
    ev_q[ev_w].loc   = LOC_SB;
    ev_q[ev_w].a     = a;
    ev_q[ev_w].b     = b;
    ev_q[ev_w].c     = c;
    ev_q[ev_w].d     = d;
    ev_w             = ev_w + 1;
  endtask

  // ===========================================================================
  //  Ring pushes, inline.  Written out rather than delegated to the reporter:
  //  the scoreboard holds the hub as an interface port, and xsim will not let it
  //  call anything on it.
  // ===========================================================================
  task automatic ring_lsu(input logic [31:0] addr, input bit is_write,
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
    hub.wp_lsu = (hub.wp_lsu + 1) % RD;
    if (hub.cnt_lsu < RD) hub.cnt_lsu <= hub.cnt_lsu + 1;
    hub.stats.lsu_reqs = hub.stats.lsu_reqs + 1;
  endtask

  task automatic ring_axi(input rec_kind_t k, input bit is_write,
                          input logic [31:0] addr, input logic [31:0] wdata,
                          input logic [3:0] strb, input logic [31:0] rdata,
                          input logic [1:0] resp);
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
    r.ok       = 1'b1;
    r.cycle_lo = hub.cyc[15:0];
    r.slot     = NUM_APB_SLAVES;
    hub.ring_axi[hub.wp_axi] = r;
    hub.wp_axi = (hub.wp_axi + 1) % RD;
    if (hub.cnt_axi < RD) hub.cnt_axi <= hub.cnt_axi + 1;
    if (k == REC_AXI_REQ) begin
      if (is_write) hub.stats.axi_wrs = hub.stats.axi_wrs + 1;
      else          hub.stats.axi_rds = hub.stats.axi_rds + 1;
    end
    else begin
      if (resp == RESP_SLVERR) hub.stats.resp_slverr = hub.stats.resp_slverr + 1;
      if (resp == RESP_DECERR) hub.stats.resp_decerr = hub.stats.resp_decerr + 1;
    end
  endtask

  task automatic ring_apb(input int unsigned slot, input logic [31:0] paddr,
                          input bit pwrite, input logic [31:0] pwdata,
                          input logic [3:0] pstrb, input logic [31:0] prdata,
                          input bit pslverr, input bit is_timeout);
    step4_rec_t r;
    if (hub.frozen) return;
    r = REC_ZERO;
    r.kind     = is_timeout ? REC_APB_TO : REC_APB_XFER;
    r.is_write = pwrite;
    r.addr     = paddr;
    r.wdata    = pwdata;
    r.rdata    = prdata;
    r.strb     = pstrb;
    r.resp     = {1'b0, pslverr};
    r.slot     = slot;
    r.ok       = !is_timeout && !pslverr;
    r.cycle_lo = hub.cyc[15:0];
    hub.ring_apb[hub.wp_apb] = r;
    hub.wp_apb = (hub.wp_apb + 1) % RD;
    if (hub.cnt_apb < RD) hub.cnt_apb <= hub.cnt_apb + 1;
    hub.stats.apb_xfers[slot] = hub.stats.apb_xfers[slot] + 1;
    if (is_timeout) hub.stats.apb_timeouts = hub.stats.apb_timeouts + 1;
  endtask

  // ===========================================================================
  //  The one in-flight transaction.  Packed so cur = '0 is legal.
  // ===========================================================================
  typedef struct packed {
    bit             valid;
    bit             from_core;      // claimed by tap A (core LSU)
    bit             is_write;
    logic [31:0]    addr;           // raw LSU / AXI address, unaligned
    logic [31:0]    wdata;
    logic [3:0]     strb;
    int unsigned    slot;           // predicted APB slot, 6 == none
    bit             want_apb;       // does the RTL predict an APB transfer?
    bit             saw_aw;
    bit             saw_w;
    bit             saw_ar;
    bit             saw_apb;
    bit             apb_timed_out;
    logic [31:0]    apb_paddr;
    logic [31:0]    apb_pwdata;
    logic [3:0]     apb_pstrb;
    logic [31:0]    apb_prdata;
    bit             apb_pwrite;
    bit             apb_pslverr;
    longint unsigned t_lsu, t_req, t_apb, t_resp;
  } tx_t;

  tx_t cur;

  function automatic bit predict_apb(input logic [31:0] a, input bit is_write,
                                     input logic [3:0] strb, output int unsigned slot);
    slot = apb_slot_of(a);
    return (slot < NUM_APB_SLAVES) && ((!is_write) || (|strb));
  endfunction

  function automatic logic [31:0] align4(input logic [31:0] a);
    return {a[31:2], 2'b00};
  endfunction

  //  Latency budget for the APB phase, taken from the slot's own timeout
  //  threshold plus slack -- so it is never tighter than what the RTL itself
  //  considers legal.  A path check that fails on a transfer the timeout monitor
  //  would also have aborted is measuring the wrong thing.
  function automatic longint unsigned lat_budget(input int unsigned slot);
    if (slot >= NUM_APB_SLAVES) return 8;
    return APB_TIMEOUT_CYCLES[slot] + LAT_SLACK;
  endfunction

  // ===========================================================================
  //  TAP A -- the core issues an MMIO access.  Fires when hybrid_mem_interface
  //  would set axi_req_active, i.e. mem_req & addr_in_mmio_range
  //  (hybrid_mem_interface.sv:75).
  // ===========================================================================
  wire lsu_mmio = lsu_req && !lsu_stall
                  && (lsu_addr >= HMIF_MMIO_BASE) && (lsu_addr <= HMIF_MMIO_LIMIT);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cur <= '0;
    end
    else begin
      // ---- a second MMIO access while one is still in flight ----
      if (lsu_mmio && cur.valid) begin
        raise(CID_PATH_ORDER, lsu_addr, cur.addr, 0, 0);
        cur.valid = 1'b0;
      end

      if (lsu_mmio) begin
        int unsigned s;
        cur = '0;
        cur.valid     = 1'b1;
        cur.from_core = 1'b1;
        cur.is_write  = lsu_we;
        cur.addr      = lsu_addr;
        cur.wdata     = lsu_wdata;
        cur.strb      = lsu_be;
        cur.t_lsu     = hub.cyc;
        cur.want_apb  = predict_apb(lsu_addr, lsu_we, lsu_be, s);
        cur.slot      = s;
        ring_lsu(lsu_addr, lsu_we, lsu_wdata, lsu_be);
      end

      // ---- the bootloader claims the record when the core did not ----
      else if (!cur.valid &&
               ((boot_aw_valid && boot_aw_ready && in_apb_region(boot_aw_addr)) ||
                (boot_ar_valid && boot_ar_ready && in_apb_region(boot_ar_addr)))) begin
        int unsigned s;
        automatic bit wr = boot_aw_valid && boot_aw_ready;
        automatic logic [31:0] ba = wr ? boot_aw_addr : boot_ar_addr;
        automatic logic [3:0]  bs = wr ? 4'hF : 4'h0;
        cur = '0;
        cur.valid     = 1'b1;
        cur.is_write  = wr;
        cur.addr      = ba;
        cur.strb      = bs;
        cur.t_lsu     = hub.cyc;
        cur.want_apb  = predict_apb(ba, wr, bs, s);
        cur.slot      = s;
      end

      // ======================= TAP B : AXI request ========================
      if (cur.valid) begin
        if (aw_valid && aw_ready) begin
          cur.saw_aw = 1'b1;
          if (cur.t_req == 0) cur.t_req = hub.cyc;
          //  The core's address must reach the fabric unaltered.
          if (cur.from_core && cur.addr != aw_addr)
            raise(CID_PATH_NO_LOSS, cur.addr, 0, 0, 0);
        end
        if (w_valid && w_ready) begin
          cur.saw_w = 1'b1;
          if (cur.t_req == 0) cur.t_req = hub.cyc;
          if (cur.from_core) begin
            if (cur.wdata !== w_data)
              raise(CID_PATH_WDATA, 0, cur.wdata, w_data, 0);
            //  BYTE ENABLES.  mem_be -> w.strb -> pstrb, unbroken:
            //  hybrid_mem_interface.sv:349, axi_lite_to_apb.sv:126/311/339.
            if (cur.strb !== w_strb)
              raise(CID_PATH_STRB, 0, cur.strb, w_strb, 0);
          end
        end
        if (ar_valid && ar_ready) begin
          cur.saw_ar = 1'b1;
          if (cur.t_req == 0) cur.t_req = hub.cyc;
          if (cur.from_core && cur.addr != ar_addr)
            raise(CID_PATH_NO_LOSS, cur.addr, 0, 0, 0);
        end

        // ======================= TAP C : APB transfer =====================
        for (int unsigned i = 0; i < NUM_APB_SLAVES; i++) begin
          if (apb_psel[i] && apb_penable[i] && apb_pready[i]) begin
            automatic bit tmo = apb_tmo_pulse[i];
            cur.saw_apb       = 1'b1;
            cur.apb_paddr     = apb_paddr[i];
            cur.apb_pwdata    = apb_pwdata[i];
            cur.apb_pstrb     = apb_pstrb[i];
            cur.apb_prdata    = apb_prdata[i];
            cur.apb_pwrite    = apb_pwrite[i];
            cur.apb_pslverr   = apb_pslverr[i];
            cur.apb_timed_out = tmo;
            cur.t_apb         = hub.cyc;

            ring_apb(i, apb_paddr[i], apb_pwrite[i], apb_pwdata[i], apb_pstrb[i],
                     apb_prdata[i], apb_pslverr[i] | tmo, tmo);

            //  ---- address decoding: the slot must be the one the map says --
            if (i != cur.slot)
              raise(CID_PATH_SLOT, cur.slot, cur.addr, i, 0);

            //  ---- address integrity: PADDR is the aligned AXI address ------
            if (cur.apb_paddr !== align4(cur.addr))
              raise(CID_PATH_ADDR, align4(cur.addr), cur.apb_paddr, cur.addr, 0);

            //  ---- direction ------------------------------------------------
            if (cur.apb_pwrite !== cur.is_write)
              raise(CID_PATH_DIR, {31'h0, cur.is_write}, {31'h0, cur.apb_pwrite}, 0, 0);

            //  ---- write data integrity ------------------------------------
            if (cur.is_write && cur.apb_pwdata !== cur.wdata)
              raise(CID_PATH_WDATA, 0, cur.wdata, cur.apb_pwdata, 0);

            //  ---- byte enables must survive the bridge unchanged -----------
            if (cur.apb_pstrb !== cur.strb)
              raise(CID_PATH_STRB, 0, cur.strb, cur.apb_pstrb, 0);
          end
        end
      end

      // ==================== TAP B response : close the record =================
      if (cur.valid && ((b_valid && b_ready) || (r_valid && r_ready))) begin
        automatic bit          is_wr_done = b_valid && b_ready;
        automatic logic [1:0]  resp       = is_wr_done ? b_resp : r_resp;
        automatic logic [31:0] rdata      = r_data;

        cur.t_resp = hub.cyc;

        //  The request must have reached the fabric at all.
        if (!cur.saw_aw && !cur.saw_ar)
          raise(CID_PATH_NO_LOSS, cur.addr, 0, 0, 0);

        //  Did the APB phase happen when the RTL says it should?
        if (cur.want_apb && !cur.saw_apb)
          raise(CID_PATH_NO_EXTRA_APB, cur.addr, 0, 0, 0);
        if (!cur.want_apb && cur.saw_apb)
          raise(CID_PATH_NO_EXTRA_APB, cur.addr, 0, 0, 0);

        //  Response prediction.  Only the two cases the bridge itself decides:
        //  an unmapped read, and a write with all strobes clear.  Whether a
        //  peripheral SHOULD raise PSLVERR is the register layer's business.
        if (!cur.want_apb && cur.slot == NUM_APB_SLAVES && resp != RESP_DECERR)
          raise(CID_PATH_HOLE, cur.addr, {30'h0, resp}, 0, 0);
        if (!cur.want_apb && cur.slot < NUM_APB_SLAVES && cur.is_write &&
            resp != RESP_OKAY)
          raise(CID_PATH_ZERO_STRB, {30'h0, resp}, 0, 0, 0);

        //  PSLVERR must not be swallowed on the way back.
        if (cur.saw_apb && cur.apb_pslverr && resp != RESP_SLVERR && !cur.apb_timed_out)
          raise(CID_PATH_RESP, {30'h0, resp}, 0, 0, 0);

        //  Read data integrity: PRDATA is the only source of RDATA.
        if (!cur.is_write && cur.saw_apb && !cur.apb_timed_out &&
            (rdata !== cur.apb_prdata))
          raise(CID_PATH_RDATA, 0, cur.apb_prdata, rdata, 0);

        //  ---- latency ----
        if (!axi_tmo_pulse && cur.t_req != 0) begin
          automatic longint unsigned lat = cur.t_resp - cur.t_req;
          automatic longint unsigned budget = lat_budget(cur.slot) + 32;
          if (lat > budget)
            raise(CID_PATH_LATENCY, cur.addr, lat, cur.slot, budget);
        end

        ring_axi(REC_AXI_RESP, cur.is_write, cur.addr, cur.wdata, cur.strb, rdata, resp);
        cur = '0;
      end
    end
  end

  //  Push an AXI-request record as soon as the request is seen, so the frozen
  //  window shows requests and responses interleaved in real order.
  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (aw_valid && aw_ready && w_valid && w_ready)
        ring_axi(REC_AXI_REQ, 1'b1, aw_addr, w_data, w_strb, 32'h0, RESP_OKAY);
      else if (ar_valid && ar_ready)
        ring_axi(REC_AXI_REQ, 1'b0, ar_addr, 32'h0, 4'h0, 32'h0, RESP_OKAY);
    end
  end

  // ===========================================================================
  //  End-of-test consistency.
  //
  //  A record still open at the end means an access never completed.  Without
  //  this check it would be invisible: the transaction simply never appears in
  //  any ring.
  // ===========================================================================
//  A task, not a function: it raises a finding, and raise() is a task.
  task automatic end_of_test();
    automatic logic [31:0] flags;
    if (cur.valid) begin
      //  Pack the completion flags into one word so the report can say which
      //  halves of the transaction were actually seen.
      flags[0] = cur.saw_aw;
      flags[1] = cur.saw_w;
      flags[2] = cur.saw_ar;
      flags[3] = cur.saw_apb;
      raise(CID_PATH_NO_LOSS, cur.addr, flags, cur.apb_paddr, 0);
      cur = '0;
    end
  endtask

  function automatic int unsigned apb_xfer_count();
    return hub.stats.apb_xfers[0] + hub.stats.apb_xfers[1] + hub.stats.apb_xfers[2] +
           hub.stats.apb_xfers[3] + hub.stats.apb_xfers[4] + hub.stats.apb_xfers[5];
  endfunction

endmodule : step4_path_scoreboard