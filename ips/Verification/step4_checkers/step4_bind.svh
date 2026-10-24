// =============================================================================
//  step4_bind.svh : attach the Step 4 checkers to riscforge_soc_subsystem
// =============================================================================
//  `include this file ONCE, inside the testbench module, immediately after the
//  SoC instance and the reporter have been declared:
//
//      riscforge_soc_subsystem u_dut ( .clk_i (clk), .rst_ni (hard_rst_ni), ... );
//      step4_hub               u_hub (.clk(clk), .rst_n(rst_n));
//      step4_reporter     u_step4_rep (.clk(clk), .rst_n(rst_n), .hub(u_hub));
//      step4_fault_inject u_step4_fi  ( .clk(clk), .rst_n(rst_n), .cfg(step4_fi_cfg), ... );
//      `include "step4_bind.svh"
//
//  WHY THE INSTANCE NAMES MATTER
//  A bind statement's port connections are resolved in the scope of the module
//  that CONTAINS the bind statement, not in the scope of the bind target.  That
//  is what lets .hub(u_hub) reach an interface instantiated in the testbench
//  while .apb_req[3].psel reaches a signal inside the SoC.  It also means the
//  SoC instance must be called `u_dut` and the reporter interface `u_hub`.
//  Override with the RF_DUT / RF_HUB macros if your bench uses other names.
//
//  WHAT IS BOUND, AND WHY THERE
//
//   u_step4_axi_core   xbar_slv_req/resp[0] -- the core's AXI4-Lite master, as
//                      seen AFTER axi_lite_timeout_monitor.  Post-monitor on
//                      purpose: the timeout monitor is itself under test, and a
//                      checker sitting in front of it would be blinded to the
//                      abort path.
//   u_step4_axi_bootslave  xbar_slv_req/resp[1] -- the bootloader's master.
//                      It drives APB[4] during boot, so it needs protocol
//                      checking even though it carries no core MMIO traffic.
//   u_step4_apb         apb_req/apb_resp, all six slots in one instance so the
//                      fabric-wide "exactly one PSEL" property is visible.
//   u_step4_path        the end-to-end path scoreboard: LSU -> AXI M2 -> APB
//                      bridge -> slot.
//
//  NOT BOUND HERE
//   xbar_mst_req/resp[0..1] (ISRAM, DSRAM).  They are the same protocol with a
//   different address map; bind them from the SoC regression with LOC_AXI_* if
//   the SRAM agents ever become multi-transaction.  The core never uses them
//   for MMIO, so the Step 4 path has nothing to say about them.
// =============================================================================

`ifndef RF_DUT
  `define RF_DUT u_dut
`endif
`ifndef RF_HUB
  `define RF_HUB u_hub
`endif

// ---------------------------------------------------------------------------
//  Flattened APB views.  Built as concatenations because the SoC keeps apb_req
//  as an unpacked array of packed structs, while the checkers take packed
//  [slot][field] ports: one bind, one port map, and the element order is stated
//  here once instead of being implied by six near-identical bindings.
//  Element 0 is APB[0] (I2C) .. element 5 is APB[5] (Timer1).
// ---------------------------------------------------------------------------
`define RF_APB_PSEL     {`RF_DUT.apb_req[5].psel,    `RF_DUT.apb_req[4].psel,    `RF_DUT.apb_req[3].psel,    `RF_DUT.apb_req[2].psel,    `RF_DUT.apb_req[1].psel,    `RF_DUT.apb_req[0].psel}
`define RF_APB_PENABLE  {`RF_DUT.apb_req[5].penable, `RF_DUT.apb_req[4].penable, `RF_DUT.apb_req[3].penable, `RF_DUT.apb_req[2].penable, `RF_DUT.apb_req[1].penable, `RF_DUT.apb_req[0].penable}
`define RF_APB_PWRITE   {`RF_DUT.apb_req[5].pwrite,  `RF_DUT.apb_req[4].pwrite,  `RF_DUT.apb_req[3].pwrite,  `RF_DUT.apb_req[2].pwrite,  `RF_DUT.apb_req[1].pwrite,  `RF_DUT.apb_req[0].pwrite}
`define RF_APB_PADDR    {`RF_DUT.apb_req[5].paddr,   `RF_DUT.apb_req[4].paddr,   `RF_DUT.apb_req[3].paddr,   `RF_DUT.apb_req[2].paddr,   `RF_DUT.apb_req[1].paddr,   `RF_DUT.apb_req[0].paddr}
`define RF_APB_PWDATA   {`RF_DUT.apb_req[5].pwdata,  `RF_DUT.apb_req[4].pwdata,  `RF_DUT.apb_req[3].pwdata,  `RF_DUT.apb_req[2].pwdata,  `RF_DUT.apb_req[1].pwdata,  `RF_DUT.apb_req[0].pwdata}
`define RF_APB_PSTRB    {`RF_DUT.apb_req[5].pstrb,   `RF_DUT.apb_req[4].pstrb,   `RF_DUT.apb_req[3].pstrb,   `RF_DUT.apb_req[2].pstrb,   `RF_DUT.apb_req[1].pstrb,   `RF_DUT.apb_req[0].pstrb}
`define RF_APB_PREADY   {`RF_DUT.apb_resp[5].pready, `RF_DUT.apb_resp[4].pready, `RF_DUT.apb_resp[3].pready, `RF_DUT.apb_resp[2].pready, `RF_DUT.apb_resp[1].pready, `RF_DUT.apb_resp[0].pready}
`define RF_APB_PSLVERR  {`RF_DUT.apb_resp[5].pslverr,`RF_DUT.apb_resp[4].pslverr,`RF_DUT.apb_resp[3].pslverr,`RF_DUT.apb_resp[2].pslverr,`RF_DUT.apb_resp[1].pslverr,`RF_DUT.apb_resp[0].pslverr}
`define RF_APB_PRDATA   {`RF_DUT.apb_resp[5].prdata, `RF_DUT.apb_resp[4].prdata, `RF_DUT.apb_resp[3].prdata, `RF_DUT.apb_resp[2].prdata, `RF_DUT.apb_resp[1].prdata, `RF_DUT.apb_resp[0].prdata}
`define RF_APB_TMO      {`RF_DUT.apb_timeout_pulse}

// =============================================================================
//  1. AXI4-Lite protocol -- the core's master port
// =============================================================================
bind riscforge_soc_subsystem step4_axi_sva #(
  .PORT_NAME ("core-MMIO-axil"),
  .LOC_IDX   (step4_pkg::LOC_AXI_CORE)
) u_step4_axi_core (
  .clk       (`RF_DUT.clk_i),
  .rst_n     (`RF_DUT.sys_rst_n),
  .aw_addr   (`RF_DUT.xbar_slv_req[0].aw.addr),
  .aw_prot   (`RF_DUT.xbar_slv_req[0].aw.prot),
  .aw_valid  (`RF_DUT.xbar_slv_req[0].aw_valid),
  .aw_ready  (`RF_DUT.xbar_slv_resp[0].aw_ready),
  .w_data    (`RF_DUT.xbar_slv_req[0].w.data),
  .w_strb    (`RF_DUT.xbar_slv_req[0].w.strb),
  .w_valid   (`RF_DUT.xbar_slv_req[0].w_valid),
  .w_ready   (`RF_DUT.xbar_slv_resp[0].w_ready),
  .b_resp    (`RF_DUT.xbar_slv_resp[0].b.resp),
  .b_valid   (`RF_DUT.xbar_slv_resp[0].b_valid),
  .b_ready   (`RF_DUT.xbar_slv_req[0].b_ready),
  .ar_addr   (`RF_DUT.xbar_slv_req[0].ar.addr),
  .ar_prot   (`RF_DUT.xbar_slv_req[0].ar.prot),
  .ar_valid  (`RF_DUT.xbar_slv_req[0].ar_valid),
  .ar_ready  (`RF_DUT.xbar_slv_resp[0].ar_ready),
  .r_data    (`RF_DUT.xbar_slv_resp[0].r.data),
  .r_resp    (`RF_DUT.xbar_slv_resp[0].r.resp),
  .r_valid   (`RF_DUT.xbar_slv_resp[0].r_valid),
  .r_ready   (`RF_DUT.xbar_slv_req[0].r_ready),
  .hub       (`RF_HUB)
);

// =============================================================================
//  2. AXI4-Lite protocol -- the bootloader's master port (APB[4] during boot)
// =============================================================================
bind riscforge_soc_subsystem step4_axi_sva #(
  .PORT_NAME ("bootloader-axil"),
  .LOC_IDX   (step4_pkg::LOC_AXI_BOOT)
) u_step4_axi_boot (
  .clk       (`RF_DUT.clk_i),
  .rst_n     (`RF_DUT.sys_rst_n),
  .aw_addr   (`RF_DUT.xbar_slv_req[1].aw.addr),
  .aw_prot   (`RF_DUT.xbar_slv_req[1].aw.prot),
  .aw_valid  (`RF_DUT.xbar_slv_req[1].aw_valid),
  .aw_ready  (`RF_DUT.xbar_slv_resp[1].aw_ready),
  .w_data    (`RF_DUT.xbar_slv_req[1].w.data),
  .w_strb    (`RF_DUT.xbar_slv_req[1].w.strb),
  .w_valid   (`RF_DUT.xbar_slv_req[1].w_valid),
  .w_ready   (`RF_DUT.xbar_slv_resp[1].w_ready),
  .b_resp    (`RF_DUT.xbar_slv_resp[1].b.resp),
  .b_valid   (`RF_DUT.xbar_slv_resp[1].b_valid),
  .b_ready   (`RF_DUT.xbar_slv_req[1].b_ready),
  .ar_addr   (`RF_DUT.xbar_slv_req[1].ar.addr),
  .ar_prot   (`RF_DUT.xbar_slv_req[1].ar.prot),
  .ar_valid  (`RF_DUT.xbar_slv_req[1].ar_valid),
  .ar_ready  (`RF_DUT.xbar_slv_resp[1].ar_ready),
  .r_data    (`RF_DUT.xbar_slv_resp[1].r.data),
  .r_resp    (`RF_DUT.xbar_slv_resp[1].r.resp),
  .r_valid   (`RF_DUT.xbar_slv_resp[1].r_valid),
  .r_ready   (`RF_DUT.xbar_slv_req[1].r_ready),
  .hub       (`RF_HUB)
);

// =============================================================================
//  3. APB4 protocol -- all six slots, one instance
// =============================================================================
bind riscforge_soc_subsystem step4_apb_sva #(
  .PORT_NAME ("apb-bridge"),
  .LOC_IDX   (step4_pkg::LOC_APB)
) u_step4_apb (
  .clk       (`RF_DUT.clk_i),
  .rst_n     (`RF_DUT.sys_rst_n),
  .psel      (`RF_APB_PSEL),
  .penable   (`RF_APB_PENABLE),
  .pwrite    (`RF_APB_PWRITE),
  .pready    (`RF_APB_PREADY),
  .pslverr   (`RF_APB_PSLVERR),
  .paddr     (`RF_APB_PADDR),
  .pwdata    (`RF_APB_PWDATA),
  .pstrb     (`RF_APB_PSTRB),
  .prdata    (`RF_APB_PRDATA),
  .tmo_pulse (`RF_APB_TMO),
  .hub       (`RF_HUB)
);

// =============================================================================
//  4. End-to-end MMIO path scoreboard
//     tap A: the core LSU
//     tap B: the AXI4-Lite transaction on xbar slave port 0
//     tap C: the completed APB transfer
//     bootloader: accounted for so its APB[4] traffic is not read as a ghost
// =============================================================================
bind riscforge_soc_subsystem step4_path_scoreboard u_step4_path (
  .clk             (`RF_DUT.clk_i),
  .rst_n           (`RF_DUT.sys_rst_n),

  .lsu_req         (`RF_DUT.core_lsu_req),
  .lsu_addr        (`RF_DUT.core_lsu_addr),
  .lsu_we          (`RF_DUT.core_lsu_we),
  .lsu_wdata       (`RF_DUT.core_lsu_wdata),
  .lsu_be          (`RF_DUT.core_lsu_be),
  .lsu_stall       (`RF_DUT.core_lsu_stall),

  .aw_addr         (`RF_DUT.xbar_slv_req[0].aw.addr),
  .aw_valid        (`RF_DUT.xbar_slv_req[0].aw_valid),
  .aw_ready        (`RF_DUT.xbar_slv_resp[0].aw_ready),
  .w_data          (`RF_DUT.xbar_slv_req[0].w.data),
  .w_strb          (`RF_DUT.xbar_slv_req[0].w.strb),
  .w_valid         (`RF_DUT.xbar_slv_req[0].w_valid),
  .w_ready         (`RF_DUT.xbar_slv_resp[0].w_ready),
  .ar_addr         (`RF_DUT.xbar_slv_req[0].ar.addr),
  .ar_valid        (`RF_DUT.xbar_slv_req[0].ar_valid),
  .ar_ready        (`RF_DUT.xbar_slv_resp[0].ar_ready),
  .b_valid         (`RF_DUT.xbar_slv_resp[0].b_valid),
  .b_ready         (`RF_DUT.xbar_slv_req[0].b_ready),
  .b_resp          (`RF_DUT.xbar_slv_resp[0].b.resp),
  .r_valid         (`RF_DUT.xbar_slv_resp[0].r_valid),
  .r_ready         (`RF_DUT.xbar_slv_req[0].r_ready),
  .r_resp          (`RF_DUT.xbar_slv_resp[0].r.resp),
  .r_data          (`RF_DUT.xbar_slv_resp[0].r.data),
  .axi_tmo_pulse   (`RF_DUT.axi_rd_timeout_pulse | `RF_DUT.axi_wr_timeout_pulse),

  .boot_aw_addr    (`RF_DUT.xbar_slv_req[1].aw.addr),
  .boot_aw_valid   (`RF_DUT.xbar_slv_req[1].aw_valid),
  .boot_aw_ready   (`RF_DUT.xbar_slv_resp[1].aw_ready),
  .boot_ar_addr    (`RF_DUT.xbar_slv_req[1].ar.addr),
  .boot_ar_valid   (`RF_DUT.xbar_slv_req[1].ar_valid),
  .boot_ar_ready   (`RF_DUT.xbar_slv_resp[1].ar_ready),

  .apb_psel        (`RF_APB_PSEL),
  .apb_penable     (`RF_APB_PENABLE),
  .apb_pwrite      (`RF_APB_PWRITE),
  .apb_pready      (`RF_APB_PREADY),
  .apb_pslverr     (`RF_APB_PSLVERR),
  .apb_paddr       (`RF_APB_PADDR),
  .apb_pwdata      (`RF_APB_PWDATA),
  .apb_prdata      (`RF_APB_PRDATA),
  .apb_pstrb       (`RF_APB_PSTRB),
  .apb_tmo_pulse   (`RF_APB_TMO),

  .hub             (`RF_HUB)
);