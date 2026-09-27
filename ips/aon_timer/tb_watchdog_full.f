// =============================================================================
// RISCFORGE 1TOPS — Watchdog (OpenTitan aon_timer) detailed testbench filelist
// =============================================================================
// Run from the aon_timer/ directory on the CentOS tree:
//     xrun -f tb_watchdog_full.f
//     xrun -f tb_watchdog_full.f +define+WDT_AON_DIV=4
//     xrun -f tb_watchdog_full.f +define+WDT_AON_ASYNC
//     xrun -f tb_watchdog_full.f -svseed random
// Code coverage of the IP (add to any of the above):
//     -coverage all -covdut aon_timer -covoverwrite
//     then open the result with: imc -load cov_work/scope/test
//
// Same RTL list as tb_watchdog.f, plus the testbench-only alert receiver
// (tb_files/prim_alert_receiver.sv, unmodified OpenTitan copy).
//
// Paths are relative to the tool's WORKING DIRECTORY, which MUST be aon_timer/.
// Windows repo -> CentOS tree:
//     ips/aon_timer/             -> MALAY_SOC/rtl/aon_timer/
//     SOC_FILES_CENTOS/watchdog/ -> MALAY_SOC/rtl/SOC_FILES/include/watchdog/
//
// Not listed on purpose (pulled in by `include through the +incdir below):
//     prim_assert.sv, prim_assert_*_macros.svh, prim_assert_sec_cm.svh,
//     prim_flop_macros.sv
// =============================================================================

-sv
-timescale 1ns/1ps
-top tb_watchdog_full

+incdir+../SOC_FILES/include/watchdog/prim

// =============================================================================
// Section 1: Packages (dependency order)
// =============================================================================
../SOC_FILES/include/watchdog/prim_abstract/prim_pkg.sv
../SOC_FILES/include/watchdog/prim/prim_util_pkg.sv
../SOC_FILES/include/watchdog/prim/prim_mubi_pkg.sv
../SOC_FILES/include/watchdog/prim/prim_secded_pkg.sv
../SOC_FILES/include/watchdog/prim/prim_subreg_pkg.sv
../SOC_FILES/include/watchdog/prim/prim_alert_pkg.sv
../SOC_FILES/include/watchdog/top_pkg/top_pkg.sv
../SOC_FILES/include/watchdog/tlul/tlul_pkg.sv
../SOC_FILES/include/watchdog/lc_ctrl/lc_ctrl_reg_pkg.sv
../SOC_FILES/include/watchdog/lc_ctrl/lc_ctrl_state_pkg.sv
../SOC_FILES/include/watchdog/lc_ctrl/lc_ctrl_pkg.sv
rtl/aon_timer_reg_pkg.sv

// =============================================================================
// Section 2: Technology primitives + primgen-generated abstract wrappers
// =============================================================================
// prim_abstract/ holds FuseSoC/primgen output (unedited), generated with:
//   python -m fusesoc.main --cores-root hw/ip --cores-root hw/top_earlgrey
//     --cores-root hw/lint --cores-root hw/dv run --setup --target=default
//     --tool=xcelium --build-root build/aon_timer lowrisc:ip:aon_timer
// prim_flop / prim_buf select `PRIM_DEFAULT_IMPL (default prim_pkg::ImplGeneric),
// so the Xilinx variants below are compiled but never instantiated.
../SOC_FILES/include/watchdog/prim_generic/prim_generic_flop.sv
../SOC_FILES/include/watchdog/prim_generic/prim_generic_buf.sv
../SOC_FILES/include/watchdog/prim_generic/prim_generic_flop_2sync.sv
../SOC_FILES/include/watchdog/prim_generic/prim_generic_xnor2.sv
../SOC_FILES/include/watchdog/prim_xilinx/prim_xilinx_flop.sv
../SOC_FILES/include/watchdog/prim_xilinx/prim_xilinx_buf.sv
../SOC_FILES/include/watchdog/prim_xilinx_ultrascale/prim_xilinx_ultrascale_flop.sv
../SOC_FILES/include/watchdog/prim_xilinx_ultrascale/prim_xilinx_ultrascale_buf.sv
../SOC_FILES/include/watchdog/prim_abstract/prim_flop.sv
../SOC_FILES/include/watchdog/prim_abstract/prim_buf.sv
../SOC_FILES/include/watchdog/prim_abstract/prim_flop_2sync.sv
../SOC_FILES/include/watchdog/prim_abstract/prim_xnor2.sv

// =============================================================================
// Section 3: OpenTitan primitives
// =============================================================================
../SOC_FILES/include/watchdog/prim/prim_cdc_rand_delay.sv
../SOC_FILES/include/watchdog/prim/prim_sec_anchor_buf.sv
../SOC_FILES/include/watchdog/prim/prim_sec_anchor_flop.sv
../SOC_FILES/include/watchdog/prim/prim_diff_decode.sv
../SOC_FILES/include/watchdog/prim/prim_alert_sender.sv
../SOC_FILES/include/watchdog/prim/prim_lc_sync.sv
../SOC_FILES/include/watchdog/prim/prim_edge_detector.sv
../SOC_FILES/include/watchdog/prim/prim_intr_hw.sv
../SOC_FILES/include/watchdog/prim/prim_pulse_sync.sv
../SOC_FILES/include/watchdog/prim/prim_sync_reqack.sv
../SOC_FILES/include/watchdog/prim/prim_reg_cdc_arb.sv
../SOC_FILES/include/watchdog/prim/prim_reg_cdc.sv
../SOC_FILES/include/watchdog/prim/prim_onehot_check.sv
../SOC_FILES/include/watchdog/prim/prim_reg_we_check.sv
../SOC_FILES/include/watchdog/prim/prim_secded_inv_39_32_dec.sv
../SOC_FILES/include/watchdog/prim/prim_secded_inv_39_32_enc.sv
../SOC_FILES/include/watchdog/prim/prim_secded_inv_64_57_dec.sv
../SOC_FILES/include/watchdog/prim/prim_secded_inv_64_57_enc.sv
../SOC_FILES/include/watchdog/prim/watchdog_prim_subreg_arb.sv
../SOC_FILES/include/watchdog/prim/watchdog_prim_subreg.sv
../SOC_FILES/include/watchdog/prim/watchdog_prim_subreg_ext.sv

// =============================================================================
// Section 4: TL-UL
// =============================================================================
../SOC_FILES/include/watchdog/tlul/tlul_data_integ_dec.sv
../SOC_FILES/include/watchdog/tlul/tlul_data_integ_enc.sv
../SOC_FILES/include/watchdog/tlul/tlul_cmd_intg_chk.sv
../SOC_FILES/include/watchdog/tlul/tlul_cmd_intg_gen.sv
../SOC_FILES/include/watchdog/tlul/tlul_rsp_intg_gen.sv
../SOC_FILES/include/watchdog/tlul/tlul_err.sv
../SOC_FILES/include/watchdog/tlul/tlul_adapter_reg.sv

// =============================================================================
// Section 5: Watchdog IP (aon_timer)
// =============================================================================
rtl/aon_timer_reg_top.sv
rtl/aon_timer_core.sv
rtl/aon_timer.sv

// =============================================================================
// Section 6: Testbench
// =============================================================================
tb_files/prim_alert_receiver.sv
tb_watchdog_full.sv
