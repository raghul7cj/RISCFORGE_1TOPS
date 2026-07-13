// =============================================================================
// RISCFORGE 1TOPS — SoC Subsystem Compilation Filelist
// =============================================================================
// Cadence Xcelium:  xrun -sv -f soc_subsystem.f
// Cadence Genus:    read_hdl -sv -f soc_subsystem.f
// Cadence Tempus:   (use the netlist post-synthesis)
//
// NOTE: Paths are relative to ips/RTL_SOC/.
//       Adjust the base path (IP_ROOT) for your environment.
// =============================================================================

-sv
-timescale 1ns/1ps

// Top module
-top riscforge_soc_subsystem

// =============================================================================
// Section 1: Include Paths (for `include directives in IP source files)
// =============================================================================
+incdir+../axi_lite_xbar/include/axi
+incdir+../axi_lite_xbar/include/common_cells
+incdir+../axi_lite_xbar/include
+incdir+../apb_uart-main/include/apb
+incdir+../apb_uart-main/include/obi
+incdir+../apb_uart-main/include/common_cells
+incdir+../apb_uart-main/include/axi
+incdir+../apb_uart-main/include

// I2C and SPI master local includes
+incdir+../apb_i2c-master
+incdir+../spi_master_ip/spi_master

// TODO: The following include paths require the 'register_interface' package
//       from PULP Platform (https://github.com/pulp-platform/register_interface).
//       Obtain and place it, then uncomment and update the path below.
// +incdir+<path_to>/register_interface/include

// =============================================================================
// Section 2: Packages (compile order matters — packages before modules)
// =============================================================================

// Common math functions
../axi_lite_xbar/include/common_cells/cf_math_pkg.sv

// AXI package (xbar_cfg_t, resp_t, prot_t, etc.)
../axi_lite_xbar/include/common_cells/axi_pkg.sv

// GPIO register package (GPIOCount, reg2hw/hw2reg structs)
../gpio-master/src/gpio_reg_pkg.sv

// CLIC packages
../clic-master/src/clic_pkg.sv
../clic-master/src/clicint_reg_pkg.sv
../clic-master/src/clicintv_reg_pkg.sv
../clic-master/src/clicvs_reg_pkg.sv
../clic-master/src/mclic_reg_pkg.sv

// OBI package (needed by apb_uart → apb_uart_wrap → apb_to_obi)
../apb_uart-main/include/obi/obi_pkg.sv

// =============================================================================
// Section 3: Common Cells (shared infrastructure modules)
// =============================================================================
../axi_lite_xbar/include/common_cells/addr_decode_dync.sv
../axi_lite_xbar/include/common_cells/addr_decode.sv
../axi_lite_xbar/include/common_cells/fifo_v3.sv
../axi_lite_xbar/include/common_cells/fall_through_register.sv
../axi_lite_xbar/include/common_cells/spill_register.sv
../axi_lite_xbar/include/common_cells/spill_register_flushable.sv
../axi_lite_xbar/include/common_cells/counter.sv
../axi_lite_xbar/include/common_cells/rr_arb_tree.sv
../axi_lite_xbar/include/common_cells/lzc.sv
../axi_lite_xbar/include/common_cells/onehot_to_bin.sv
../axi_lite_xbar/include/common_cells/delta_counter.sv
../axi_lite_xbar/include/common_cells/id_queue.sv

// =============================================================================
// Section 4: AXI Infrastructure Modules (crossbar dependencies)
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
../axi_lite_to_apb/axi_lite_to_apb.sv

// =============================================================================
// Section 7: APB I2C Master
// NOTE: i2c_master_defines.sv is `included by apb_i2c.sv (resolved via +incdir)
// =============================================================================
../apb_i2c-master/i2c_master_bit_ctrl.sv
../apb_i2c-master/i2c_master_byte_ctrl.sv
../apb_i2c-master/apb_i2c.sv

// =============================================================================
// Section 8: APB Timer
// =============================================================================
../apb_timer-master/src/timer.sv
../apb_timer-master/src/apb_timer.sv

// =============================================================================
// Section 9: APB UART
// NOTE: The UART has a dependency chain:
//   apb_uart → apb_uart_wrap → apb_to_obi → obi_uart
//   These modules are in apb_uart-main/include/obi/ and apb_uart-main/rtl/
//   The obi_uart module may require additional OBI sub-modules.
// =============================================================================
// OBI infrastructure (from apb_uart-main/include/obi/)
../apb_uart-main/include/obi/apb_to_obi.sv

// TODO: obi_uart is an external dependency. Obtain from PULP Platform and add:
// <path_to>/obi_uart.sv

// UART wrappers
../apb_uart-main/rtl/apb_uart_wrap.sv
../apb_uart-main/rtl/apb_uart.sv

// =============================================================================
// Section 10: GPIO
// NOTE: gpio_apb_wrap depends on 'register_interface' package for:
//   - apb_to_reg module
//   - REG_BUS interface
//   Obtain from https://github.com/pulp-platform/register_interface
// =============================================================================
// TODO: Uncomment and set path when register_interface is available:
// <path_to>/register_interface/src/apb_to_reg.sv
// <path_to>/register_interface/src/reg_intf.sv

../gpio-master/src/gpio_input_stage.sv
../gpio-master/src/gpio_reg_top.sv
../gpio-master/src/gpio.sv
../gpio-master/src/gpio_apb_wrap.sv

// =============================================================================
// Section 11: CLIC (Core-Local Interrupt Controller)
// NOTE: clic_apb depends on 'register_interface' package for:
//   - apb_to_reg module
//   - REG_BUS interface
//   - REG_BUS_TYPEDEF_REQ / REG_BUS_TYPEDEF_RSP macros
// =============================================================================
// TODO: Uncomment and set path when register_interface is available:
// <path_to>/register_interface/src/apb_to_reg.sv   (if not already compiled above)
// <path_to>/register_interface/src/reg_intf.sv      (if not already compiled above)

../clic-master/src/clicint_reg_top.sv
../clic-master/src/clicintv_reg_top.sv
../clic-master/src/clicvs_reg_top.sv
../clic-master/src/mclic_reg_top.sv
../clic-master/src/clic_reg_adapter.sv
../clic-master/src/clic_gateway.sv
../clic-master/src/clic_target.sv
../clic-master/src/clic.sv
../clic-master/src/clic_apb.sv

// =============================================================================
// Section 12: APB SPI Master
// =============================================================================
../spi_master_ip/spi_master/spi_master_clkgen.sv
../spi_master_ip/spi_master/spi_master_fifo.sv
../spi_master_ip/spi_master/spi_master_rx.sv
../spi_master_ip/spi_master/spi_master_tx.sv
../spi_master_ip/spi_master/spi_master_controller.sv
../spi_master_ip/spi_master/spi_master_apb_if.sv
../spi_master_ip/spi_master/apb_spi_master.sv

// =============================================================================
// Section 13: SoC Internal Memory Modules
// =============================================================================
sram_sp.sv
sram_mux.sv
axi_lite_sram_if.sv

// =============================================================================
// Section 14: Stub IPs (hollow — to be replaced later)
// =============================================================================
riscv_core_stub.sv
bootloader_stub.sv

// =============================================================================
// Section 15: SoC Subsystem Top-Level
// =============================================================================
riscforge_soc_subsystem.sv
