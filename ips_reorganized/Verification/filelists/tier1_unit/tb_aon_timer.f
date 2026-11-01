// RISCFORGE 1TOPS — Tier 1 IP Unit: aon_timer (Watchdog)
// Invocation root: rtl/ips
// Top: tb_watchdog_full
// Note: Primitives under SOC_FILES/include/watchdog/ reside on the remote EDA
//       CentOS tree (/home/iiita/MALAY_SOC/rtl/SOC_FILES/include/watchdog/).

+incdir+SOC_FILES/include/watchdog/prim

// Packages
SOC_FILES/include/watchdog/prim_abstract/prim_pkg.sv
SOC_FILES/include/watchdog/prim/prim_util_pkg.sv
SOC_FILES/include/watchdog/prim/prim_mubi_pkg.sv
SOC_FILES/include/watchdog/prim/prim_secded_pkg.sv
SOC_FILES/include/watchdog/prim/prim_subreg_pkg.sv
SOC_FILES/include/watchdog/prim/prim_alert_pkg.sv
SOC_FILES/include/watchdog/top_pkg/top_pkg.sv
SOC_FILES/include/watchdog/tlul/tlul_pkg.sv
SOC_FILES/include/watchdog/lc_ctrl/lc_ctrl_reg_pkg.sv
SOC_FILES/include/watchdog/lc_ctrl/lc_ctrl_state_pkg.sv
SOC_FILES/include/watchdog/lc_ctrl/lc_ctrl_pkg.sv
aon_timer/rtl/aon_timer_reg_pkg.sv

// Primitives
SOC_FILES/include/watchdog/prim_generic/prim_generic_flop.sv
SOC_FILES/include/watchdog/prim_generic/prim_generic_buf.sv
SOC_FILES/include/watchdog/prim_generic/prim_generic_flop_2sync.sv
SOC_FILES/include/watchdog/prim_generic/prim_generic_xnor2.sv
SOC_FILES/include/watchdog/prim_xilinx/prim_xilinx_flop.sv
SOC_FILES/include/watchdog/prim_xilinx/prim_xilinx_buf.sv
SOC_FILES/include/watchdog/prim_xilinx_ultrascale/prim_xilinx_ultrascale_flop.sv
SOC_FILES/include/watchdog/prim_xilinx_ultrascale/prim_xilinx_ultrascale_buf.sv
SOC_FILES/include/watchdog/prim_abstract/prim_flop.sv
SOC_FILES/include/watchdog/prim_abstract/prim_buf.sv
SOC_FILES/include/watchdog/prim_abstract/prim_flop_2sync.sv
SOC_FILES/include/watchdog/prim_abstract/prim_xnor2.sv

// OpenTitan Primitives
SOC_FILES/include/watchdog/prim/prim_cdc_rand_delay.sv
SOC_FILES/include/watchdog/prim/prim_sec_anchor_buf.sv
SOC_FILES/include/watchdog/prim/prim_sec_anchor_flop.sv
SOC_FILES/include/watchdog/prim/prim_diff_decode.sv
SOC_FILES/include/watchdog/prim/prim_alert_sender.sv
SOC_FILES/include/watchdog/prim/prim_lc_sync.sv
SOC_FILES/include/watchdog/prim/prim_edge_detector.sv
SOC_FILES/include/watchdog/prim/prim_intr_hw.sv
SOC_FILES/include/watchdog/prim/prim_pulse_sync.sv
SOC_FILES/include/watchdog/prim/prim_sync_reqack.sv
SOC_FILES/include/watchdog/prim/prim_reg_cdc_arb.sv
SOC_FILES/include/watchdog/prim/prim_reg_cdc.sv
SOC_FILES/include/watchdog/prim/prim_onehot_check.sv
SOC_FILES/include/watchdog/prim/prim_reg_we_check.sv
SOC_FILES/include/watchdog/prim/prim_secded_inv_39_32_dec.sv
SOC_FILES/include/watchdog/prim/prim_secded_inv_39_32_enc.sv
SOC_FILES/include/watchdog/prim/prim_secded_inv_64_57_dec.sv
SOC_FILES/include/watchdog/prim/prim_secded_inv_64_57_enc.sv
SOC_FILES/include/watchdog/prim/watchdog_prim_subreg_arb.sv
SOC_FILES/include/watchdog/prim/watchdog_prim_subreg.sv
SOC_FILES/include/watchdog/prim/watchdog_prim_subreg_ext.sv

// TL-UL
SOC_FILES/include/watchdog/tlul/tlul_data_integ_dec.sv
SOC_FILES/include/watchdog/tlul/tlul_data_integ_enc.sv
SOC_FILES/include/watchdog/tlul/tlul_cmd_intg_chk.sv
SOC_FILES/include/watchdog/tlul/tlul_cmd_intg_gen.sv
SOC_FILES/include/watchdog/tlul/tlul_rsp_intg_gen.sv
SOC_FILES/include/watchdog/tlul/tlul_err.sv
SOC_FILES/include/watchdog/tlul/tlul_adapter_reg.sv

// Watchdog IP
aon_timer/rtl/aon_timer_reg_top.sv
aon_timer/rtl/aon_timer_core.sv
aon_timer/rtl/aon_timer.sv

// Testbench
aon_timer/tb_files/prim_alert_receiver.sv
aon_timer/tb_watchdog_full.sv
