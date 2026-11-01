#!/usr/bin/env python3
"""
create_filelists.py — Generates the 3-tier forwarding filelists for RISCFORGE 1TOPS.
All paths are strictly relative to repo working directory: rtl/ips
"""

import os
import sys

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FILELISTS_DIR = os.path.join(BASE_DIR, "Verification", "filelists")

TIER1_DIR = os.path.join(FILELISTS_DIR, "tier1_unit")
TIER2_DIR = os.path.join(FILELISTS_DIR, "tier2_subsystem")
TIER3_DIR = os.path.join(FILELISTS_DIR, "tier3_soc")

os.makedirs(TIER1_DIR, exist_ok=True)
os.makedirs(TIER2_DIR, exist_ok=True)
os.makedirs(TIER3_DIR, exist_ok=True)

# -----------------------------------------------------------------------------
# Tier 1 IP Unit Filelists
# -----------------------------------------------------------------------------

AON_TIMER_F = """// RISCFORGE 1TOPS — Tier 1 IP Unit: aon_timer (Watchdog)
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
"""

APB_I2C_F = """// RISCFORGE 1TOPS — Tier 1 IP Unit: apb_i2c
// Invocation root: rtl/ips
// Top: i2c_thorough_tb

+incdir+apb_i2c-master

apb_i2c-master/i2c_master_defines.sv
apb_i2c-master/i2c_master_bit_ctrl.sv
apb_i2c-master/i2c_master_byte_ctrl.sv
apb_i2c-master/apb_i2c.sv
apb_i2c-master/i2c_thorough_tb.sv
"""

APB_TIMER_F = """// RISCFORGE 1TOPS — Tier 1 IP Unit: apb_timer
// Invocation root: rtl/ips
// Top: apb_timer_tb

+incdir+apb_timer-master/tb

apb_timer-master/rtl/timer.sv
apb_timer-master/rtl/apb_timer.sv
apb_timer-master/tb/apb_timer_if.sv
apb_timer-master/tb/apb_timer_pkg.sv
apb_timer-master/tb/apb_timer_assertions.sv
apb_timer-master/tb/apb_timer_tb.sv
"""

APB_UART_F = """// RISCFORGE 1TOPS — Tier 1 IP Unit: apb_uart
// Invocation root: rtl/ips
// Top: tb_apb_uart_thorough

+incdir+SOC_FILES/include
+incdir+SOC_FILES/include/common_cells

SOC_FILES/include/common_cells/cf_math_pkg.sv
SOC_FILES/include/obi/obi_pkg.sv
SOC_FILES/include/obi/obi_uart_pkg.sv
SOC_FILES/include/apb/apb_pkg.sv

SOC_FILES/include/common_cells/sync.sv
SOC_FILES/include/common_cells/counter.sv
SOC_FILES/include/common_cells/fifo_v3.sv
SOC_FILES/include/common_cells/fall_through_register.sv
SOC_FILES/include/common_cells/shift_reg.sv
SOC_FILES/include/common_cells/lzc.sv
SOC_FILES/include/common_cells/delta_counter.sv
SOC_FILES/include/common_cells/shift_reg_gated.sv
SOC_FILES/include/register_interface/reg_to_apb.sv

SOC_FILES/include/obi/apb_to_obi.sv
SOC_FILES/include/obi/obi_uart.sv
SOC_FILES/include/obi/obi_uart_register.sv
SOC_FILES/include/obi/obi_uart_modem.sv
SOC_FILES/include/obi/obi_uart_baudgen.sv
SOC_FILES/include/obi/obi_uart_rx.sv
SOC_FILES/include/obi/obi_uart_tx.sv
SOC_FILES/include/obi/obi_uart_interrupts.sv

apb_uart-main/rtl/apb_uart.sv
apb_uart-main/rtl/apb_uart_wrap.sv
apb_uart-main/rtl/reg_uart_wrap.sv
apb_uart-main/rtl/tb_apb_uart_thorough.sv
"""

GPIO_F = """// RISCFORGE 1TOPS — Tier 1 IP Unit: gpio
// Invocation root: rtl/ips
// Top: tb_gpio_apb_directed

+incdir+SOC_FILES/include/apb
+incdir+SOC_FILES/include/register_interface
+incdir+SOC_FILES/include/common_cells
+incdir+SOC_FILES/include
+incdir+axi_lite_xbar/include/common_cells
+incdir+axi_lite_xbar/include

gpio-master/gpio_reg_pkg.sv
SOC_FILES/include/apb/apb_pkg.sv

axi_lite_xbar/include/common_cells/sync.sv

SOC_FILES/include/register_interface/reg_intf.sv
SOC_FILES/include/register_interface/apb_to_reg.sv
SOC_FILES/include/register_interface/prim_subreg_arb.sv
SOC_FILES/include/register_interface/prim_subreg.sv
SOC_FILES/include/register_interface/prim_subreg_ext.sv

gpio-master/gpio_input_stage_no_clk_gates.sv
gpio-master/gpio_reg_top.sv
gpio-master/gpio.sv
gpio-master/gpio_apb_wrap.sv

gpio-master/tb_gpio_apb_directed.sv
"""

BOOTLOADER_F = """// RISCFORGE 1TOPS — Tier 1 IP Unit: bootloader
// Invocation root: rtl/ips
// Top: bootloader_tb_all_testcases

SOC_FILES/include/common_cells/axi_pkg.sv

bootloader/bootloader_tb_all_testcases.sv
bootloader/bootloader.sv

spi_master_ip/spi_master/spi_master_clkgen.sv
spi_master_ip/spi_master/spi_master_fifo.sv
spi_master_ip/spi_master/spi_master_rx.sv
spi_master_ip/spi_master/spi_master_tx.sv
spi_master_ip/spi_master/spi_master_controller.sv
spi_master_ip/spi_master/spi_master_apb_if.sv
spi_master_ip/spi_master/apb_spi_master.sv

spi_slave_infinion/S25fs512s/model/s25fs512s.sv
"""

SPI_MASTER_F = """// RISCFORGE 1TOPS — Tier 1 IP Unit: spi_master
// Invocation root: rtl/ips
// Top: tb_apb_spi_master_bfm

spi_master_ip/spi_master/apb_spi_master.sv
spi_master_ip/spi_master/spi_master_apb_if.sv
spi_master_ip/spi_master/spi_master_clkgen.sv
spi_master_ip/spi_master/spi_master_controller.sv
spi_master_ip/spi_master/spi_master_fifo.sv
spi_master_ip/spi_master/spi_master_rx.sv
spi_master_ip/spi_master/spi_master_tx.sv

spi_master_ip/spi_master/spi_master_m_bfm_tb.sv
"""

IRQ_ARBITER_F = """// RISCFORGE 1TOPS — Tier 1 IP Unit: irq_arbiter
// Invocation root: rtl/ips
// Top: tb_irq_restructure

riscv_core/rtl/irq_gateway.v
riscv_core/rtl/irq_arbiter.v
riscv_core/rtl/wb_trap_mret_commit_controller.v
riscv_core/rtl/csr_regfile.v

Verification/tb_irq_restructure.sv
"""

APB_TIMEOUT_MONITOR_F = """// RISCFORGE 1TOPS — Tier 1 IP Unit: apb_timeout_monitor
// Invocation root: rtl/ips
// Top: tb_apb_timeout_monitor

bus_monitors/apb_timeout_monitor.sv

Verification/infrastructure/tb/tb_apb_timeout_monitor.sv
"""

AXI_LITE_TO_APB_F = """// RISCFORGE 1TOPS — Tier 1 IP Unit: axi_lite_to_apb
// Invocation root: rtl/ips
// Top: tb_axi_lite_to_apb

+incdir+axi_lite_xbar/include/common_cells
+incdir+axi_lite_xbar/include/axi
+incdir+axi_lite_xbar/include
+incdir+axi_lite_to_apb

axi_lite_xbar/include/common_cells/cf_math_pkg.sv
axi_lite_xbar/include/common_cells/axi_pkg.sv

axi_lite_xbar/include/common_cells/addr_decode_dync.sv
axi_lite_xbar/include/common_cells/addr_decode.sv
axi_lite_xbar/include/common_cells/rr_arb_tree.sv
axi_lite_xbar/include/common_cells/fifo_v3.sv
axi_lite_xbar/include/common_cells/fall_through_register.sv
axi_lite_xbar/include/common_cells/spill_register.sv
axi_lite_xbar/include/common_cells/lzc.sv
axi_lite_xbar/include/common_cells/onehot_to_bin.sv

axi_lite_to_apb/axi_lite_to_apb.sv

axi_lite_to_apb/tb_axi_lite_to_apb.sv
"""

AXI_LITE_XBAR_F = """// RISCFORGE 1TOPS — Tier 1 IP Unit: axi_lite_xbar
// Invocation root: rtl/ips
// Top: tb_axi_lite_xbar

+incdir+axi_lite_xbar/include/axi
+incdir+axi_lite_xbar/include/common_cells

axi_lite_xbar/include/common_cells/cf_math_pkg.sv
axi_lite_xbar/include/common_cells/axi_pkg.sv

axi_lite_xbar/include/common_cells/addr_decode_dync.sv
axi_lite_xbar/include/common_cells/addr_decode.sv
axi_lite_xbar/include/common_cells/fifo_v3.sv
axi_lite_xbar/include/common_cells/fall_through_register.sv
axi_lite_xbar/include/common_cells/spill_register.sv
axi_lite_xbar/include/common_cells/spill_register_flushable.sv
axi_lite_xbar/include/common_cells/counter.sv
axi_lite_xbar/include/common_cells/rr_arb_tree.sv
axi_lite_xbar/include/common_cells/lzc.sv

axi_lite_xbar/include/axi/axi_err_slv.sv
axi_lite_xbar/include/axi/axi_atop_filter.sv
axi_lite_xbar/include/axi/axi_lite_to_axi.sv
axi_lite_xbar/include/axi/axi_lite_demux.sv
axi_lite_xbar/include/axi/axi_lite_mux.sv

axi_lite_xbar/axi_lite_xbar.sv

axi_lite_xbar/tb_axi_lite_xbar.sv
"""

# -----------------------------------------------------------------------------
# Tier 2 Subsystem Fabric & Datapath Filelists
# -----------------------------------------------------------------------------

SOC_GPIO_APERTURE_F = """// RISCFORGE 1TOPS — Tier 2 Subsystem Fabric: soc_gpio_aperture
// Invocation root: rtl/ips
// Top: soc_gpio_aperture_tb

+incdir+axi_lite_xbar/include/common_cells
+incdir+axi_lite_xbar/include/axi
+incdir+axi_lite_xbar/include

axi_lite_xbar/include/common_cells/cf_math_pkg.sv
axi_lite_xbar/include/common_cells/axi_pkg.sv

axi_lite_xbar/include/common_cells/addr_decode_dync.sv
axi_lite_xbar/include/common_cells/addr_decode.sv
axi_lite_xbar/include/common_cells/rr_arb_tree.sv
axi_lite_xbar/include/common_cells/fifo_v3.sv
axi_lite_xbar/include/common_cells/fall_through_register.sv
axi_lite_xbar/include/common_cells/spill_register.sv
axi_lite_xbar/include/common_cells/lzc.sv
axi_lite_xbar/include/common_cells/onehot_to_bin.sv

axi_lite_to_apb/axi_lite_to_apb.sv

Verification/infrastructure/tb/soc_gpio_aperture_tb.sv
"""

DATAPATH_COMMON_RTL = """// Packages
axi_lite_xbar/include/common_cells/cf_math_pkg.sv
axi_lite_xbar/include/common_cells/axi_pkg.sv
gpio-master/gpio_reg_pkg.sv
SOC_FILES/include/apb/apb_pkg.sv
SOC_FILES/include/obi/obi_pkg.sv
SOC_FILES/include/obi/obi_uart_pkg.sv

// Common Cells
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

// AXI Infrastructure
axi_lite_xbar/include/axi/axi_intf.sv
axi_lite_xbar/include/axi/axi_err_slv.sv
axi_lite_xbar/include/axi/axi_atop_filter.sv
axi_lite_xbar/include/axi/axi_lite_to_axi.sv
axi_lite_xbar/include/axi/axi_lite_demux.sv
axi_lite_xbar/include/axi/axi_lite_mux.sv

// Crossbar & Bridge
axi_lite_xbar/axi_lite_xbar.sv
axi_lite_to_apb/axi_lite_to_apb.sv

// Peripherals
apb_i2c-master/i2c_master_bit_ctrl.sv
apb_i2c-master/i2c_master_byte_ctrl.sv
apb_i2c-master/apb_i2c.sv

apb_timer-master/rtl/timer.sv
apb_timer-master/rtl/apb_timer.sv

SOC_FILES/include/obi/apb_to_obi.sv
SOC_FILES/include/obi/obi_uart_baudgen.sv
SOC_FILES/include/obi/obi_uart_rx.sv
SOC_FILES/include/obi/obi_uart_tx.sv
SOC_FILES/include/obi/obi_uart_interrupts.sv
SOC_FILES/include/obi/obi_uart_modem.sv
SOC_FILES/include/obi/obi_uart_register.sv
SOC_FILES/include/obi/obi_uart.sv
apb_uart-main/rtl/apb_uart_wrap.sv
apb_uart-main/rtl/apb_uart.sv

SOC_FILES/include/register_interface/reg_intf.sv
SOC_FILES/include/register_interface/apb_to_reg.sv
SOC_FILES/include/register_interface/prim_subreg_arb.sv
SOC_FILES/include/register_interface/prim_subreg.sv
SOC_FILES/include/register_interface/prim_subreg_ext.sv
gpio-master/gpio_input_stage_no_clk_gates.sv
gpio-master/gpio_reg_top.sv
gpio-master/gpio.sv
gpio-master/gpio_apb_wrap.sv

spi_master_ip/spi_master/spi_master_clkgen.sv
spi_master_ip/spi_master/spi_master_fifo.sv
spi_master_ip/spi_master/spi_master_rx.sv
spi_master_ip/spi_master/spi_master_tx.sv
spi_master_ip/spi_master/spi_master_controller.sv
spi_master_ip/spi_master/spi_master_apb_if.sv
spi_master_ip/spi_master/apb_spi_master.sv

// Internal Memories
RTL_SOC/sram_sp.sv
RTL_SOC/sram_mux.sv
RTL_SOC/axi_lite_sram_if.sv
instr_module/Instruction_Memory.v
RTL_SOC/imem_sram_wrapper.sv
RTL_SOC/boot_rom.sv
RTL_SOC/instr_fetch_demux.sv

// RISC-V Core & Bootloader
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
riscv_core/rtl/booth_enc.v
riscv_core/rtl/csa.v
riscv_core/rtl/pp_gen.v
riscv_core/rtl/rv32m_mul.v
riscv_core/rtl/rv32m_div.v
riscv_core/rtl/rv32m_unit.v
riscv_core/rtl/csr_regfile.v
riscv_core/rtl/wb_trap_mret_commit_controller.v
riscv_core/rtl/hazard_unit.v
riscv_core/rtl/imem_controller.v
riscv_core/rtl/ls_unit.v
riscv_core/rtl/fetch_cycle.v
riscv_core/rtl/decode_cycle.v
riscv_core/rtl/execute_cycle.v
riscv_core/rtl/memory_cycle.v
riscv_core/rtl/writeback_cycle.v
riscv_core/rtl/top.v
riscv_core/rtl/hybrid_mem_interface.sv
bootloader/bootloader.sv

// SoC Top
RTL_SOC/riscforge_soc_subsystem.sv
"""

DATAPATH_I2C0_F = f"""// RISCFORGE 1TOPS — Tier 2 Subsystem Datapath: tb_datapath_i2c0
// Invocation root: rtl/ips
// Top: tb_i2c0

+incdir+axi_lite_xbar/include/axi
+incdir+axi_lite_xbar/include/common_cells
+incdir+axi_lite_xbar/include
+incdir+SOC_FILES/include/apb
+incdir+SOC_FILES/include/obi
+incdir+SOC_FILES/include/common_cells
+incdir+SOC_FILES/include
+incdir+apb_i2c-master
+incdir+spi_master_ip/spi_master
+incdir+RTL_SOC
+incdir+mem_files
+incdir+i2c_slave_at24c02
+incdir+datapath_verification/i2c0

{DATAPATH_COMMON_RTL}
// Target Model
i2c_slave_at24c02/i2c_rx.sv
i2c_slave_at24c02/i2c_digital_filter.sv
i2c_slave_at24c02/i2c_drv.sv
i2c_slave_at24c02/i2c_target_core.sv
i2c_slave_at24c02/i2c_target_endpoint.sv
i2c_slave_at24c02/at24c02_storage.sv
i2c_slave_at24c02/at24c02_device.sv
i2c_slave_at24c02/i2c_at24c02.sv

// Testbench
datapath_verification/i2c0/tb_i2c0.sv
"""

DATAPATH_SPI0_F = f"""// RISCFORGE 1TOPS — Tier 2 Subsystem Datapath: tb_datapath_spi0
// Invocation root: rtl/ips
// Top: tb_spi0

+incdir+axi_lite_xbar/include/axi
+incdir+axi_lite_xbar/include/common_cells
+incdir+axi_lite_xbar/include
+incdir+SOC_FILES/include/apb
+incdir+SOC_FILES/include/obi
+incdir+SOC_FILES/include/common_cells
+incdir+SOC_FILES/include
+incdir+apb_i2c-master
+incdir+spi_master_ip/spi_master
+incdir+RTL_SOC
+incdir+mem_files
+incdir+datapath_verification/spi0

{DATAPATH_COMMON_RTL}
// Target Model
spi_slave_infinion/S25fs512s/model/s25fs512s.sv

// Testbench
datapath_verification/spi0/tb_spi0.sv
"""

DATAPATH_UART0_F = f"""// RISCFORGE 1TOPS — Tier 2 Subsystem Datapath: tb_datapath_uart0
// Invocation root: rtl/ips
// Top: tb_uart0

+incdir+axi_lite_xbar/include/axi
+incdir+axi_lite_xbar/include/common_cells
+incdir+axi_lite_xbar/include
+incdir+SOC_FILES/include/apb
+incdir+SOC_FILES/include/obi
+incdir+SOC_FILES/include/common_cells
+incdir+SOC_FILES/include
+incdir+apb_i2c-master
+incdir+spi_master_ip/spi_master
+incdir+RTL_SOC
+incdir+mem_files
+incdir+datapath_verification/UART0

{DATAPATH_COMMON_RTL}
// Testbench
datapath_verification/UART0/tb_uart0.sv
"""

# -----------------------------------------------------------------------------
# Tier 3 Full SoC Filelists
# -----------------------------------------------------------------------------

SOC_VERIFICATION_F = """// RISCFORGE 1TOPS — Tier 3 SoC Integration: soc_verification
// Invocation root: rtl/ips
// Top: soc_tb_top

+incdir+axi_lite_xbar/include/axi
+incdir+axi_lite_xbar/include/common_cells
+incdir+apb_uart-main/include/apb
+incdir+apb_uart-main/include/obi
+incdir+apb_uart-main/include/common_cells
+incdir+apb_uart-main/include/axi
+incdir+apb_uart-main/include/register_interface
+incdir+apb_uart-main/include
+incdir+register_interface
+incdir+apb_i2c-master
+incdir+Verification/infrastructure/tb

// Packages
Verification/infrastructure/tb/tb_pkg.sv
axi_lite_xbar/include/common_cells/cf_math_pkg.sv
axi_lite_xbar/include/common_cells/axi_pkg.sv
gpio-master/gpio_reg_pkg.sv
apb_uart-main/include/apb/apb_pkg.sv
apb_uart-main/include/obi/obi_pkg.sv
apb_uart-main/include/obi/obi_uart_pkg.sv

// Common cells
axi_lite_xbar/include/common_cells/addr_decode.sv
axi_lite_xbar/include/common_cells/addr_decode_dync.sv
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

// AXI infrastructure
axi_lite_xbar/include/axi/axi_err_slv.sv
axi_lite_xbar/include/axi/axi_atop_filter.sv
axi_lite_xbar/include/axi/axi_lite_to_axi.sv
axi_lite_xbar/include/axi/axi_lite_demux.sv
axi_lite_xbar/include/axi/axi_lite_mux.sv

// Crossbar + APB bridge + bus timeout monitors
axi_lite_xbar/axi_lite_xbar.sv
axi_lite_to_apb/axi_lite_to_apb.sv
bus_monitors/apb_timeout_monitor.sv
bus_monitors/axi_lite_timeout_monitor.sv

// Peripherals
apb_i2c-master/i2c_master_bit_ctrl.sv
apb_i2c-master/i2c_master_byte_ctrl.sv
apb_i2c-master/apb_i2c.sv

apb_timer-master/rtl/timer.sv
apb_timer-master/rtl/apb_timer.sv

apb_uart-main/include/obi/apb_to_obi.sv
apb_uart-main/include/obi/obi_uart_baudgen.sv
apb_uart-main/include/obi/obi_uart_rx.sv
apb_uart-main/include/obi/obi_uart_tx.sv
apb_uart-main/include/obi/obi_uart_interrupts.sv
apb_uart-main/include/obi/obi_uart_modem.sv
apb_uart-main/include/obi/obi_uart_register.sv
apb_uart-main/include/obi/obi_uart.sv
apb_uart-main/rtl/apb_uart_wrap.sv
apb_uart-main/rtl/apb_uart.sv

register_interface/reg_intf.sv
register_interface/apb_to_reg.sv
register_interface/prim_subreg.sv
register_interface/prim_subreg_arb.sv
register_interface/prim_subreg_ext.sv

gpio-master/gpio_input_stage_no_clk_gates.sv
gpio-master/gpio_reg_top.sv
gpio-master/gpio.sv
gpio-master/gpio_apb_wrap.sv

spi_master_ip/spi_master/spi_master_clkgen.sv
spi_master_ip/spi_master/spi_master_fifo.sv
spi_master_ip/spi_master/spi_master_rx.sv
spi_master_ip/spi_master/spi_master_tx.sv
spi_master_ip/spi_master/spi_master_controller.sv
spi_master_ip/spi_master/spi_master_apb_if.sv
spi_master_ip/spi_master/apb_spi_master.sv

// Memories
RTL_SOC/sram_sp.sv
RTL_SOC/sram_mux.sv
RTL_SOC/axi_lite_sram_if.sv
instr_module/Instruction_Memory.v
RTL_SOC/imem_sram_wrapper.sv
RTL_SOC/boot_rom.sv
RTL_SOC/instr_fetch_demux.sv

// Core & Bootloader
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

riscv_core/rtl/booth_enc.v
riscv_core/rtl/csa.v
riscv_core/rtl/pp_gen.v
riscv_core/rtl/rv32m_mul.v
riscv_core/rtl/rv32m_div.v
riscv_core/rtl/rv32m_unit.v

riscv_core/rtl/irq_gateway.v
riscv_core/rtl/irq_arbiter.v
riscv_core/rtl/csr_regfile.v
riscv_core/rtl/wb_trap_mret_commit_controller.v
riscv_core/rtl/hazard_unit.v

riscv_core/rtl/imem_controller.v
riscv_core/rtl/ls_unit.v

riscv_core/rtl/fetch_cycle.v
riscv_core/rtl/decode_cycle.v
riscv_core/rtl/execute_cycle.v
riscv_core/rtl/memory_cycle.v
riscv_core/rtl/writeback_cycle.v

riscv_core/rtl/top.v
riscv_core/rtl/hybrid_mem_interface.sv
bootloader/bootloader.sv

// SoC Top
RTL_SOC/riscforge_soc_subsystem.sv

// VIPs
Verification/infrastructure/vip/uart_pin_vip.sv
Verification/infrastructure/vip/gpio_pin_vip.sv
Verification/infrastructure/vip/i2c_eeprom_at24c02.sv
Verification/infrastructure/vip/spi_flash_s25fs512s.sv

// Passive Monitors
Verification/infrastructure/tb/rf_monitor_if.sv
Verification/infrastructure/monitors/rf_monitors.sv
Verification/infrastructure/monitors/rf_monitor_env.sv
Verification/infrastructure/tb/rf_mon_probe.sv

Verification/infrastructure/monitors/fetch_monitor.sv
Verification/infrastructure/monitors/retire_monitor.sv
Verification/infrastructure/monitors/lsu_monitor.sv
Verification/infrastructure/monitors/axi_lite_monitor.sv
Verification/infrastructure/monitors/apb_monitor.sv
Verification/infrastructure/monitors/irq_monitor.sv

// Checkers
Verification/infrastructure/checkers/axi_lite_protocol_sva.sv
Verification/infrastructure/checkers/apb_protocol_sva.sv
Verification/infrastructure/checkers/mmio_path_scoreboard.sv
Verification/infrastructure/checkers/register_predictor.sv
Verification/infrastructure/checkers/irq_predictor.sv
Verification/infrastructure/checkers/failure_reporter.sv

// Testbench Top
Verification/infrastructure/tb/soc_tb_top.sv
"""

# Copy or mirror RTL_SOC/soc_subsystem.f directly for Design Only
with open(os.path.join(BASE_DIR, "RTL_SOC", "soc_subsystem.f"), "r", encoding="utf-8") as f:
    SOC_SUBSYSTEM_DESIGN_F = f.read()

FILELIST_MAP = {
    # Tier 1
    os.path.join(TIER1_DIR, "tb_aon_timer.f"): AON_TIMER_F,
    os.path.join(TIER1_DIR, "tb_apb_i2c.f"): APB_I2C_F,
    os.path.join(TIER1_DIR, "tb_apb_timer.f"): APB_TIMER_F,
    os.path.join(TIER1_DIR, "tb_apb_uart.f"): APB_UART_F,
    os.path.join(TIER1_DIR, "tb_gpio.f"): GPIO_F,
    os.path.join(TIER1_DIR, "tb_bootloader.f"): BOOTLOADER_F,
    os.path.join(TIER1_DIR, "tb_spi_master.f"): SPI_MASTER_F,
    os.path.join(TIER1_DIR, "tb_irq_arbiter.f"): IRQ_ARBITER_F,
    os.path.join(TIER1_DIR, "tb_apb_timeout_monitor.f"): APB_TIMEOUT_MONITOR_F,
    os.path.join(TIER1_DIR, "tb_axi_lite_to_apb.f"): AXI_LITE_TO_APB_F,
    os.path.join(TIER1_DIR, "tb_axi_lite_xbar.f"): AXI_LITE_XBAR_F,
    # Tier 2
    os.path.join(TIER2_DIR, "tb_soc_gpio_aperture.f"): SOC_GPIO_APERTURE_F,
    os.path.join(TIER2_DIR, "tb_datapath_i2c0.f"): DATAPATH_I2C0_F,
    os.path.join(TIER2_DIR, "tb_datapath_spi0.f"): DATAPATH_SPI0_F,
    os.path.join(TIER2_DIR, "tb_datapath_uart0.f"): DATAPATH_UART0_F,
    # Tier 3
    os.path.join(TIER3_DIR, "soc_verification.f"): SOC_VERIFICATION_F,
    os.path.join(TIER3_DIR, "soc_subsystem.f"): SOC_SUBSYSTEM_DESIGN_F,
}

def main():
    print(f"Generating 17 3-tier forwarding filelists under {FILELISTS_DIR}...")
    for path, content in FILELIST_MAP.items():
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(content.strip() + "\n")
        rel_path = os.path.relpath(path, BASE_DIR).replace("\\", "/")
        print(f"  [OK] {rel_path} ({len(content.splitlines())} lines)")
    print("All filelists successfully generated.")

if __name__ == "__main__":
    main()
