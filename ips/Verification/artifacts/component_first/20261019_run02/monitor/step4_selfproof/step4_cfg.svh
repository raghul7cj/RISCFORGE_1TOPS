// =============================================================================
//  step4_cfg.svh : global compile-time configuration for the Step 4 checkers
// =============================================================================
//  Included by every file in this package, because the reporter is used as a
//  PORT TYPE by every checker.  A parameterized module cannot appear as a port
//  with a parameter override, so the sizes have to come from macros that every
//  file agrees on.  Relying on the macro being defined in step4_pkg.sv would make
//  the package order-dependent in the file list -- a trap, because alphabetical
//  order puts step4_apb_sva.sv before step4_pkg.sv.
//
//  Override on the command line, e.g.
//      +define+STEP4_RING_DEPTH=64 +define+STEP4_STALL_BOUND=256
// =============================================================================

`ifndef STEP4_CFG_SVH
`define STEP4_CFG_SVH

`ifndef STEP4_RING_DEPTH
  `define STEP4_RING_DEPTH 16
`endif
`ifndef STEP4_RETIRE_DEPTH
  `define STEP4_RETIRE_DEPTH 32
`endif
`ifndef STEP4_MAX_FINDINGS
  `define STEP4_MAX_FINDINGS 64
`endif
`ifndef STEP4_REPORT_FILE
  `define STEP4_REPORT_FILE "step4_report.txt"
`endif
`ifndef STEP4_PCMAP_FILE
  `define STEP4_PCMAP_FILE ""
`endif

//  Longest legal single-channel stall the protocol assertions will wait before
//  declaring deadlock.  Deliberately far below AXI_TIMEOUT_APB (131072): the
//  axi_lite_timeout_monitor already covers the long tail, and an SVA range of
//  131k cycles is expensive for any simulator to carry.  If this fires the bus
//  is already dead long before the hardware monitor would have noticed.
`ifndef STEP4_STALL_BOUND
  `define STEP4_STALL_BOUND 64
`endif

`endif // STEP4_CFG_SVH