// =============================================================================
//  step4_hub.sv : shared reporter state  (INTERFACE -- STORAGE ONLY, NO FUNCTIONS)
// =============================================================================
//  WHY AN INTERFACE AT ALL
//  Every checker needs a handle on the reporter.  A module cannot be used as a
//  port type in xsim at all ("'mhub' is an unknown type"), and a module WITH
//  parameters cannot be either ("unexpected parameter values in module port
//  declaration").  An interface can.  So the handle is an interface, and all the
//  logic that would otherwise live in it lives in step4_reporter.
//
//  WHY THIS INTERFACE HAS NO FUNCTIONS
//  xsim generates code for every function declared in an interface, whether or
//  not anything calls it, and it crashes (EXCEPTION_ACCESS_VIOLATION, during
//  codegen) on anything non-trivial -- functions taking unpacked-array
//  arguments, functions with string outputs, a case statement full of
//  $sformatf.  All of those work perfectly in an ordinary module.
//
//  So the rule for this file is: variables, structs and one always_ff, nothing
//  else.  Checkers and monitors write into it directly; step4_reporter reads it
//  and owns every decision, every string and every $display.  That split is
//  better engineering anyway -- the reporter stays in charge of blame, and the
//  observers stay dumb, which is what a scoreboard is supposed to be.
//
//  Layout
//    rings        circular transaction windows, one per observation tap
//    ret_pc/ret_in  retired-instruction window for the disassembly in the report
//    evt[]        the finding mailbox: checkers fill a slot, the reporter drains it
//    findings[]   everything the reporter has accepted, for the page and the log
//    stats        counters, which are also the vacuity evidence for the pass rule
// =============================================================================

`include "step4_cfg.svh"

interface step4_hub (
  input logic clk,
  input logic rst_n
);

  import step4_pkg::*;

  // ---- sizing, from step4_cfg.svh so every file agrees --------------------
  localparam int unsigned RING_DEPTH   = `STEP4_RING_DEPTH;
  localparam int unsigned RETIRE_DEPTH = `STEP4_RETIRE_DEPTH;
  localparam int unsigned MAX_FINDINGS = `STEP4_MAX_FINDINGS;
  localparam int unsigned EVT_NCH    = 3;
  localparam int unsigned EVT_REGION = 4;
  localparam int unsigned EVT_SLOTS  = EVT_NCH * EVT_REGION;

  // ---- free-running cycle stamp -------------------------------------------
  longint unsigned cyc = 0;
  always_ff @(posedge clk) if (rst_n) cyc <= cyc + 1;

  // ---- observation windows ------------------------------------------------
  step4_rec_t ring_lsu [RING_DEPTH];
  step4_rec_t ring_axi [RING_DEPTH];
  step4_rec_t ring_apb [RING_DEPTH];
  int unsigned wp_lsu = 0, cnt_lsu = 0;
  int unsigned wp_axi = 0, cnt_axi = 0;
  int unsigned wp_apb = 0, cnt_apb = 0;

  // ---- retired-instruction window ----------------------------------------
  logic [31:0] ret_pc [RETIRE_DEPTH];
  logic [31:0] ret_in [RETIRE_DEPTH];
  int unsigned wp_ret = 0, cnt_ret = 0;

  // ---- finding mailbox: one private ring per checker (M2 decoupled forward) ----
  //  The previous revision had ONE shared write pointer `evt_w` incremented by
  //  THREE different `always_ff @(negedge clk)` blocks. That is a multi-driver
  //  variable, and it was worse than a race:
  //    1. every forwarder posted UNCONDITIONALLY (`hub.evt[hub.evt_w] = ev_q[ev_r]`
  //       with no `ev_q[ev_r].vld` test), so the pointer advanced one slot per
  //       checker per clock even in a fault-free run;
  //    2. it was advanced with `+ 1` and NEVER taken modulo EVT_SLOTS, so within
  //       ~3 clocks the index left the array and every subsequent post was an
  //       out-of-bounds write whose event the reporter never saw;
  //    3. `evt_overflow` existed to record a dropped event but nothing ever
  //       incremented it, so losses were silent.
  //  Fix: each forwarder owns a disjoint region of the array and its own write
  //  pointer (single driver per pointer, so no multi-driver race at all), the
  //  pointer is taken modulo the region size, and a full region increments a
  //  per-checker overflow counter instead of overwriting an undrained event.
  // EVT_NCH / EVT_REGION / EVT_SLOTS come from step4_pkg so that the hub, the
  // reporter and all three forwarders cannot drift apart (they all index this
  // one array). EVT_SLOTS == EVT_NCH * EVT_REGION == 12.
  step4_evt_t evt [EVT_SLOTS];
  // evt_wp[ch] has exactly one procedural driver: the forwarder owning channel
  // `ch`. evt[ch*EVT_REGION + k] has exactly one writer (that forwarder, on the
  // negedge) and one clearer (the reporter, on the posedge).
  int unsigned evt_wp  [EVT_NCH];
  int unsigned evt_ovf [EVT_NCH];

  // ---- accepted findings --------------------------------------------------
  step4_evt_t findings [MAX_FINDINGS];
  int unsigned n_find = 0;
  int unsigned n_down = 0;
  int unsigned n_reas = 0;

  // ---- blame state --------------------------------------------------------
  bit          fatal_seen = 0;
  bit          frozen     = 0;
  bit          report_req = 0;      // reporter must emit the page now
  int unsigned blame_cid  = 0;
  layer_t      blame_layer = L_NONE;
  string       blame_where = "";

  // ---- locations registered by the checkers -------------------------------
  string loc_name [LOC_MAX+1];

  // ---- counters -----------------------------------------------------------
  step4_stats_t stats;

  // ---- run control, set by the reporter -----------------------------------
  string test_name = "unnamed";

endinterface : step4_hub