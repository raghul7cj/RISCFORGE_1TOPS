// =============================================================================
// RISCFORGE 1TOPS - IP sources (everything outside RTL_SOC except the core)
// =============================================================================
// All paths are relative to the run directory ips/RTL_SOC/sim/.
// Pulled in by ../run.f. Packages are listed first - compile order matters.
// =============================================================================

// =============================================================================
// Section 1: Packages
// =============================================================================

// Common math functions
../../axi_lite_xbar/include/common_cells/cf_math_pkg.sv

// AXI package (xbar_cfg_t, resp_t, prot_t, etc.)
// NOTE: ../../riscv_core/rtl/axi_pkg.sv is deliberately NOT listed anywhere.
//       It is a copy of this package with the same name; compiling both is a
//       duplicate-package error. It exists so the core can be simulated
//       standalone, outside these filelists.
../../axi_lite_xbar/include/common_cells/axi_pkg.sv

// GPIO register package (GPIOCount, reg2hw/hw2reg structs)
../../gpio-master/rtl/gpio_reg_pkg.sv

// APB package (apb_to_reg / gpio_apb_wrap)
../../SOC_FILES/include/apb/apb_pkg.sv

// OBI packages (needed by apb_uart -> apb_uart_wrap -> apb_to_obi -> obi_uart)
// NOTE: compile exactly ONE copy of obi_pkg - same package name.
../../SOC_FILES/include/obi/obi_pkg.sv
../../SOC_FILES/include/obi/obi_uart_pkg.sv

// =============================================================================
// Section 2: Common Cells (shared infrastructure modules)
// =============================================================================
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

// =============================================================================
// Section 3: AXI Infrastructure Modules (crossbar dependencies)
// =============================================================================
../../axi_lite_xbar/include/axi/axi_err_slv.sv
../../axi_lite_xbar/include/axi/axi_atop_filter.sv
../../axi_lite_xbar/include/axi/axi_lite_to_axi.sv
../../axi_lite_xbar/include/axi/axi_lite_demux.sv
../../axi_lite_xbar/include/axi/axi_lite_mux.sv

// =============================================================================
// Section 4: AXI-Lite Crossbar
// =============================================================================
../../axi_lite_xbar/axi_lite_xbar.sv

// =============================================================================
// Section 5: AXI-Lite -> APB Bridge
// =============================================================================
../../axi_lite_to_apb/rtl/axi_lite_to_apb.sv

// =============================================================================
// Section 6: Bus Timeout Monitors
// NOTE: riscforge_soc_subsystem instantiates one apb_timeout_monitor per APB
//       slot and one axi_lite_timeout_monitor on the core's master port, so
//       they are required for elaboration in every test. soc_montest_tb is the
//       bench that exercises them.
// =============================================================================
../../bus_monitors/apb_timeout_monitor.sv
../../bus_monitors/axi_lite_timeout_monitor.sv

// =============================================================================
// Section 7: APB I2C Master
// NOTE: i2c_master_defines.sv is `included by apb_i2c.sv (resolved via inc.f)
// =============================================================================
../../apb_i2c-master/rtl/i2c_master_bit_ctrl.sv
../../apb_i2c-master/rtl/i2c_master_byte_ctrl.sv
../../apb_i2c-master/rtl/apb_i2c.sv

// =============================================================================
// Section 8: APB Timer (used by both Timer 0 and Timer 1 instances)
// =============================================================================
../../apb_timer/apb_timer/timer.sv
../../apb_timer/apb_timer/apb_timer.sv

// =============================================================================
// Section 9: APB UART
// NOTE: dependency chain apb_uart -> apb_uart_wrap -> apb_to_obi -> obi_uart
// =============================================================================
// OBI infrastructure
../../SOC_FILES/include/obi/apb_to_obi.sv

// OBI UART core + sub-modules
../../SOC_FILES/include/obi/obi_uart_baudgen.sv
../../SOC_FILES/include/obi/obi_uart_rx.sv
../../SOC_FILES/include/obi/obi_uart_tx.sv
../../SOC_FILES/include/obi/obi_uart_interrupts.sv
../../SOC_FILES/include/obi/obi_uart_modem.sv
../../SOC_FILES/include/obi/obi_uart_register.sv
../../SOC_FILES/include/obi/obi_uart.sv

// UART wrappers
../../uart/rtl/apb_uart_wrap.sv
../../uart/rtl/apb_uart.sv

// =============================================================================
// Section 10: GPIO
// NOTE: gpio_apb_wrap depends on PULP register_interface (REG_BUS, apb_to_reg)
// =============================================================================
../../SOC_FILES/include/register_interface/reg_intf.sv
../../SOC_FILES/include/register_interface/apb_to_reg.sv
../../SOC_FILES/include/register_interface/prim_subreg_arb.sv
../../SOC_FILES/include/register_interface/prim_subreg.sv
../../SOC_FILES/include/register_interface/prim_subreg_ext.sv

// NOTE: the _no_clk_gates variant declares the SAME module name
// (gpio_input_stage) but drops the tc_clk_gating dependency, which no
// technology cell library is bound in this flow to provide.
../../gpio-master/rtl/gpio_input_stage_no_clk_gates.sv
../../gpio-master/rtl/gpio_reg_top.sv
../../gpio-master/rtl/gpio.sv
../../gpio-master/rtl/gpio_apb_wrap.sv

// =============================================================================
// Section 11: APB SPI Master
// =============================================================================
../../spi/spi_master/spi_master_clkgen.sv
../../spi/spi_master/spi_master_fifo.sv
../../spi/spi_master/spi_master_rx.sv
../../spi/spi_master/spi_master_tx.sv
../../spi/spi_master/spi_master_controller.sv
../../spi/spi_master/spi_master_apb_if.sv
../../spi/spi_master/apb_spi_master.sv

// =============================================================================
// Section 12: Instruction memory macro (wrapped by rtl/imem_sram_wrapper.sv)
// =============================================================================
../../instr_module/Instruction_Memory.v

// =============================================================================
// Section 13: Bootloader
// =============================================================================
../../bootloader/rtl/bootloader.sv
