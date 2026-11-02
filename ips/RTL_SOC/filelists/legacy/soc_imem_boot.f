// =============================================================================
// RISCFORGE 1TOPS — SoC Instruction Memory Boot-Loading Testbench Filelist
// =============================================================================
// Cadence Xcelium:  xrun -sv -f rtl/soc_imem_boot_tb.f
//
// NOTE: Paths are relative to ips/RTL_SOC/ (run xrun from RTL_SOC/).
//       Adapted for the VLSI CentOS system.
// =============================================================================

-sv
-timescale 1ns/1ps
-access +rwc

// Top module
-top soc_imem_boot_tb

// =============================================================================
// Section 1: Include Paths
// =============================================================================
+incdir+../SOC_FILES/include/axi
+incdir+../SOC_FILES/include/common_cells
+incdir+../SOC_FILES/include
+incdir+../SOC_FILES/include/apb
+incdir+../SOC_FILES/include/obi
+incdir+../apb_i2c-master
+incdir+../spi/spi_master
+incdir+../SOC_FILES/include/register_interface-master

// =============================================================================
// Section 2: Packages
// =============================================================================
../SOC_FILES/include/common_cells/cf_math_pkg.sv
../SOC_FILES/include/common_cells/axi_pkg.sv
../gpio-master/gpio_reg_pkg.sv
../clic-master/clic_pkg.sv
../clic-master/clicint_reg_pkg.sv
../clic-master/clicintv_reg_pkg.sv
../clic-master/clicvs_reg_pkg.sv
../clic-master/mclic_reg_pkg.sv
../SOC_FILES/include/apb/apb_pkg.sv
../SOC_FILES/include/obi/obi_pkg.sv
../SOC_FILES/include/obi/obi_uart_pkg.sv

// =============================================================================
// Section 3: Common Cells
// =============================================================================
../SOC_FILES/include/common_cells/addr_decode_dync.sv
../SOC_FILES/include/common_cells/addr_decode.sv
../SOC_FILES/include/common_cells/fifo_v3.sv
../SOC_FILES/include/common_cells/fall_through_register.sv
../SOC_FILES/include/common_cells/spill_register.sv
../SOC_FILES/include/common_cells/spill_register_flushable.sv
../SOC_FILES/include/common_cells/counter.sv
../SOC_FILES/include/common_cells/rr_arb_tree.sv
../SOC_FILES/include/common_cells/lzc.sv
../SOC_FILES/include/common_cells/onehot_to_bin.sv
../SOC_FILES/include/common_cells/delta_counter.sv
../SOC_FILES/include/common_cells/id_queue.sv
../SOC_FILES/include/common_cells/sync.sv

// =============================================================================
// Section 4: AXI Infrastructure
// =============================================================================
../axi_lite_xbar/include/axi/axi_err_slv.sv
../axi_lite_xbar/include/axi/axi_atop_filter.sv
../axi_lite_xbar/include/axi/axi_lite_to_axi.sv
../axi_lite_xbar/include/axi/axi_lite_demux.sv
../axi_lite_xbar/include/axi/axi_lite_mux.sv

// =============================================================================
// Section 5: AXI-Lite Crossbar
// =============================================================================
../axi_lite_xbar/axi_lite_xbar.sv

// =============================================================================
// Section 6: AXI-Lite → APB Bridge
// =============================================================================
../axi_lite_to_apb/rtl/axi_lite_to_apb.sv

// =============================================================================
// Section 7: APB I2C Master
// =============================================================================
../apb_i2c-master/i2c_master_bit_ctrl.sv
../apb_i2c-master/i2c_master_byte_ctrl.sv
../apb_i2c-master/apb_i2c.sv

// =============================================================================
// Section 8: APB Timer
// =============================================================================
../apb_timer/apb_timer/timer.sv
../apb_timer/apb_timer/apb_timer.sv

// =============================================================================
// Section 9: APB UART + OBI UART
// =============================================================================
../SOC_FILES/include/obi/apb_to_obi.sv
../SOC_FILES/include/obi/obi_uart_baudgen.sv
../SOC_FILES/include/obi/obi_uart_rx.sv
../SOC_FILES/include/obi/obi_uart_tx.sv
../SOC_FILES/include/obi/obi_uart_interrupts.sv
../SOC_FILES/include/obi/obi_uart_modem.sv
../SOC_FILES/include/obi/obi_uart_register.sv
../SOC_FILES/include/obi/obi_uart.sv
../apb_uart-main/rtl/apb_uart_wrap.sv
../apb_uart-main/rtl/apb_uart.sv

// =============================================================================
// Section 10: Register Interface (PULP Platform)
// =============================================================================
../SOC_FILES/include/register_interface-master/reg_intf.sv
../SOC_FILES/include/register_interface-master/apb_to_reg.sv
../SOC_FILES/include/register_interface-master/apb_to_reg_v2.sv
../SOC_FILES/include/register_interface-master/periph_to_reg.sv
../SOC_FILES/include/register_interface-master/prim_subreg.sv
../SOC_FILES/include/register_interface-master/prim_subreg_ext.sv
../SOC_FILES/include/register_interface-master/prim_subreg_arb.sv

// =============================================================================
// Section 11: GPIO
// =============================================================================
../gpio-master/gpio_input_stage_no_clk_gates.sv
../gpio-master/gpio_reg_top.sv
../gpio-master/gpio.sv
../gpio-master/gpio_apb_wrap.sv

// =============================================================================
// Section 12: CLIC
// =============================================================================
../clic-master/clicint_reg_top.sv
../clic-master/clicintv_reg_top.sv
../clic-master/clicvs_reg_top.sv
../clic-master/mclic_reg_top.sv
../clic-master/clic_reg_adapter.sv
../clic-master/clic_gateway.sv
../clic-master/clic_target.sv
../clic-master/clic.sv
../clic-master/clic_apb.sv

// =============================================================================
// Section 13: APB SPI Master
// =============================================================================
../spi/spi_master/spi_master_clkgen.sv
../spi/spi_master/spi_master_fifo.sv
../spi/spi_master/spi_master_rx.sv
../spi/spi_master/spi_master_tx.sv
../spi/spi_master/spi_master_controller.sv
../spi/spi_master/spi_master_apb_if.sv
../spi/spi_master/apb_spi_master.sv

// =============================================================================
// Section 14: SPI Flash Model (Infineon S25FS512S)
// =============================================================================
../spi_slave_infinion/S25fs512s/model/s25fs512s.sv

// =============================================================================
// Section 15: SoC Internal Memory Modules
// =============================================================================
rtl/sram_sp.sv
rtl/sram_mux.sv
rtl/axi_lite_sram_if.sv
../instr_module/Instruction_Memory.v
rtl/imem_sram_wrapper.sv

// =============================================================================
// Section 16: Stub IPs and Real Bootloader
// =============================================================================
rtl/riscv_core_stub.sv
../bootloader/rtl/bootloader.sv

// =============================================================================
// Section 17: SoC Subsystem Top-Level
// =============================================================================
rtl/riscforge_soc_subsystem.sv

// =============================================================================
// Section 18: Testbench
// =============================================================================
rtl/soc_imem_boot_tb.sv
