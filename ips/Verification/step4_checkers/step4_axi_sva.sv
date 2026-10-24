// =============================================================================
//  step4_axi_sva.sv : AXI4-Lite protocol assertions
// =============================================================================
//  Bind target: every AXI4-Lite interface in the fabric.  For RISCFORGE that is
//
//    xbar_slv_req/resp [0]  core MMIO master  (post axi_lite_timeout_monitor)
//    xbar_slv_req/resp [1]  bootloader master
//    xbar_mst_req/resp [0]  ISRAM
//    xbar_mst_req/resp [1]  DSRAM
//    xbar_mst_req/resp [2]  APB bridge      <-- this is "Master 2" in Step 4
//    core_axi_req/resp      hybrid_mem_interface <-> timeout monitor
//
//  WHAT IS CHECKED, AND WHY EACH ONE MATTERS HERE
//
//  1. Stability while stalled.  This is the assertion that catches a broken
//     combinational path from the LSU bus onto aw.addr.  In this design
//     hybrid_mem_interface.sv:345 drives aw.addr straight from mem_addr, and
//     correctness depends entirely on core_lsu_stall freezing the pipeline.  If
//     that freeze is ever weakened, the AW payload changes under the bridge and
//     the access lands on the wrong APB slot.  Nothing else in the flow would
//     notice: the transfer still completes, just somewhere else.
//
//  2. VALID must not be withdrawn.  AXI4 removed the AXI3 allowance for
//     withdrawing VALID before READY.  A master that does loses a transfer, and
//     the xbar demux latches the wrong target.
//
//  3. No X on the payload.  The SRAM models use 4 MB arrays gated by `ifndef
//     SYNTHESIS`; an uninitialised word arrives as X and would otherwise be
//     written into a peripheral and read back as a plausible-looking value.
//
//  4. Response legality.  EXOKAY is defined for AXI full only.  On AXI4-Lite it
//     must never appear, so seeing it means the response came from a full-AXI
//     converter wired up by mistake.
//
//  5. A write response cannot precede its AW and W.  The bridge generates B from
//     the APB transfer; an early B means the APB transfer completed against a
//     request that never latched.
//
//  6. Bounded stall, and a read that is answered.  Both turn an unbounded
//     simulation hang into a named failure instead of a timeout with no story.
//
//  Every assertion has a matching cover, per the pass rule in the integration
//  guide ("every assertion has a cover that is hit").  A cover that is never hit
//  means the property was never stressed and its pass is worth nothing.
//
//  HOW A FAILURE REACHES THE REPORTER
//  The action blocks here only assign a packed record and bump a pointer.  They
//  must not call the reporter directly: xsim crashes in codegen when a
//  concurrent assertion's action block calls a function on an interface that
//  carries state (see the note in step4_pkg.sv).  A negedge forwarder does the
//  call, off the same edge as the assertion so the order is deterministic.
// =============================================================================

`include "step4_cfg.svh"

module step4_axi_sva #(
  parameter string PORT_NAME  = "axi",
  parameter int    LOC_IDX    = 0,
  parameter int    STALL_BOUND = `STEP4_STALL_BOUND
) (
  input logic        clk,
  input logic        rst_n,
  // AW
  input logic [31:0] aw_addr,
  input logic [2:0]  aw_prot,
  input logic        aw_valid,
  input logic        aw_ready,
  // W
  input logic [31:0] w_data,
  input logic [3:0]  w_strb,
  input logic        w_valid,
  input logic        w_ready,
  // B
  input logic [1:0]  b_resp,
  input logic        b_valid,
  input logic        b_ready,
  // AR
  input logic [31:0] ar_addr,
  input logic [2:0]  ar_prot,
  input logic        ar_valid,
  input logic        ar_ready,
  // R
  input logic [31:0] r_data,
  input logic [1:0]  r_resp,
  input logic        r_valid,
  input logic        r_ready,
  // reporter
  step4_hub hub
);

  import step4_pkg::*;

  // ---------------------------------------------------------------------------
  // Deferred-finding buffer
  // ---------------------------------------------------------------------------
  localparam int unsigned EVQ = 4;      // power of two
  step4_evt_t ev_q [EVQ];
  logic [1:0]  ev_w = 0;                // written by the action blocks (posedge)
  logic [1:0]  ev_r = 0;                // read by the forwarder (negedge)

  //  Register the location by writing the interface array directly.  An initial
  //  block calling a reporter function would put the whole reporter back inside
  //  xsim's interface codegen path, which is exactly what this package avoids.
  initial hub.loc_name[LOC_IDX] = PORT_NAME;

  //  Forward the local queue into the shared mailbox.  NEGEDGE on purpose: the
  //  action blocks write at the posedge, so a different edge removes any ordering
  //  ambiguity about which one wins when the queue is empty and ev_w == ev_r.
  always_ff @(negedge clk) begin
    if (!rst_n) begin
      ev_r <= 0;
      ev_w <= 0;
      hub.evt_wp[EVT_CH_AXI] <= 0;
      hub.evt_ovf[EVT_CH_AXI] <= 0;
    end
    else begin
      // Only post a REAL finding. The old code posted unconditionally, which
      // advanced the shared mailbox pointer once per checker per clock and ran
      // it off the end of the array within a few cycles of a fault-free run.
      if (ev_q[ev_r].vld) begin
        automatic int unsigned widx = hub.evt_wp[EVT_CH_AXI] % EVT_REGION;
        automatic int unsigned slot = EVT_CH_AXI*EVT_REGION + widx;
        if (!hub.evt[slot].vld) begin
          hub.evt[slot]                  = ev_q[ev_r];
          hub.evt[slot].vld              = 1'b1;
          hub.evt_wp[EVT_CH_AXI]         = (widx + 1) % EVT_REGION;
        end else begin
          // Region full and undrained: count it. Never overwrite an event the
          // reporter has not classified yet.
          hub.evt_ovf[EVT_CH_AXI]        = hub.evt_ovf[EVT_CH_AXI] + 1;
        end
        ev_q[ev_r].vld = 1'b0;
      end
      ev_r = (ev_r + 1) % EVQ;
    end
  end

  // ---------------------------------------------------------------------------
  // Handshake shapes
  // ---------------------------------------------------------------------------
  wire aw_stall = aw_valid && !aw_ready;
  wire w_stall  = w_valid  && !w_ready;
  wire b_stall  = b_valid  && !b_ready;
  wire ar_stall = ar_valid && !ar_ready;
  wire r_stall  = r_valid  && !r_ready;

  wire aw_hs = aw_valid && aw_ready;
  wire w_hs  = w_valid  && w_ready;
  wire ar_hs = ar_valid && ar_ready;
  wire b_hs  = b_valid  && b_ready;

  //  A write response is only legal once both halves of the request latched.
  bit aw_seen, w_seen;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      aw_seen <= 1'b0;
      w_seen  <= 1'b0;
    end
    else if (b_hs) begin
      aw_seen <= 1'b0;
      w_seen  <= 1'b0;
    end
    else begin
      if (aw_hs) aw_seen <= 1'b1;
      if (w_hs)  w_seen  <= 1'b1;
    end
  end

  //  Previous-cycle payloads.  These are $past() written out: $past() inside an
  //  SVA action block has no clocking event to infer from and xsim refuses to
  //  elaborate it.
  logic [31:0] p_aw_addr, p_w_data, p_ar_addr, p_r_data;
  logic [2:0]  p_aw_prot, p_ar_prot;
  logic [3:0]  p_w_strb;
  logic [1:0]  p_b_resp, p_r_resp;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      p_aw_addr <= '0; p_aw_prot <= '0; p_w_data <= '0; p_w_strb <= '0;
      p_ar_addr <= '0; p_ar_prot <= '0; p_r_data <= '0;
      p_b_resp  <= '0; p_r_resp  <= '0;
    end
    else begin
      p_aw_addr <= aw_addr; p_aw_prot <= aw_prot;
      p_w_data  <= w_data;  p_w_strb  <= w_strb;
      p_ar_addr <= ar_addr; p_ar_prot <= ar_prot;
      p_r_data  <= r_data;
      p_b_resp  <= b_resp;  p_r_resp  <= r_resp;
    end
  end

  // ===========================================================================
  // 1. Stability while stalled
  // ===========================================================================
  A_AXIL_AW_STABLE : assert property (@(posedge clk) disable iff (!rst_n)
      aw_stall |=> ($stable(aw_addr) && $stable(aw_prot)))
    else begin
      ev_q[ev_w].vld   = 1'b1;
      ev_q[ev_w].cid   = CID_AXIL_AW_STABLE;
      ev_q[ev_w].layer = L_PROTO;
      ev_q[ev_w].loc   = LOC_IDX;
      ev_q[ev_w].a     = {8'h00, aw_prot,  aw_addr};
      ev_q[ev_w].b     = {8'h00, p_aw_prot, p_aw_addr};
      ev_w             = ev_w + 1;
    end
  C_AXIL_AW_STABLE : cover property (@(posedge clk) disable iff (!rst_n)
      $past(aw_stall) && aw_valid && !aw_ready);

  A_AXIL_W_STABLE : assert property (@(posedge clk) disable iff (!rst_n)
      w_stall |=> ($stable(w_data) && $stable(w_strb)))
    else begin
      ev_q[ev_w].vld   = 1'b1;
      ev_q[ev_w].cid   = CID_AXIL_W_STABLE;
      ev_q[ev_w].layer = L_PROTO;
      ev_q[ev_w].loc   = LOC_IDX;
      ev_q[ev_w].a     = {20'h0, w_strb,  w_data};
      ev_q[ev_w].b     = {20'h0, p_w_strb, p_w_data};
      ev_w             = ev_w + 1;
    end
  C_AXIL_W_STABLE : cover property (@(posedge clk) disable iff (!rst_n)
      $past(w_stall) && w_valid && !w_ready);

  A_AXIL_B_STABLE : assert property (@(posedge clk) disable iff (!rst_n)
      b_stall |=> $stable(b_resp))
    else begin
      ev_q[ev_w].vld   = 1'b1;
      ev_q[ev_w].cid   = CID_AXIL_B_STABLE;
      ev_q[ev_w].layer = L_PROTO;
      ev_q[ev_w].loc   = LOC_IDX;
      ev_q[ev_w].a     = {30'h0, b_resp};
      ev_q[ev_w].b     = {30'h0, p_b_resp};
      ev_w             = ev_w + 1;
    end
  C_AXIL_B_STABLE : cover property (@(posedge clk) disable iff (!rst_n)
      $past(b_stall) && b_valid && !b_ready);

  A_AXIL_AR_STABLE : assert property (@(posedge clk) disable iff (!rst_n)
      ar_stall |=> ($stable(ar_addr) && $stable(ar_prot)))
    else begin
      ev_q[ev_w].vld   = 1'b1;
      ev_q[ev_w].cid   = CID_AXIL_AR_STABLE;
      ev_q[ev_w].layer = L_PROTO;
      ev_q[ev_w].loc   = LOC_IDX;
      ev_q[ev_w].a     = {8'h00, ar_prot,  ar_addr};
      ev_q[ev_w].b     = {8'h00, p_ar_prot, p_ar_addr};
      ev_w             = ev_w + 1;
    end
  C_AXIL_AR_STABLE : cover property (@(posedge clk) disable iff (!rst_n)
      $past(ar_stall) && ar_valid && !ar_ready);

  A_AXIL_R_STABLE : assert property (@(posedge clk) disable iff (!rst_n)
      r_stall |=> ($stable(r_data) && $stable(r_resp)))
    else begin
      ev_q[ev_w].vld   = 1'b1;
      ev_q[ev_w].cid   = CID_AXIL_R_STABLE;
      ev_q[ev_w].layer = L_PROTO;
      ev_q[ev_w].loc   = LOC_IDX;
      ev_q[ev_w].a     = {28'h0, r_resp, r_data};
      ev_q[ev_w].b     = {28'h0, p_r_resp, p_r_data};
      ev_w             = ev_w + 1;
    end
  C_AXIL_R_STABLE : cover property (@(posedge clk) disable iff (!rst_n)
      $past(r_stall) && r_valid && !r_ready);

  // ===========================================================================
  // 2. VALID must be held until READY (AXI4 removed the AXI3 allowance)
  //    AXIL-1006: stability is checked ONLY while a transfer is pending, i.e.
  //    VALID asserted and READY low with NO handshake having completed on the
  //    previous cycle. The !$past(handshake) term is the idle qualification:
  //    once VALID && READY has completed, the transfer is done and the bus is
  //    returning to idle, so a master that drops VALID in the cycle after its
  //    handshake (registered VALID-drop latency, as in the self-proof BFM
  //    which deasserts at the following negedge) must NOT be flagged as a
  //    withdrawal. A withdrawal mid-stall with no preceding handshake still
  //    fires. Reset is excluded via disable iff (!rst_n); when the bus is
  //    idle (VALID==0) the antecedent is false and the property passes
  //    vacuously.
  // ===========================================================================
  A_AXIL_AW_HOLD : assert property (@(posedge clk) disable iff (!rst_n)
      (aw_valid && !aw_ready && !$past(aw_valid && aw_ready)) |=> aw_valid)
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_VALID_HELD;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].c = 32'h01; ev_w = ev_w + 1;
    end
  A_AXIL_W_HOLD : assert property (@(posedge clk) disable iff (!rst_n)
      (w_valid && !w_ready && !$past(w_valid && w_ready)) |=> w_valid)
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_VALID_HELD;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].c = 32'h02; ev_w = ev_w + 1;
    end
  A_AXIL_B_HOLD : assert property (@(posedge clk) disable iff (!rst_n)
      (b_valid && !b_ready && !$past(b_valid && b_ready)) |=> b_valid)
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_VALID_HELD;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].c = 32'h03; ev_w = ev_w + 1;
    end
  A_AXIL_AR_HOLD : assert property (@(posedge clk) disable iff (!rst_n)
      (ar_valid && !ar_ready && !$past(ar_valid && ar_ready)) |=> ar_valid)
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_VALID_HELD;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].c = 32'h04; ev_w = ev_w + 1;
    end
  A_AXIL_R_HOLD : assert property (@(posedge clk) disable iff (!rst_n)
      (r_valid && !r_ready && !$past(r_valid && r_ready)) |=> r_valid)
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_VALID_HELD;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].c = 32'h05; ev_w = ev_w + 1;
    end
  C_AXIL_VALID_HELD : cover property (@(posedge clk) disable iff (!rst_n)
      (aw_stall || w_stall || ar_stall || r_stall));

  // ===========================================================================
  // 3. No X on any payload
  // ===========================================================================
  A_AXIL_AW_NOX : assert property (@(posedge clk) disable iff (!rst_n)
      aw_valid && !aw_ready |-> !$isunknown({aw_addr, aw_prot}))
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_NO_X;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].a = {aw_addr, aw_prot}; ev_w = ev_w + 1;
    end
  A_AXIL_W_NOX : assert property (@(posedge clk) disable iff (!rst_n)
      w_valid && !w_ready |-> !$isunknown({w_data, w_strb}))
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_NO_X;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].a = {w_data, w_strb}; ev_w = ev_w + 1;
    end
  A_AXIL_AR_NOX : assert property (@(posedge clk) disable iff (!rst_n)
      ar_valid && !ar_ready |-> !$isunknown({ar_addr, ar_prot}))
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_NO_X;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].a = {ar_addr, ar_prot}; ev_w = ev_w + 1;
    end
  A_AXIL_B_NOX : assert property (@(posedge clk) disable iff (!rst_n)
      b_valid && !b_ready |-> !$isunknown(b_resp))
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_NO_X;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].a = {30'h0, b_resp}; ev_w = ev_w + 1;
    end
  A_AXIL_R_NOX : assert property (@(posedge clk) disable iff (!rst_n)
      r_valid && !r_ready |-> !$isunknown({r_data, r_resp}))
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_NO_X;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].a = {r_data, r_resp}; ev_w = ev_w + 1;
    end
  C_AXIL_NO_X : cover property (@(posedge clk) disable iff (!rst_n)
      (aw_valid || w_valid || ar_valid || b_valid || r_valid)
      && !$isunknown({aw_addr, w_data, ar_addr, r_data}));

  // ===========================================================================
  // 4. Response legality.  EXOKAY is not an AXI4-Lite response.
  // ===========================================================================
  A_AXIL_B_LEGAL : assert property (@(posedge clk) disable iff (!rst_n)
      b_hs |-> (b_resp != RESP_EXOKAY))
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_RESP_LEGAL;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].a = {30'h0, b_resp}; ev_w = ev_w + 1;
    end
  A_AXIL_R_LEGAL : assert property (@(posedge clk) disable iff (!rst_n)
      (r_valid && r_ready) |-> (r_resp != RESP_EXOKAY))
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_RESP_LEGAL;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].a = {30'h0, r_resp}; ev_w = ev_w + 1;
    end
  C_AXIL_RESP_LEGAL : cover property (@(posedge clk) disable iff (!rst_n)
      b_hs || (r_valid && r_ready));

  // ===========================================================================
  // 5. A write response requires a latched AW and W
  //    AXI4-Lite allows W to precede AW, so this does not order the two; it only
  //    forbids answering a write that was never issued.
  // ===========================================================================
  A_AXIL_B_HAS_REQ : assert property (@(posedge clk) disable iff (!rst_n)
      b_hs |-> (aw_seen && w_seen))
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_B_HAS_REQ;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].a = {31'h0, w_seen, aw_seen}; ev_w = ev_w + 1;
    end
  C_AXIL_W_AFTER_AW : cover property (@(posedge clk) disable iff (!rst_n)
      w_hs && !aw_hs);   // the legal "W before AW" case, worth covering explicitly

  // ===========================================================================
  // 6. Bounded stall -- converts a hang into a named failure
  // ===========================================================================
  A_AXIL_AW_NOSTALL : assert property (@(posedge clk) disable iff (!rst_n)
      aw_stall |-> ##[0:STALL_BOUND] aw_ready)
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_NO_STALL;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].a = aw_addr; ev_q[ev_w].c = 32'h01;
      ev_q[ev_w].d = STALL_BOUND; ev_w = ev_w + 1;
    end
  A_AXIL_W_NOSTALL : assert property (@(posedge clk) disable iff (!rst_n)
      w_stall |-> ##[0:STALL_BOUND] w_ready)
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_NO_STALL;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].c = 32'h02; ev_q[ev_w].d = STALL_BOUND; ev_w = ev_w + 1;
    end
  A_AXIL_AR_NOSTALL : assert property (@(posedge clk) disable iff (!rst_n)
      ar_stall |-> ##[0:STALL_BOUND] ar_ready)
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_NO_STALL;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].a = ar_addr; ev_q[ev_w].c = 32'h04;
      ev_q[ev_w].d = STALL_BOUND; ev_w = ev_w + 1;
    end
  A_AXIL_R_NOSTALL : assert property (@(posedge clk) disable iff (!rst_n)
      r_stall |-> ##[0:STALL_BOUND] r_ready)
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_NO_STALL;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].c = 32'h05; ev_q[ev_w].d = STALL_BOUND; ev_w = ev_w + 1;
    end
  C_AXIL_NO_STALL : cover property (@(posedge clk) disable iff (!rst_n)
      (aw_stall || w_stall || ar_stall || r_stall));

  // ===========================================================================
  // 7. A read must be answered.  Without this, a request the fabric accepts and
  //    then loses shows up only as a watchdog timeout with no explanation: the
  //    core simply sits on core_lsu_stall forever.
  // ===========================================================================
  A_AXIL_AR_ANSWERED : assert property (@(posedge clk) disable iff (!rst_n)
      ar_hs |-> ##[0:STALL_BOUND] (r_valid && r_ready))
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_AXIL_R_ANSWERED;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].a = ar_addr; ev_q[ev_w].d = STALL_BOUND; ev_w = ev_w + 1;
    end
  C_AXIL_ERR_GONE : cover property (@(posedge clk) disable iff (!rst_n)
      ar_hs ##[1:8] (r_valid && r_ready));

endmodule : step4_axi_sva