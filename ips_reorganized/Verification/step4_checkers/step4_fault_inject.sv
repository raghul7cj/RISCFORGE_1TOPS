// =============================================================================
//  step4_fault_inject.sv : fault injection framework
// =============================================================================
//  Step 4 of the integration guide asks for this explicitly:
//
//    "Give every checker a fault-injection switch (for example, force one byte
//     strobe) so you can prove it fires."
//    Proof: "each injected fault is named by the correct check ID in the report,
//     and every assertion has a cover that is hit."
//
//  A checker that has never been seen to fire is indistinguishable from a
//  checker that is dead.  Formal handles that by proof; in simulation the only
//  answer is to break the thing on purpose and confirm the right check names it.
//
//  TWO KINDS OF INJECTION, AND WHY BOTH
//
//  1. OBSERVATION-SIDE (default, always available)
//     The injector sits between the DUT tap and the checker inputs and publishes
//     a corrupted VIEW of the payload.  The RTL is untouched, the transaction
//     still completes for real, and the checker sees a violation.  This proves
//     the checker logic, which is what Step 4 owns.  Safe: no force, no release,
//     no risk of leaving a net stuck, and it works on golden RTL with no
//     RTL changes at all.
//
//  2. DUT-SIDE (opt-in, needs +define+STEP4_FORCE_FI)
//     Procedural force/release on the real nets, so the DESIGN reacts too: a
//     stuck PREADY really does make apb_timeout_monitor fire, and a corrupted
//     strobe really does reach the peripheral.  This is how you prove the
//     timeout path end to end, which observation-side injection cannot do.
//     Deliberately compiled out by default -- a force that is not released can
//     silently poison a regression, and that risk should be a deliberate choice.
//
//  The injector corrupts PAYLOAD ONLY.  Valid and ready are passed straight
//  through from the DUT, so an injected fault never accidentally also breaks the
//  handshake properties and the protocol checker cannot tell which check is
//  supposed to fire.  One fault, one check ID.
// =============================================================================

`include "step4_cfg.svh"

//  Imported at file scope, not inside the module body: the configuration type
//  appears in the PORT LIST, and port lists are elaborated before any
//  module-body import has taken effect.
import step4_fault_inject_pkg::*;

module step4_fault_inject (
  input  logic clk,
  input  logic rst_n,

  // ---- configuration from the testbench -----------------------------------
  input  step4_fault_inject_cfg_t cfg,

  // ---- control (not corrupted) --------------------------------------------
  input  logic        i_lsu_req,
  input  logic        i_lsu_we,
  input  logic        i_lsu_stall,
  input  logic        i_aw_valid, i_aw_ready,
  input  logic        i_w_valid,  i_w_ready,
  input  logic        i_ar_valid, i_ar_ready,
  input  logic        i_b_valid,  i_b_ready,
  input  logic        i_r_valid,  i_r_ready,
  input  logic [5:0]  i_psel,
  input  logic [5:0]  i_penable,
  input  logic [5:0]  i_pwrite,
  input  logic [5:0]  i_pready,

  // ---- payload in, from the DUT -------------------------------------------
  input  logic [31:0] i_lsu_addr,
  input  logic [31:0] i_lsu_wdata,
  input  logic [3:0]  i_lsu_be,
  input  logic [31:0] i_aw_addr,
  input  logic [31:0] i_w_data,
  input  logic [3:0]  i_w_strb,
  input  logic [31:0] i_ar_addr,
  input  logic [1:0]  i_b_resp,
  input  logic [1:0]  i_r_resp,
  input  logic [31:0] i_r_data,
  input  logic [5:0][31:0] i_paddr,
  input  logic [5:0][31:0] i_pwdata,
  input  logic [5:0][31:0] i_prdata,
  input  logic [5:0][3:0]  i_pstrb,
  input  logic [5:0]        i_pslverr,

  // ---- payload out, what the checkers actually observe --------------------
  output logic [31:0] o_lsu_addr,
  output logic [31:0] o_lsu_wdata,
  output logic [3:0]  o_lsu_be,
  output logic [31:0] o_aw_addr,
  output logic [31:0] o_w_data,
  output logic [3:0]  o_w_strb,
  output logic [31:0] o_ar_addr,
  output logic [1:0]  o_b_resp,
  output logic [1:0]  o_r_resp,
  output logic [31:0] o_r_data,
  output logic [5:0][31:0] o_paddr,
  output logic [5:0][31:0] o_pwdata,
  output logic [5:0][31:0] o_prdata,
  output logic [5:0][3:0]  o_pstrb,
output logic [5:0]        o_pslverr,
output logic [5:0]        o_psel,
output logic [5:0]        o_penable,
output logic [5:0]        o_pready
);

  import step4_pkg::*;

  //  The injector needs its own cycle counter because it must be able to arm
  //  before anything else has been elaborated.
  longint unsigned t = 0;
  always_ff @(posedge clk) if (rst_n) t <= t + 1;

  function automatic longint unsigned cycle_now();
    return t;
  endfunction

  // ---------------------------------------------------------------------------
  // Injection bookkeeping.
  //
  //  `fire` is high on the cycles the fault applies, and is counted in
  //  TRANSACTIONS, not cycles.  Counting cycles would corrupt a random subset of
  //  payloads and the resulting failure would not be reproducible from a seed --
  //  which defeats the point of having a seed at all.
  // ---------------------------------------------------------------------------
  step4_fault_inject_cfg_t c;      // working copy of the configuration
  int unsigned             fired;
  bit                      done;
  logic [5:0]              wait_hold; // FI_WAIT: slots held in fake access phase

  // =============================================================================
//  THE ONE RULE THAT MAKES FAULT INJECTION WORK HERE
//
//  A path scoreboard compares two observation points.  If you corrupt both, it
//  sees a consistent world and reports nothing.  So every injector in this file
//  breaks exactly ONE hop in the chain
//
//      core_lsu_*  ->  AXI4-Lite  ->  APB PSTRB/PDATA
//
//  and leaves the others alone.  An injector that spoils the whole chain is
//  worthless for proving a path check: it proves only that the file compiles.
//
//  Each injector names the hop it breaks in its comment, and the self-proof
//  matrix in step4_smoke_tb.sv lists the check ID that must result.
// =============================================================================

  //  Injection window: active from at_cycle for n_times CYCLES, or until the
  //  testbench disarms it, whichever comes first.  Measured in cycles rather
  //  than transfers on purpose -- the self-proof drives one known transfer and
  //  needs to know the window is still open when the APB access phase happens,
//  //  which is a fixed number of cycles after the request, not a fixed number
  //  //  of transfers.
  //
  //  The window is PER ARM: disarming (between self-proof cases) clears the
  //  fired/done budget, otherwise it accumulates across the whole matrix and
  //  the lifetime budget is exhausted mid-matrix, so later cases inject
  //  nothing and end with no finding at all.
  //
  //  `fire` is defined here (before the bookkeeping block) because the
  //  FI_WAIT hold latch below needs it and SystemVerilog requires declaration
  //  before use in this flow.
  wire fire = (!done && c.armed && c.kind != FI_NONE && (t >= c.at_cycle) &&
               (fired < c.n_times));

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      c         <= cfg;
      fired     <= 0;
      done      <= 1'b0;
      wait_hold <= '0;
    end
    else begin
      c <= cfg;
      if (!c.armed) begin
        fired     <= 0;
        done      <= 1'b0;
        wait_hold <= '0;
      end
      else begin
        if (!done) begin
          if (c.kind != FI_NONE && (t >= c.at_cycle)) begin
            if (fired >= c.n_times) done <= 1'b1;
            else                    fired <= fired + 1;
          end
        end
        //  FI_WAIT outlives the live transfer (see the FI_WAIT arm): latch the
        //  stalled slot on the real PSEL and hold it for the wait budget.
        if (c.kind == FI_WAIT && fire && |(i_psel & c.slot_mask))
          wait_hold <= wait_hold | (i_psel & c.slot_mask);
        if ((t >= c.at_cycle) && ((t - c.at_cycle) >= c.wait_cycles))
          wait_hold <= '0;
      end
    end
  end

  //  Which slot the injector is aimed at: the lowest set bit of the mask.
  int i_slot;
  always_comb begin
    i_slot = 0;
    for (int unsigned k = 0; k < step4_pkg::NUM_APB_SLAVES; k++)
      if (c.slot_mask[k]) begin i_slot = k; break; end
  end

  //  Must be declared before the always_comb that indexes o_*[i_slot].
  wire target_apb = |(i_psel & c.slot_mask);
  wire fire_apb   = fire && target_apb;

  // ===========================================================================
  //  The three injectors the plan names, plus the data ones the proof matrix
  //  needs.
  // ===========================================================================
  always_comb begin
    // ---- default: pass everything through unchanged ----
    o_lsu_addr  = i_lsu_addr;
    o_lsu_wdata = i_lsu_wdata;
    o_lsu_be    = i_lsu_be;
    o_aw_addr   = i_aw_addr;
    o_w_data    = i_w_data;
    o_w_strb    = i_w_strb;
    o_ar_addr   = i_ar_addr;
    o_b_resp    = i_b_resp;
    o_r_resp    = i_r_resp;
    o_r_data    = i_r_data;
    o_paddr     = i_paddr;
    o_pwdata    = i_pwdata;
    o_prdata    = i_prdata;
    o_psel      = i_psel;      // phase signals are never corrupted, but they MUST
    o_penable   = i_penable;   // be driven: an undriven output floats X and every
                             // APB check downstream silently sees nothing.
    o_pstrb     = i_pstrb;
    o_pslverr   = i_pslverr;
    o_pready    = i_pready;

    if (fire) begin
      case (c.kind)

        // ---- 1. STROBE CORRUPTOR -- breaks the APB hop --------------------
        //  Forces PSTRB on the live transfer and touches nothing else, so the
        //  scoreboard sees LSU byte enables == AXI WSTRB but APB PSTRB different.
        //  That is exactly a byte lane dropped on the way into the peripheral.
        //  Expected check: PATH_STRB.
        FI_STROBE: begin
          if (fire_apb) o_pstrb[i_slot] = c.strb_value;
        end

        // ---- 1b. STROBE CORRUPTOR ON THE AXI HOP --------------------------
        //  Same fault, one hop earlier: WSTRB is forced while the LSU byte
        //  enables and the APB PSTRB are left alone.  Two different injection
        //  points for one check, because the check has to catch a lane lost on
        //  either side of the bridge.
        //  Expected check: PATH_STRB.
        FI_STROBE_AXI: begin
          o_w_strb = c.strb_value;
        end

        // ---- 2. WAIT-STATE INJECTOR -- breaks the APB response ------------
        //  Reports PREADY late to the checker, simulating a slow peripheral.
        //  Once the injected stall passes STEP4_STALL_BOUND the check must fire.
        //  Under +define+STEP4_FORCE_FI the real PREADY is forced low instead,
        //  so the design's own apb_timeout_monitor fires and the SLVERR path is
        //  exercised for real.
        //
        //  Observation-side subtlety: the live transfer retires in two cycles,
        //  so gating the stall on live PSEL would release after two cycles and
        //  the completion bound could never expire.  The stalled slot is
        //  therefore latched (wait_hold) on the live transfer and held --
        //  PSEL and PENABLE high with PREADY low in the checker view -- for
        //  the whole wait budget, so the access-phase completion bound
        //  (APB_COMPLETE) expires mid-stall.  Payload is untouched, so no
        //  stability check can fire first; the scoreboard's missing-transfer
        //  finding fires at record close and blame is then reassigned to the
        //  PROTO layer, which is the precedence the self-proof checks.
        //  Expected check: APB_COMPLETE.
        FI_WAIT: begin
          if (fire && wait_hold[i_slot] && ((t - c.at_cycle) < c.wait_cycles)) begin
            o_psel[i_slot]    = 1'b1;
            o_penable[i_slot] = 1'b1;
            o_pready[i_slot]  = 1'b0;
          end
        end

        // ---- 3a. PARITY-STYLE ERROR TRIGGER -- breaks the APB response -----
        //  A peripheral raising PSLVERR for a reason the bridge cannot see: the
        //  stand-in for a parity failure on an otherwise unprotected fabric.
        //  The AXI response is left as the bridge produced it (OKAY), so this
        //  is precisely the "the bridge swallowed an error" scenario.
        //  Expected check: PATH_RESP.
        FI_SLVERR: begin
          if (fire_apb && i_psel[i_slot] && i_penable[i_slot])
            o_pslverr[i_slot] = 1'b1;
        end

        // ---- 3b. TIMEOUT TRIGGER -- breaks the APB read data ---------------
        //  Injects the sentinel the timeout monitors use.  A read returning
        //  32'hDEAD_BEEF from a slot is a timeout, and the register layer must
        //  never accept it as peripheral data.
        //  Expected check: PATH_RDATA.
        FI_TIMEOUT: begin
          if (fire_apb && i_psel[i_slot] && i_penable[i_slot])
            o_prdata[i_slot] = step4_pkg::APB_TIMEOUT_DATA;
        end

        // ---- 4. APB ADDRESS CORRUPTION -- breaks the APB request ----------
        //  Moves PADDR to a different register inside the slot.  The slot
        //  itself is chosen by the bridge's decoder and cannot be corrupted
        //  from outside, so this shows up as an address mismatch, not a slot
        //  mismatch.
        //  Expected check: PATH_ADDR.
        FI_PADDR: begin
          if (fire_apb) o_paddr[i_slot] = o_paddr[i_slot] ^ c.data_value;
        end

        // ---- 5. AXI ADDRESS CORRUPTION -- breaks the AXI request ----------
        //  The address the core asked for and the address the fabric is given
        //  now disagree, which is what a broken address path from the LSU bus
        //  onto aw.addr looks like.
        //  Expected check: PATH_NO_LOSS.
        FI_AXI_ADDR: begin
          o_aw_addr = o_aw_addr ^ c.data_value;
          o_ar_addr = o_ar_addr ^ c.data_value;
        end

        // ---- 6. APB WRITE DATA CORRUPTION -- breaks the APB request --------
        //  Expected check: PATH_WDATA.
        FI_WDATA: begin
          if (fire_apb) o_pwdata[i_slot] = o_pwdata[i_slot] ^ c.data_value;
        end

        // ---- 7. APB READ DATA CORRUPTION -- breaks the APB response --------
        //  Expected check: PATH_RDATA.
        FI_RDATA: begin
          if (fire_apb) o_prdata[i_slot] = o_prdata[i_slot] ^ c.data_value;
        end

        // ---- 8. RESPONSE CORRUPTION -- breaks the AXI response -------------
        //  Replaces the response code the bridge produced.  Run against a read
        //  of an unmapped hole, where RESP_DECERR is the only legal answer.
        //  Expected check: PATH_HOLE.
        FI_RESP: begin
          o_b_resp = c.resp_value;
          o_r_resp = c.resp_value;
        end

        // ---- 9. WRITE DATA ON THE AXI HOP -- breaks the AXI request -------
        //  The core's write data and the data the fabric carries now disagree.
        //  Expected check: PATH_WDATA.
        FI_AXI_WDATA: begin
          o_w_data = o_w_data ^ c.data_value;
        end
        default: ;   // FI_NONE
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  //  Bookkeeping for the proof matrix
  // ---------------------------------------------------------------------------
  int unsigned n_injected = 0;
  always_ff @(posedge clk) begin
    if (rst_n && fire && c.kind != FI_NONE)
      n_injected <= n_injected + 1;
  end

  function automatic bit injected();
    return n_injected != 0;
  endfunction

endmodule : step4_fault_inject


// =============================================================================
//  DUT-side injection.  Opt-in, because a force that is never released silently
//  poisons everything downstream of it.
// =============================================================================

