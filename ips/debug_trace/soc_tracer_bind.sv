// =============================================================================
// RISCFORGE 1TOPS — bind soc_tracer into every riscforge_soc_subsystem instance
// =============================================================================
// Testbench only. Compiling this file (via soc_tracer.f) is the only thing
// needed to trace a run; without it the SoC and every testbench are unchanged.
//
// All names on the right-hand side resolve inside riscforge_soc_subsystem.
// If a signal is renamed in the RTL, elaboration fails here, naming it.
// =============================================================================

bind riscforge_soc_subsystem soc_tracer #(
  .NUM_APB        ( NUM_APB_SLAVES                          ),
  .NUM_XBAR_RULES ( NUM_XBAR_RULES                          ),
  .SOC_AXI_REQ_W  ( $bits(axi_req_t)                        ),
  .SOC_AXI_RESP_W ( $bits(axi_resp_t)                       ),
  .SOC_APB_REQ_W  ( $bits(apb_req_t)                        ),
  .SOC_APB_RESP_W ( $bits(apb_resp_t)                       ),
  .SOC_RULE_W     ( $bits(rule_t)                           ),
  // Section 21: hybrid_mem_interface DMEM_BASE_BYTE / MEM_DEPTH / MMIO_*
  .DSRAM_BASE     ( 32'h0002_0000                           ),
  .DSRAM_LIMIT    ( 32'h0002_0000 + DSRAM_NUM_WORDS * 4 - 1 ),
  .MMIO_BASE      ( 32'h4000_0000                           ),
  .MMIO_LIMIT     ( 32'h4FFF_FFFF                           )
) u_soc_tracer (
  .clk_i         ( clk_i                                  ),
  .sys_rst_ni    ( sys_rst_n                              ),
  .core_rst_ni   ( core_rst_n                             ),
  .periph_rst_ni ( periph_rst_n                           ),
  .spi_rst_ni    ( spi_rst_n                              ),
  .boot_done_i   ( boot_done_o                            ),

  // IF / ID
  .pc_f          ( i_riscv_core.Fetch.PCF                 ),
  .pc_d          ( i_riscv_core.PCD                       ),
  .instr_d       ( i_riscv_core.InstrD                    ),
  .valid_d       ( i_riscv_core.valid_D                   ),
  // EX
  .pc_e          ( i_riscv_core.PCE                       ),
  .valid_e       ( i_riscv_core.valid_E                   ),
  // MEM
  .pc_m          ( i_riscv_core.PC_M                      ),
  .valid_m       ( i_riscv_core.valid_M                   ),
  .lsunit_m      ( i_riscv_core.lsunitM                   ),
  .alu_result_m  ( i_riscv_core.ALU_ResultM               ),
  .write_data_m  ( i_riscv_core.WriteDataM                ),
  .mem_hold_wb   ( i_riscv_core.Memory.core_stall_gated   ),
  .lsu_fmt_rdata ( i_riscv_core.Memory.lsu_core_rdata     ),
  // WB
  .pc_w          ( i_riscv_core.PC_W                      ),
  .valid_w       ( i_riscv_core.valid_W                   ),
  .exc_valid_w   ( i_riscv_core.exc_valid_W               ),
  .regwrite_w    ( i_riscv_core.RegWriteW_gated           ),
  .rd_w          ( i_riscv_core.RDW                       ),
  .result_w      ( i_riscv_core.ResultW                   ),
  // Hazard unit
  .stall_f       ( i_riscv_core.StallF                    ),
  .stall_d       ( i_riscv_core.StallD                    ),
  .stall_e       ( i_riscv_core.StallE                    ),
  .stall_m       ( i_riscv_core.StallM                    ),
  .flush_d       ( i_riscv_core.FlushD                    ),
  .flush_e       ( i_riscv_core.FlushE                    ),
  .flush_m       ( i_riscv_core.FlushM                    ),
  .flush_w       ( i_riscv_core.FlushW                    ),
  .mem_stall     ( i_riscv_core.mem_stall_out             ),
  .mul_stall     ( i_riscv_core.stallMUL                  ),
  .pcsrc_e       ( i_riscv_core.PCSrcE                    ),
  .trap_redirect ( i_riscv_core.wb_trap_redirect          ),
  // Trap commit
  .trap_valid    ( i_riscv_core.trap_commit_valid         ),
  .trap_cause    ( i_riscv_core.trap_commit_cause         ),
  .trap_pc       ( i_riscv_core.trap_commit_pc            ),
  .trap_addr     ( i_riscv_core.trap_commit_addr          ),
  .trap_is_irq   ( i_riscv_core.trap_commit_is_interrupt  ),
  .mret_commit   ( i_riscv_core.mret_commit               ),

  // LSU bus
  .lsu_req       ( core_lsu_req                           ),
  .lsu_we        ( core_lsu_we                            ),
  .lsu_addr      ( core_lsu_addr                          ),
  .lsu_wdata     ( core_lsu_wdata                         ),
  .lsu_be        ( core_lsu_be                            ),
  .lsu_rdata     ( core_lsu_rdata                         ),
  .lsu_stall     ( core_lsu_stall                         ),
  .lsu_err       ( core_lsu_err                           ),
  .hmi_wr_state  ( i_core_data_if.axi_write_state         ),
  .hmi_rd_state  ( i_core_data_if.axi_read_state          ),

  // AXI-Lite hops
  .hmi_req       ( core_axi_req                           ),
  .hmi_resp      ( core_axi_resp                          ),
  .xs_req        ( xbar_slv_req[0]                        ),
  .xs_resp       ( xbar_slv_resp[0]                       ),
  .xm_req        ( xbar_mst_req[2]                        ),
  .xm_resp       ( xbar_mst_resp[2]                       ),

  // APB hops
  .bridge_state  ( i_axi_lite_to_apb.apb_state_q          ),
  .apb_req       ( apb_req                                ),
  .apb_resp_slv  ( apb_resp_slv                           ),
  .apb_resp_mst  ( apb_resp                               ),
  .spi_req       ( spi_apb_req                            ),
  .spi_resp      ( spi_apb_resp                           ),

  // Timeout monitors
  .tmo_apb       ( apb_timeout_pulse                      ),
  .tmo_axi_wr    ( axi_wr_timeout_pulse                   ),
  .tmo_axi_rd    ( axi_rd_timeout_pulse                   ),

  // Address maps
  .xbar_map      ( xbar_addr_map                          ),
  .apb_map       ( apb_addr_map                           )
);
