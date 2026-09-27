// =============================================================================
// RISCFORGE 1TOPS — SoC Subsystem Compilation Filelist
// =============================================================================
// Cadence Xcelium:  xrun    -f rtl/soc_subsystem.f
// Cadence Genus:    read_hdl -sv -f rtl/soc_subsystem.f
//
// PATHS TARGET THE VLSI CentOS TREE (/home/iiita/MALAY_SOC/rtl/).
// They are relative to the tool's WORKING DIRECTORY, which MUST be RTL_SOC/ —
// not to the location of this file. So:
//     rtl/<file>      -> RTL_SOC/rtl/<file>
//     ../<dir>/<file> -> MALAY_SOC/rtl/<dir>/<file>
//
// This is the design-only list (no flash model, no testbench). It is kept in
// sync with rtl/soc_timer0_boot_run.f, which is the same list plus the vendor
// SPI flash model and the boot-to-runtime testbench. Every path below is one
// that soc_timer0_boot_run.f has already compiled successfully on this tree.
//
// Layout notes for this tree:
//     common_cells + AXI infra   -> ../axi_lite_xbar/include/
//     apb / obi / register_iface -> ../SOC_FILES/include/
//     UART wrappers              -> ../uart/rtl/
//     SPI master                 -> ../spi/spi_master/
//     APB timer                  -> ../apb_timer/apb_timer/
//     apb_i2c, axi_lite_to_apb, bootloader -> have an rtl/ subdirectory
// =============================================================================

-sv
-timescale 1ns/1ps

// Top module
-top riscforge_soc_subsystem

// =============================================================================
// Section 1: Include Paths (for `include directives in IP source files)
// =============================================================================
// The `include directives name their containing directory, e.g.
//   "register_interface/typedef.svh", "common_cells/registers.svh",
//   "apb/typedef.svh"
// so ../SOC_FILES/include (the PARENT) must be on the path as well as the
// individual leaf directories.
+incdir+../axi_lite_xbar/include/axi
+incdir+../axi_lite_xbar/include/common_cells
+incdir+../axi_lite_xbar/include
+incdir+../SOC_FILES/include/apb
+incdir+../SOC_FILES/include/obi
+incdir+../SOC_FILES/include/common_cells
+incdir+../SOC_FILES/include/axi
+incdir+../SOC_FILES/include

// I2C and SPI master local includes
+incdir+../apb_i2c-master/rtl
+incdir+../spi/spi_master

// =============================================================================
// Section 2: Packages (compile order matters — packages before modules)
// =============================================================================

// Common math functions
../axi_lite_xbar/include/common_cells/cf_math_pkg.sv

// AXI package (xbar_cfg_t, resp_t, prot_t, RESP_OKAY, etc.)
../axi_lite_xbar/include/common_cells/axi_pkg.sv

// GPIO register package (GPIOCount, reg2hw/hw2reg structs)
../gpio-master/gpio_reg_pkg.sv

// APB package (apb_to_reg / gpio_apb_wrap)
../SOC_FILES/include/apb/apb_pkg.sv

// OBI packages (needed by apb_uart -> apb_uart_wrap -> apb_to_obi -> obi_uart)
../SOC_FILES/include/obi/obi_pkg.sv
../SOC_FILES/include/obi/obi_uart_pkg.sv

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
../axi_lite_xbar/include/common_cells/sync.sv
../axi_lite_xbar/include/common_cells/stream_register.sv

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
// Section 6: AXI-Lite -> APB Bridge
// =============================================================================
../axi_lite_to_apb/rtl/axi_lite_to_apb.sv

// =============================================================================
// Section 6b: Bus Timeout Monitors
// NOTE: apb_timeout_monitor is interposed on the APB response path only;
//       axi_lite_timeout_monitor sits on the core's AXI-Lite master port.
// =============================================================================
../bus_monitors/apb_timeout_monitor.sv
../bus_monitors/axi_lite_timeout_monitor.sv

// =============================================================================
// Section 7: APB I2C Master
// NOTE: i2c_master_defines.sv is `included by apb_i2c.sv (resolved via +incdir)
// =============================================================================
../apb_i2c-master/rtl/i2c_master_bit_ctrl.sv
../apb_i2c-master/rtl/i2c_master_byte_ctrl.sv
../apb_i2c-master/rtl/apb_i2c.sv

// =============================================================================
// Section 8: APB Timer (used by both Timer 0 and Timer 1 instances)
// =============================================================================
../apb_timer/apb_timer/timer.sv
../apb_timer/apb_timer/apb_timer.sv

// =============================================================================
// Section 9: APB UART
// Dependency chain: apb_uart -> apb_uart_wrap -> apb_to_obi -> obi_uart
// =============================================================================
// OBI infrastructure
../SOC_FILES/include/obi/apb_to_obi.sv

// OBI UART core + sub-modules
../SOC_FILES/include/obi/obi_uart_baudgen.sv
../SOC_FILES/include/obi/obi_uart_rx.sv
../SOC_FILES/include/obi/obi_uart_tx.sv
../SOC_FILES/include/obi/obi_uart_interrupts.sv
../SOC_FILES/include/obi/obi_uart_modem.sv
../SOC_FILES/include/obi/obi_uart_register.sv
../SOC_FILES/include/obi/obi_uart.sv

// UART wrappers
../uart/rtl/apb_uart_wrap.sv
../uart/rtl/apb_uart.sv

// =============================================================================
// Section 10: GPIO
// gpio_apb_wrap needs the PULP register_interface (REG_BUS, apb_to_reg).
// =============================================================================
../SOC_FILES/include/register_interface/reg_intf.sv
../SOC_FILES/include/register_interface/apb_to_reg.sv
../SOC_FILES/include/register_interface/prim_subreg_arb.sv
../SOC_FILES/include/register_interface/prim_subreg.sv
../SOC_FILES/include/register_interface/prim_subreg_ext.sv

// NOTE: the _no_clk_gates variant declares the SAME module name
// (gpio_input_stage) but drops the tc_clk_gating dependency, which no
// technology cell library is bound in this flow to provide.
../gpio-master/gpio_input_stage_no_clk_gates.sv
../gpio-master/gpio_reg_top.sv
../gpio-master/gpio.sv
../gpio-master/gpio_apb_wrap.sv

// =============================================================================
// Section 11: APB SPI Master
// NOTE: spi_master_apb_if.sv redefines the REG_STATUS macro that apb_i2c.sv
//       also defines (xmvlog *W,MACRDF). Harmless — each uses its own value
//       within its own file — but it is why that warning appears.
// =============================================================================
../spi/spi_master/spi_master_clkgen.sv
../spi/spi_master/spi_master_fifo.sv
../spi/spi_master/spi_master_rx.sv
../spi/spi_master/spi_master_tx.sv
../spi/spi_master/spi_master_controller.sv
../spi/spi_master/spi_master_apb_if.sv
../spi/spi_master/apb_spi_master.sv

// =============================================================================
// Section 12: SoC Internal Memory Modules
// =============================================================================
rtl/sram_sp.sv
rtl/sram_mux.sv
rtl/axi_lite_sram_if.sv
../instr_module/Instruction_Memory.v
rtl/imem_sram_wrapper.sv
rtl/boot_rom.sv
rtl/instr_fetch_demux.sv

// =============================================================================
// Section 13: RISC-V Core (RV32IM, 5-stage) + Bootloader
// =============================================================================
// NOTE: ../riscv_core/rtl/axi_pkg.sv is deliberately NOT listed. It declares the
//       same package name as the common_cells axi_pkg compiled in Section 2;
//       compiling both is a duplicate-package error. It exists so the core can
//       be simulated standalone, outside this filelist.

// Leaf / combinational blocks
../riscv_core/rtl/PC.v
../riscv_core/rtl/PC_Adder.v
../riscv_core/rtl/Mux2.v
../riscv_core/rtl/Mux_3_by_1.v
../riscv_core/rtl/ALU.v
../riscv_core/rtl/ALU_Decoder.v
../riscv_core/rtl/Main_Decoder.v
../riscv_core/rtl/Control_Unit_Top.v
../riscv_core/rtl/Sign_Extend.v
../riscv_core/rtl/Register_File.v
../riscv_core/rtl/JB_unit.v
../riscv_core/rtl/opcode_check.v

// M-extension (multiply / divide)
../riscv_core/rtl/booth_enc.v
../riscv_core/rtl/csa.v
../riscv_core/rtl/pp_gen.v
../riscv_core/rtl/rv32m_mul.v
../riscv_core/rtl/rv32m_div.v
../riscv_core/rtl/rv32m_unit.v

// CSR / trap / hazard control
../riscv_core/rtl/csr_regfile.v
../riscv_core/rtl/wb_trap_mret_commit_controller.v
../riscv_core/rtl/hazard_unit.v

// Memory-side helpers (instantiated inside the pipeline stages)
../riscv_core/rtl/imem_controller.v
../riscv_core/rtl/ls_unit.v

// Pipeline stages
../riscv_core/rtl/fetch_cycle.v
../riscv_core/rtl/decode_cycle.v
../riscv_core/rtl/execute_cycle.v
../riscv_core/rtl/memory_cycle.v
../riscv_core/rtl/writeback_cycle.v

// Core top
../riscv_core/rtl/top.v

// Data-memory router (DSRAM direct / MMIO over AXI-Lite)
../riscv_core/rtl/hybrid_mem_interface.sv

// Bootloader
../bootloader/rtl/bootloader.sv

// =============================================================================
// Section 14: SoC Subsystem Top-Level
// =============================================================================
rtl/riscforge_soc_subsystem.sv
