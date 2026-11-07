// =============================================================================
// RISCFORGE 1TOPS - Vivado sources for the WINDOWS checkout
// =============================================================================
// Same files and order as filelists/inc.f + ip.f (+ core.f, soc_rtl.f), with
// the IP paths of this Windows tree, which differs from the Linux tree the
// Xcelium filelists were written for:
//     Linux (filelists/ip.f)          Windows (here)
//     SOC_FILES/include/<x>           SOC_FILES_CENTOS/<x>
//     gpio-master/rtl/                gpio-master/
//     apb_i2c-master/rtl/             apb_i2c-master/
//     apb_timer/apb_timer/            apb_timer-master/rtl/
//     axi_lite_to_apb/rtl/            axi_lite_to_apb/
//     uart/rtl/                       apb_uart-main/rtl/
//     spi/spi_master/                 spi_master_ip/spi_master/
//     bootloader/rtl/                 bootloader/
// Used by build.tcl on Windows. Paths are relative to ips/RTL_SOC/sim/ like
// the shared filelists. core.f and soc_rtl.f resolve in both trees as-is.
// =============================================================================

// ---- include paths (inc.f) ----
+incdir+../../axi_lite_xbar/include/axi
+incdir+../../axi_lite_xbar/include/common_cells
+incdir+../../axi_lite_xbar/include
+incdir+../../../SOC_FILES_CENTOS/apb
+incdir+../../../SOC_FILES_CENTOS/obi
+incdir+../../../SOC_FILES_CENTOS/common_cells
+incdir+../../../SOC_FILES_CENTOS/axi
+incdir+../../../SOC_FILES_CENTOS
+incdir+../../apb_i2c-master
+incdir+../../spi_master_ip/spi_master

// ---- Section 1: packages ----
../../axi_lite_xbar/include/common_cells/cf_math_pkg.sv
../../axi_lite_xbar/include/common_cells/axi_pkg.sv
../../gpio-master/gpio_reg_pkg.sv
../../../SOC_FILES_CENTOS/apb/apb_pkg.sv
../../../SOC_FILES_CENTOS/obi/obi_pkg.sv
../../../SOC_FILES_CENTOS/obi/obi_uart_pkg.sv

// ---- Section 2: common cells ----
../../axi_lite_xbar/include/common_cells/addr_decode_dync.sv
../../axi_lite_xbar/include/common_cells/addr_decode.sv
../../axi_lite_xbar/include/common_cells/fifo_v3.sv
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

// ---- Section 3/4: AXI infrastructure + crossbar ----
../../axi_lite_xbar/include/axi/axi_err_slv.sv
../../axi_lite_xbar/include/axi/axi_atop_filter.sv
../../axi_lite_xbar/include/axi/axi_lite_to_axi.sv
../../axi_lite_xbar/include/axi/axi_lite_demux.sv
../../axi_lite_xbar/include/axi/axi_lite_mux.sv
../../axi_lite_xbar/axi_lite_xbar.sv

// ---- Section 5: AXI-Lite -> APB ----
../../axi_lite_to_apb/axi_lite_to_apb.sv

// ---- Section 6: bus timeout monitors ----
../../bus_monitors/apb_timeout_monitor.sv
../../bus_monitors/axi_lite_timeout_monitor.sv

// ---- Section 7: I2C ----
../../apb_i2c-master/i2c_master_bit_ctrl.sv
../../apb_i2c-master/i2c_master_byte_ctrl.sv
../../apb_i2c-master/apb_i2c.sv

// ---- Section 8: timer ----
../../apb_timer-master/rtl/timer.sv
../../apb_timer-master/rtl/apb_timer.sv

// ---- Section 9: UART ----
../../../SOC_FILES_CENTOS/obi/apb_to_obi.sv
../../../SOC_FILES_CENTOS/obi/obi_uart_baudgen.sv
../../../SOC_FILES_CENTOS/obi/obi_uart_rx.sv
../../../SOC_FILES_CENTOS/obi/obi_uart_tx.sv
../../../SOC_FILES_CENTOS/obi/obi_uart_interrupts.sv
../../../SOC_FILES_CENTOS/obi/obi_uart_modem.sv
../../../SOC_FILES_CENTOS/obi/obi_uart_register.sv
../../../SOC_FILES_CENTOS/obi/obi_uart.sv
../../apb_uart-main/rtl/apb_uart_wrap.sv
../../apb_uart-main/rtl/apb_uart.sv

// ---- Section 10: GPIO ----
../../../SOC_FILES_CENTOS/register_interface/reg_intf.sv
../../../SOC_FILES_CENTOS/register_interface/apb_to_reg.sv
../../../SOC_FILES_CENTOS/register_interface/prim_subreg_arb.sv
../../../SOC_FILES_CENTOS/register_interface/prim_subreg.sv
../../../SOC_FILES_CENTOS/register_interface/prim_subreg_ext.sv
../../gpio-master/gpio_input_stage_no_clk_gates.sv
../../gpio-master/gpio_reg_top.sv
../../gpio-master/gpio.sv
../../gpio-master/gpio_apb_wrap.sv

// ---- Section 11: SPI master ----
../../spi_master_ip/spi_master/spi_master_clkgen.sv
../../spi_master_ip/spi_master/spi_master_fifo.sv
../../spi_master_ip/spi_master/spi_master_rx.sv
../../spi_master_ip/spi_master/spi_master_tx.sv
../../spi_master_ip/spi_master/spi_master_controller.sv
../../spi_master_ip/spi_master/spi_master_apb_if.sv
../../spi_master_ip/spi_master/apb_spi_master.sv

// ---- Section 12/13: instruction memory, bootloader ----
../../instr_module/Instruction_Memory.v
../../bootloader/bootloader.sv

// ---- core and SoC RTL (shared filelists, same paths on both trees) ----
-f ../filelists/core.f
-f ../filelists/soc_rtl.f
