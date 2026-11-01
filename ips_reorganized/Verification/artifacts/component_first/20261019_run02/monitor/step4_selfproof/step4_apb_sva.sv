// =============================================================================
//  step4_apb_sva.sv : APB4 protocol compliance, all six slots in one instance
// =============================================================================
//  Bound once to riscforge_soc_subsystem over the bridge outputs apb_req[0..5] /
//  apb_resp[0..5], i.e. the post-timeout-monitor view the bridge itself sees.
//
//  ONE instance covers all six slots on purpose.  The interesting APB property
//  here is fabric-wide, not per-peripheral: exactly one PSEL may be asserted at
//  a time.  If the bridge ever drives two slots at once -- which is exactly what
//  a mis-written apb_addr_map rule would do, since the GPIO rule is 2 KB while
//  its neighbours are 4 KB -- two peripherals both commit the same access and
//  neither is individually wrong.  A per-slot checker cannot see that.
//
//  APB4 RULES CHECKED (ARM AMBA APB protocol specification, APB4 revision)
//
//   A1  PENABLE implies PSEL.              APB4 removed the APB2 allowance for
//                                            PENABLE to be high while PSEL is low.
//   A2  A transfer may not sit in setup: it advances to access or the master
//       withdraws PSEL.
//   A3  PADDR, PWRITE, PWDATA and PSTRB are stable for the whole transfer --
//       every cycle of setup, the first cycle of access, and every later wait
//       state.  This is the property that catches a combinational leak from the
//       AXI W channel onto the APB bus: axi_lite_to_apb.sv:302-312 and :330-340
//       rebuild the whole struct in both phases from apb_req_q, so any bug in
//       that register appears here as an APB stability violation.
//   A4  PREADY and PSLVERR are only meaningful in the access phase.
//   A5  PRDATA is only meaningful for a completed read.  A slave driving PRDATA
//       in setup, or on a write, is what makes a read-modify-write in firmware
//       see stale data.
//   A6  PADDR is word aligned.  axi_lite_to_apb applies aligned_addr() at both
//       :305 and :333, so a sub-word MMIO access arrives word aligned with the
//       real lane carried in PSTRB.  PADDR[1:0] must therefore always be zero;
//       if it is not, a peripheral decodes the wrong register.
//   A7  A transfer in the access phase completes at a rising clock edge with
//       PREADY high, and PSEL stays high through that edge.
//   A8  At most one PSEL across the fabric.
//   A9  No X on the APB payload.
//
//  Every assertion has a cover.  Action blocks only fill a packed record; see
//  step4_axi_sva.sv and the note in step4_pkg.sv for why.
// =============================================================================

`include "step4_cfg.svh"

module step4_apb_sva #(
  parameter string PORT_NAME  = "apb-bridge",
  parameter int    LOC_IDX    = 4,
  parameter int    STALL_BOUND = `STEP4_STALL_BOUND
) (
  input logic clk,
  input logic rst_n,
  //  Packed [slot][field].  Element 0 is APB[0] (I2C) .. element 5 is APB[5].
  input logic [5:0]        psel,
  input logic [5:0]        penable,
  input logic [5:0]        pwrite,
  input logic [5:0]        pready,
  input logic [5:0]        pslverr,
  input logic [5:0][31:0]  paddr,
  input logic [5:0][31:0]  pwdata,
  input logic [5:0][3:0]   pstrb,
  input logic [5:0][31:0]  prdata,
  //  Pre/post timeout-monitor view, for the timeout-path check
  input logic [5:0]        tmo_pulse,
  step4_hub hub
);

  import step4_pkg::*;

  // ---------------------------------------------------------------------------
  // Deferred-finding buffer (see step4_axi_sva.sv)
  // ---------------------------------------------------------------------------
  localparam int unsigned EVQ = 4;
  step4_evt_t ev_q [EVQ];
  logic [1:0]  ev_w = 0;
  logic [1:0]  ev_r = 0;

  //  See step4_axi_sva.sv: the location is registered by writing the interface
  //  array directly, and the queue is forwarded on the negedge.
  initial hub.loc_name[LOC_IDX] = PORT_NAME;

  always_ff @(negedge clk) begin
    if (!rst_n) begin
      ev_r <= 0;
      ev_w <= 0;
      hub.evt_wp[EVT_CH_APB] <= 0;
      hub.evt_ovf[EVT_CH_APB] <= 0;
    end
    else begin
      // Private mailbox region + modulo + validity test (see step4_axi_sva.sv).
      if (ev_q[ev_r].vld) begin
        automatic int unsigned widx = hub.evt_wp[EVT_CH_APB] % EVT_REGION;
        automatic int unsigned slot = EVT_CH_APB*EVT_REGION + widx;
        if (!hub.evt[slot].vld) begin
          hub.evt[slot]           = ev_q[ev_r];
          hub.evt[slot].vld       = 1'b1;
          hub.evt_wp[EVT_CH_APB]  = (widx + 1) % EVT_REGION;
        end else begin
          hub.evt_ovf[EVT_CH_APB] = hub.evt_ovf[EVT_CH_APB] + 1;
        end
        ev_q[ev_r].vld = 1'b0;
      end
      ev_r = (ev_r + 1) % EVQ;
    end
  end

  //  Hardware handshake shapes
  wire [5:0] setup  = psel & ~penable;   // setup phase: PSEL=1, PENABLE=0
  wire [5:0] access = psel &  penable;   // access phase
  wire [5:0] done   = access & pready;   // transfer completes on this edge
  wire [5:0] waitst = access & ~pready;  // wait states
  wire [5:0] rderr  = access & ~pwrite;

  //  Previous-cycle payload copies: $past() written out, because $past() inside
  //  an SVA action block has no clocking event to infer from.
  logic [5:0][31:0] pp_paddr, pp_pwdata;
  logic [5:0][3:0]  pp_pstrb;
  logic [5:0]        pp_pwrite, pp_penable;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pp_paddr <= '0; pp_pwdata <= '0; pp_pstrb <= '0;
      pp_pwrite <= '0; pp_penable <= '0;
    end
    else begin
      pp_paddr <= paddr; pp_pwdata <= pwdata; pp_pstrb <= pstrb;
      pp_pwrite <= pwrite; pp_penable <= penable;
    end
  end

  // ===========================================================================
  // A1  PENABLE without PSEL is not legal in APB4
  // ===========================================================================
  for (genvar i = 0; i < 6; i++) begin : g_a1
    A_APB_ENABLE_CONSISTENT : assert property (@(posedge clk) disable iff (!rst_n)
        penable[i] |-> psel[i])
      else begin
        ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_APB_ENABLE_CON;
        ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
        ev_q[ev_w].a = {24'h0, i}; ev_w = ev_w + 1;
      end
    C_APB_ENABLE_CONSISTENT : cover property (@(posedge clk) disable iff (!rst_n)
        penable[i] && !psel[i]);
  end

  // ===========================================================================
  // A2  a transfer may not sit in the setup phase
  // ===========================================================================
  for (genvar i = 0; i < 6; i++) begin : g_a2
    A_APB_NO_SETUP_STALL : assert property (@(posedge clk) disable iff (!rst_n)
        $past(setup[i]) |-> (penable[i] || !psel[i]))
      else begin
        ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_APB_ENABLE_SEQ;
        ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
        ev_q[ev_w].a = {24'h0, i}; ev_w = ev_w + 1;
      end
    C_APB_NO_SETUP_STALL : cover property (@(posedge clk) disable iff (!rst_n)
        $past(setup[i]) && psel[i] && penable[i]);
  end

  // ===========================================================================
  // A3  setup-to-access and wait-state stability
  // ===========================================================================
  for (genvar i = 0; i < 6; i++) begin : g_a3
    A_APB_SETUP_STABLE : assert property (@(posedge clk) disable iff (!rst_n)
        setup[i] |=> access[i] |-> ($stable(paddr[i]) && $stable(pwrite[i]) &&
                                     $stable(pwdata[i]) && $stable(pstrb[i])))
      else begin
        ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_APB_SETUP_STABLE;
        ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
        ev_q[ev_w].a = {paddr[i], 8'h00, i};
        ev_q[ev_w].b = pwdata[i];
        ev_q[ev_w].c = {28'h0, pstrb[i]};
        ev_q[ev_w].d = pp_paddr[i];
        ev_w = ev_w + 1;
      end
    C_APB_SETUP_STABLE : cover property (@(posedge clk) disable iff (!rst_n)
        $past(setup[i]) && psel[i] && penable[i]);

    A_APB_WAIT_STABLE : assert property (@(posedge clk) disable iff (!rst_n)
        $past(waitst[i]) && waitst[i]
        |-> ($stable(paddr[i]) && $stable(pwrite[i]) &&
              $stable(pwdata[i]) && $stable(pstrb[i])))
      else begin
        ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_APB_SETUP_STABLE;
        ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
        ev_q[ev_w].a = {paddr[i], 8'h00, i};
        ev_q[ev_w].b = pwdata[i];
        ev_q[ev_w].c = {28'h0, pstrb[i]};
        ev_q[ev_w].d = pp_paddr[i];
        ev_w = ev_w + 1;
      end
    C_APB_WAIT_STABLE : cover property (@(posedge clk) disable iff (!rst_n)
        waitst[i] && $past(waitst[i]));
  end

  // ===========================================================================
  // A4 / A5  response validity
  // ===========================================================================
  for (genvar i = 0; i < 6; i++) begin : g_a4
    A_APB_ERR_IN_ACCESS : assert property (@(posedge clk) disable iff (!rst_n)
        pslverr[i] |-> access[i])
      else begin
        ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_APB_ERR_IN_ACCESS;
        ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
        ev_q[ev_w].a = {24'h0, i}; ev_w = ev_w + 1;
      end
    C_APB_ERR_IN_ACCESS : cover property (@(posedge clk) disable iff (!rst_n)
        pslverr[i] && access[i]);

    A_APB_RDATA_ONLY_RD : assert property (@(posedge clk) disable iff (!rst_n)
        done[i] && pready[i] |-> (pwrite[i] || !$isunknown(prdata[i])))
      else begin
        ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_APB_RDATA_ONLY_RD;
        ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
        ev_q[ev_w].a = {24'h0, i}; ev_q[ev_w].b = prdata[i]; ev_w = ev_w + 1;
      end
    C_APB_RDATA_ONLY_RD : cover property (@(posedge clk) disable iff (!rst_n)
        done[i] && !pwrite[i] && pready[i]);
  end

  // ===========================================================================
  // A6  PADDR alignment
  // ===========================================================================
  for (genvar i = 0; i < 6; i++) begin : g_a6
    A_APB_ADDR_ALIGNED : assert property (@(posedge clk) disable iff (!rst_n)
        psel[i] |-> (paddr[i][1:0] == 2'b00))
      else begin
        ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_APB_ALIGNED;
        ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
        ev_q[ev_w].a = {24'h0, i}; ev_q[ev_w].b = paddr[i]; ev_w = ev_w + 1;
      end
    C_APB_ADDR_ALIGNED : cover property (@(posedge clk) disable iff (!rst_n)
        psel[i] && paddr[i][1:0] == 2'b00);
  end

  // ===========================================================================
  // A7  completion and bounded wait
  // ===========================================================================
  for (genvar i = 0; i < 6; i++) begin : g_a7
    A_APB_COMPLETES : assert property (@(posedge clk) disable iff (!rst_n)
        access[i] |-> ##[0:STALL_BOUND] pready[i])
      else begin
        ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_APB_COMPLETE;
        ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
        ev_q[ev_w].a = {24'h0, i}; ev_q[ev_w].b = paddr[i];
        ev_q[ev_w].d = STALL_BOUND; ev_w = ev_w + 1;
      end
    C_APB_COMPLETES : cover property (@(posedge clk) disable iff (!rst_n)
        access[i] && pready[i]);

    A_APB_PSEL_HELD : assert property (@(posedge clk) disable iff (!rst_n)
        done[i] |=> !psel[i] || !penable[i])
      else begin
        ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_APB_COMPLETE;
        ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
        ev_q[ev_w].a = {24'h0, i}; ev_q[ev_w].b = paddr[i];
        ev_q[ev_w].d = STALL_BOUND; ev_w = ev_w + 1;
      end
    C_APB_PSEL_HELD : cover property (@(posedge clk) disable iff (!rst_n) done[i]);
  end

  // ===========================================================================
  // A8  exactly one slot selected
  // ===========================================================================
  A_APB_ONE_SLOT : assert property (@(posedge clk) disable iff (!rst_n)
      $onehot0(psel))
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_APB_ONE_SLOT;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].a = {26'h0, psel}; ev_w = ev_w + 1;
    end
  C_APB_ONE_SLOT : cover property (@(posedge clk) disable iff (!rst_n) |psel);
  C_APB_NO_SELECT : cover property (@(posedge clk) disable iff (!rst_n) psel == 6'b0);

  // ===========================================================================
  // A9  no X on the APB payload.
  //     One property per signal class rather than one per slot: an X on any
  //     slot's address is the same failure mode and deserves the same check ID,
  //     and the message names the offending slot.
  // ===========================================================================
  A_APB_NO_X_ADDR : assert property (@(posedge clk) disable iff (!rst_n)
      (|psel) |-> !$isunknown(paddr))
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_APB_NO_X_ADDR;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].a = {26'h0, psel}; ev_w = ev_w + 1;
    end
  A_APB_NO_X_CTRL : assert property (@(posedge clk) disable iff (!rst_n)
      (|psel && |pwrite) |-> !$isunknown({pwdata, pstrb}))
    else begin
      ev_q[ev_w].vld = 1'b1; ev_q[ev_w].cid = CID_APB_NO_X_CTRL;
      ev_q[ev_w].layer = L_PROTO; ev_q[ev_w].loc = LOC_IDX;
      ev_q[ev_w].a = {pwdata[0], pstrb[0]}; ev_w = ev_w + 1;
    end
  C_APB_NO_X : cover property (@(posedge clk) disable iff (!rst_n) |psel);

endmodule : step4_apb_sva