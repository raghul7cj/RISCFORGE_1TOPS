// =============================================================================
// RISCFORGE 1TOPS — SoC Verification Infrastructure Compilation Filelist
// =============================================================================
// Paths are relative to THIS directory (Verification/infrastructure).
//
// NOTE ON TOOL SYNTAX
//   Vivado's xvlog/xelab do NOT understand VCS-style `+incdir+`. Use `-i` for
//   xvlog and `-vlogargs`/`-include` for xelab. The old filelist used
//   `+incdir+` and `-timescale`/`-top`, none of which xvlog 2022.2 accepts, so
//   the file was rejected before a single line was read. The `+incdir+` lines
//   are preserved below as a comment block for the VCS flow; run_vcs.sh passes
//   `-I` flags explicitly instead.
//
// KNOWN BLOCKER — obi_uart IS MISSING FROM THE TREE
//   apb_uart-main/rtl/apb_uart_wrap.sv:63 instantiates `obi_uart`, but no
//   obi_uart.sv / obi_uart_register.sv / obi_uart_baudgen.sv / obi_uart_rx.sv
//   / obi_uart_tx.sv / obi_uart_interrupts.sv / obi_uart_modem.sv exists
//   anywhere in the repository. Until that IP is restored (or apb_uart is
//   re-pointed at reg_uart_wrap.sv), the UART peripheral - and therefore the
//   whole SoC, and therefore soc_tb_top - cannot elaborate. Stages 5, 6 and 7
//   depend on it. Do not spend time debugging stages until this is resolved.
// =============================================================================

+incdir+../../axi_lite_xbar/include/axi
+incdir+../../axi_lite_xbar/include/common_cells
+incdir+../../apb_uart-main/include/apb
+incdir+../../apb_uart-main/include/obi
+incdir+../../apb_uart-main/include/common_cells
+incdir+../../apb_uart-main/include/axi
+incdir+../../apb_uart-main/include/register_interface
+incdir+../../apb_uart-main/include
+incdir+../../register_interface
+incdir+../../apb_i2c-master/rtl
+incdir+tb

// ---- Packages -------------------------------------------------------------
tb/tb_pkg.sv
../../axi_lite_xbar/include/common_cells/cf_math_pkg.sv
../../axi_lite_xbar/include/common_cells/axi_pkg.sv
../../gpio-master/gpio_reg_pkg.sv
../../apb_uart-main/include/apb/apb_pkg.sv
../../apb_uart-main/include/obi/obi_pkg.sv
../../apb_uart-main/include/obi/obi_uart_pkg.sv

// ---- Common cells (only what the xbar/APB bridge actually reference) -------
../../axi_lite_xbar/include/common_cells/addr_decode.sv
../../axi_lite_xbar/include/common_cells/addr_decode_dync.sv
../../axi_lite_xbar/include/common_cells/fall_through_register.sv
../../axi_lite_xbar/include/common_cells/spill_register.sv
../../axi_lite_xbar/include/common_cells/spill_register_flushable.sv
../../axi_lite_xbar/include/common_cells/counter.sv
../../axi_lite_xbar/include/common_cells/rr_arb_tree.sv
../../axi_lite_xbar/include/common_cells/lzc.sv
../../axi_lite_xbar/include/common_cells/onehot_to_bin.sv
../../axi_lite_xbar/include/common_cells/delta_counter.sv
../../axi_lite_xbar/include/common_cells/id_queue.sv
../../axi_lite_xbar/include/common_cells/sync.sv
../../axi_lite_xbar/include/common_cells/stream_register.sv

// ---- AXI infrastructure ---------------------------------------------------
../../axi_lite_xbar/include/axi/axi_err_slv.sv
../../axi_lite_xbar/include/axi/axi_atop_filter.sv
../../axi_lite_xbar/include/axi/axi_lite_to_axi.sv
../../axi_lite_xbar/include/axi/axi_lite_demux.sv
../../axi_lite_xbar/include/axi/axi_lite_mux.sv

// ---- Crossbar + APB bridge + bus timeout monitors -------------------------
../../axi_lite_xbar/axi_lite_xbar.sv
../../axi_lite_to_apb/axi_lite_to_apb.sv
../../bus_monitors/apb_timeout_monitor.sv
../../bus_monitors/axi_lite_timeout_monitor.sv

// ---- Peripherals ----------------------------------------------------------
../../apb_i2c-master/i2c_master_bit_ctrl.sv
../../apb_i2c-master/i2c_master_byte_ctrl.sv
../../apb_i2c-master/apb_i2c.sv

../../apb_timer-master/rtl/timer.sv
../../apb_timer-master/rtl/apb_timer.sv

../../apb_uart-main/include/obi/apb_to_obi.sv
../../apb_uart-main/include/obi/obi_uart_baudgen.sv
../../apb_uart-main/include/obi/obi_uart_rx.sv
../../apb_uart-main/include/obi/obi_uart_tx.sv
../../apb_uart-main/include/obi/obi_uart_interrupts.sv
../../apb_uart-main/include/obi/obi_uart_modem.sv
../../apb_uart-main/include/obi/obi_uart_register.sv
../../apb_uart-main/include/obi/obi_uart.sv
../../apb_uart-main/rtl/apb_uart_wrap.sv
../../apb_uart-main/rtl/apb_uart.sv

../../register_interface/reg_intf.sv
../../register_interface/apb_to_reg.sv
../../register_interface/prim_subreg.sv
../../register_interface/prim_subreg_arb.sv
../../register_interface/prim_subreg_ext.sv

../../gpio-master/gpio_input_stage_no_clk_gates.sv
../../gpio-master/gpio_reg_top.sv
../../gpio-master/gpio.sv
../../gpio-master/gpio_apb_wrap.sv

../../spi_master_ip/spi_master/spi_master_clkgen.sv
../../spi_master_ip/spi_master/spi_master_fifo.sv
../../spi_master_ip/spi_master/spi_master_rx.sv
../../spi_master_ip/spi_master/spi_master_tx.sv
../../spi_master_ip/spi_master/spi_master_controller.sv
../../spi_master_ip/spi_master/spi_master_apb_if.sv
../../spi_master_ip/spi_master/apb_spi_master.sv

// ---- Internal memories ----------------------------------------------------
../../RTL_SOC/sram_sp.sv
../../RTL_SOC/sram_mux.sv
../../RTL_SOC/axi_lite_sram_if.sv
../../instr_module/Instruction_Memory.v
../../RTL_SOC/imem_sram_wrapper.sv
../../RTL_SOC/boot_rom.sv
../../RTL_SOC/instr_fetch_demux.sv

// ---- Core RTL -------------------------------------------------------------
../../riscv_core/rtl/PC.v
../../riscv_core/rtl/PC_Adder.v
../../riscv_core/rtl/Mux2.v
../../riscv_core/rtl/Mux_3_by_1.v
../../riscv_core/rtl/ALU.v
../../riscv_core/rtl/ALU_Decoder.v
../../riscv_core/rtl/Main_Decoder.v
../../riscv_core/rtl/Control_Unit_Top.v
../../riscv_core/rtl/Sign_Extend.v
../../riscv_core/rtl/Register_File.v
../../riscv_core/rtl/JB_unit.v
../../riscv_core/rtl/opcode_check.v

../../riscv_core/rtl/booth_enc.v
../../riscv_core/rtl/csa.v
../../riscv_core/rtl/pp_gen.v
../../riscv_core/rtl/rv32m_mul.v
../../riscv_core/rtl/rv32m_div.v
../../riscv_core/rtl/rv32m_unit.v

../../riscv_core/rtl/irq_gateway.v
../../riscv_core/rtl/irq_arbiter.v
../../riscv_core/rtl/csr_regfile.v
../../riscv_core/rtl/wb_trap_mret_commit_controller.v
../../riscv_core/rtl/hazard_unit.v

../../riscv_core/rtl/imem_controller.v
../../riscv_core/rtl/ls_unit.v

../../riscv_core/rtl/fetch_cycle.v
../../riscv_core/rtl/decode_cycle.v
../../riscv_core/rtl/execute_cycle.v
../../riscv_core/rtl/memory_cycle.v
../../riscv_core/rtl/writeback_cycle.v

../../riscv_core/rtl/top.v
../../riscv_core/rtl/hybrid_mem_interface.sv
../../bootloader/bootloader.sv

// ---- SoC top --------------------------------------------------------------
../../RTL_SOC/riscforge_soc_subsystem.sv

// ---- Verification VIPs ----------------------------------------------------
vip/uart_pin_vip.sv
vip/gpio_pin_vip.sv
vip/i2c_eeprom_at24c02.sv
vip/spi_flash_s25fs512s.sv

// ---- Passive monitor layer ------------------------------------------------
tb/tb_pkg.sv
tb/rf_monitor_if.sv
monitors/rf_monitors.sv
monitors/rf_monitor_env.sv
tb/rf_mon_probe.sv

// ---- Legacy module monitors ----------------------------------------------
monitors/fetch_monitor.sv
monitors/retire_monitor.sv
monitors/lsu_monitor.sv
monitors/axi_lite_monitor.sv
monitors/apb_monitor.sv
monitors/irq_monitor.sv

// ---- Checkers, predictors, blame engine ----------------------------------
checkers/axi_lite_protocol_sva.sv
checkers/apb_protocol_sva.sv
checkers/mmio_path_scoreboard.sv
checkers/register_predictor.sv
checkers/irq_predictor.sv
checkers/failure_reporter.sv

// ---- Testbench top --------------------------------------------------------
tb/soc_tb_top.sv
