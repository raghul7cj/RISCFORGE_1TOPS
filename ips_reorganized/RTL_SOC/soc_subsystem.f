// =============================================================================
// RISCFORGE 1TOPS — SoC Subsystem Compilation Filelist (DESIGN ONLY, no TB)
// =============================================================================
// Cadence Xcelium:  xrun    -sv -timescale 1ns/1ps -f RTL_SOC/soc_subsystem.f \
//                            -top riscforge_soc_subsystem
// Cadence Genus:    read_hdl -sv -f RTL_SOC/soc_subsystem.f
// Synopsys VCS:     vcs -sverilog -full64 -timescale=1ns/1ps \
//                       -f RTL_SOC/soc_subsystem.f -top riscforge_soc_subsystem
// AMD Vivado XSim:  xvlog --sv -f RTL_SOC/soc_subsystem.f
//
// -----------------------------------------------------------------------------
// PATHS ARE RELATIVE TO THE TOOL'S WORKING DIRECTORY, which is why every entry
// below is written relative to the REPOSITORY ROOT and the runners must be
// invoked from there. This is the defect that broke the previous revision of
// this list: it used `../<dir>/<file>` assuming the working directory was
// RTL_SOC/ AND that the tree was the remote one at
// /home/iiita/MALAY_SOC/rtl/. Neither holds here, so every path missed.
//
// The layout differences that were corrected:
//
//   remote MALAY_SOC/rtl/           this repo (rtl/ips/)        remap applied
//   ------------------------        ---------------------       -------------------------
//   RTL_SOC/rtl/<f>.sv              RTL_SOC/<f>.sv             dropped the rtl/ level
//   SOC_FILES/include/apb           apb_uart-main/include/apb
//   SOC_FILES/include/obi           apb_uart-main/include/obi
//   SOC_FILES/include/common_cells  apb_uart-main/include/common_cells
//   SOC_FILES/include/axi           apb_uart-main/include/axi
//   uart/rtl/apb_uart.sv            apb_uart-main/rtl/apb_uart.sv
//   spi/spi_master/                 spi_master_ip/spi_master/
//   apb_timer/apb_timer/            apb_timer-master/rtl/
//   apb_i2c-master/rtl/             apb_i2c-master/
//   axi_lite_to_apb/rtl/            axi_lite_to_apb/
//   bootloader/rtl/bootloader.sv    bootloader/bootloader.sv
//   axi_lite_xbar/ riscv_core/rtl/  unchanged
//   gpio-master/ bus_monitors/ instr_module/   unchanged
//
// The OBI UART chain that the previous revision listed
// (apb_uart_wrap -> apb_to_obi -> obi_uart{,_rx,_tx,_modem,_register,
// _interrupts,_baudgen} + obi_uart_pkg) has been REMOVED. The SoC instantiates
// `apb_uart` directly, apb_uart.sv is self-contained with no
// sub-instantiations, and those obi_uart sources are absent from this
// repository. Omitting the whole chain is verified: the remaining list compiles
// clean in AMD Vivado XSim 2022.2.
//
// NOTE: this file is the design-only convenience list for lint/synthesis. The
// testbench compile list is NOT maintained here -- it lives in the canonical
// manifest Verification/infrastructure/rf_filelist.txt and is emitted per tool
// by Verification/infrastructure/gen_filelists.py. Keeping one authoritative
// list per concern avoids the drift that produced this rewrite.
//
// The `include directives inside the IP sources name their containing directory
// (e.g. "apb/typedef.svh", "axi/assign.svh", "common_cells/registers.svh"), so
// BOTH the leaf directories and their PARENT must be on the path.
// =============================================================================

-sv
-timescale 1ns/1ps

// Top module
-top riscforge_soc_subsystem

// =============================================================================
// Section 1: Include Paths
// =============================================================================
+incdir+axi_lite_xbar/include/axi
+incdir+axi_lite_xbar/include/common_cells
+incdir+axi_lite_xbar/include
+incdir+apb_uart-main/include/apb
+incdir+apb_uart-main/include/obi
+incdir+apb_uart-main/include/common_cells
+incdir+apb_uart-main/include/axi
+incdir+apb_uart-main/include/register_interface
+incdir+apb_uart-main/include
+incdir+register_interface

// I2C and SPI master local includes
+incdir+apb_i2c-master
+incdir+spi_master_ip/spi_master

// =============================================================================
// Section 2: Packages (compile order matters — packages before modules)
// =============================================================================

// Common math functions
axi_lite_xbar/include/common_cells/cf_math_pkg.sv

// AXI package (xbar_cfg_t, resp_t, prot_t, RESP_OKAY, etc.)
axi_lite_xbar/include/common_cells/axi_pkg.sv

// GPIO register package (GPIOCount, reg2hw/hw2reg structs)
gpio-master/gpio_reg_pkg.sv

// APB package (apb_to_reg / gpio_apb_wrap)
apb_uart-main/include/apb/apb_pkg.sv

// =============================================================================
// Section 3: Common Cells (shared infrastructure modules)
// =============================================================================
axi_lite_xbar/include/common_cells/addr_decode_dync.sv
axi_lite_xbar/include/common_cells/addr_decode.sv
axi_lite_xbar/include/common_cells/fifo_v3.sv
axi_lite_xbar/include/common_cells/fall_through_register.sv
axi_lite_xbar/include/common_cells/spill_register.sv
axi_lite_xbar/include/common_cells/spill_register_flushable.sv
axi_lite_xbar/include/common_cells/counter.sv
axi_lite_xbar/include/common_cells/rr_arb_tree.sv
axi_lite_xbar/include/common_cells/lzc.sv
axi_lite_xbar/include/common_cells/onehot_to_bin.sv
axi_lite_xbar/include/common_cells/delta_counter.sv
axi_lite_xbar/include/common_cells/id_queue.sv
axi_lite_xbar/include/common_cells/sync.sv
axi_lite_xbar/include/common_cells/stream_register.sv

// =============================================================================
// Section 4: AXI Infrastructure Modules (crossbar dependencies)
// =============================================================================
axi_lite_xbar/include/axi/axi_err_slv.sv
axi_lite_xbar/include/axi/axi_atop_filter.sv
axi_lite_xbar/include/axi/axi_lite_to_axi.sv
axi_lite_xbar/include/axi/axi_lite_demux.sv
axi_lite_xbar/include/axi/axi_lite_mux.sv

// =============================================================================
// Section 5: AXI-Lite Crossbar
// =============================================================================
axi_lite_xbar/axi_lite_xbar.sv

// =============================================================================
// Section 6: AXI-Lite -> APB Bridge
// =============================================================================
axi_lite_to_apb/axi_lite_to_apb.sv

// =============================================================================
// Section 6b: Bus Timeout Monitors
// NOTE: apb_timeout_monitor is interposed on the APB response path only;
//       axi_lite_timeout_monitor sits on the core's AXI-Lite master port.
// =============================================================================
bus_monitors/apb_timeout_monitor.sv
bus_monitors/axi_lite_timeout_monitor.sv

// =============================================================================
// Section 7: APB I2C Master
// NOTE: i2c_master_defines.sv is `included by apb_i2c.sv (resolved via +incdir)
// =============================================================================
apb_i2c-master/i2c_master_bit_ctrl.sv
apb_i2c-master/i2c_master_byte_ctrl.sv
apb_i2c-master/apb_i2c.sv

// =============================================================================
// Section 8: APB Timer (used by both Timer 0 and Timer 1 instances)
// =============================================================================
apb_timer-master/rtl/timer.sv
apb_timer-master/rtl/apb_timer.sv

// =============================================================================
// Section 9: APB UART
// The SoC instantiates `apb_uart` directly. apb_uart.sv is self-contained, so
// the OBI chain (apb_uart_wrap / apb_to_obi / obi_uart*) that the previous
// revision of this list carried is not compiled.
// =============================================================================
apb_uart-main/rtl/apb_uart.sv

// =============================================================================
// Section 10: GPIO
// gpio_apb_wrap -> gpio -> gpio_reg_top requires the PULP register_interface
// (reg_intf, apb_to_reg, prim_subreg, prim_subreg_arb, prim_subreg_ext).
// =============================================================================
register_interface/reg_intf.sv
register_interface/apb_to_reg.sv
register_interface/prim_subreg.sv
register_interface/prim_subreg_arb.sv
register_interface/prim_subreg_ext.sv
gpio-master/gpio_input_stage_no_clk_gates.sv
gpio-master/gpio_reg_top.sv
gpio-master/gpio.sv
gpio-master/gpio_apb_wrap.sv

// =============================================================================
// Section 11: APB SPI Master
// NOTE: spi_master_apb_if.sv redefines the REG_STATUS macro that apb_i2c.sv
//       also defines (xmvlog *W,MACRDF). Harmless — each uses its own value
//       within its own file — but it is why that warning appears.
// =============================================================================
spi_master_ip/spi_master/spi_master_clkgen.sv
spi_master_ip/spi_master/spi_master_fifo.sv
spi_master_ip/spi_master/spi_master_rx.sv
spi_master_ip/spi_master/spi_master_tx.sv
spi_master_ip/spi_master/spi_master_controller.sv
spi_master_ip/spi_master/spi_master_apb_if.sv
spi_master_ip/spi_master/apb_spi_master.sv

// =============================================================================
// Section 12: SoC Internal Memory Modules
// =============================================================================
RTL_SOC/sram_sp.sv
RTL_SOC/sram_mux.sv
RTL_SOC/axi_lite_sram_if.sv
instr_module/Instruction_Memory.v
RTL_SOC/imem_sram_wrapper.sv
RTL_SOC/boot_rom.sv
RTL_SOC/instr_fetch_demux.sv

// =============================================================================
// Section 13: RISC-V Core (RV32IM_Zicsr, 5-stage) + Bootloader
// =============================================================================
// NOTE: riscv_core/rtl/axi_pkg.sv is deliberately NOT listed. It declares the
//       same package name as the common_cells axi_pkg compiled in Section 2;
//       compiling both is a duplicate-package error. It exists so the core can
//       be simulated standalone, outside this filelist.

// Leaf / combinational blocks
riscv_core/rtl/PC.v
riscv_core/rtl/PC_Adder.v
riscv_core/rtl/Mux2.v
riscv_core/rtl/Mux_3_by_1.v
riscv_core/rtl/ALU.v
riscv_core/rtl/ALU_Decoder.v
riscv_core/rtl/Main_Decoder.v
riscv_core/rtl/Control_Unit_Top.v
riscv_core/rtl/Sign_Extend.v
riscv_core/rtl/Register_File.v
riscv_core/rtl/JB_unit.v
riscv_core/rtl/opcode_check.v

// M-extension (multiply / divide)
riscv_core/rtl/booth_enc.v
riscv_core/rtl/csa.v
riscv_core/rtl/pp_gen.v
riscv_core/rtl/rv32m_mul.v
riscv_core/rtl/rv32m_div.v
riscv_core/rtl/rv32m_unit.v

// CSR / trap / hazard / IRQ control
riscv_core/rtl/irq_gateway.v
riscv_core/rtl/irq_arbiter.v
riscv_core/rtl/csr_regfile.v
riscv_core/rtl/wb_trap_mret_commit_controller.v
riscv_core/rtl/hazard_unit.v

// Memory-side helpers (instantiated inside the pipeline stages)
riscv_core/rtl/imem_controller.v
riscv_core/rtl/ls_unit.v

// Pipeline stages
riscv_core/rtl/fetch_cycle.v
riscv_core/rtl/decode_cycle.v
riscv_core/rtl/execute_cycle.v
riscv_core/rtl/memory_cycle.v
riscv_core/rtl/writeback_cycle.v

// Core top
riscv_core/rtl/top.v

// Data-memory router (DSRAM direct / MMIO over AXI-Lite)
riscv_core/rtl/hybrid_mem_interface.sv

// Bootloader
bootloader/bootloader.sv

// =============================================================================
// Section 14: SoC Subsystem Top-Level
// =============================================================================
RTL_SOC/riscforge_soc_subsystem.sv
