// RISCFORGE 1TOPS — Tier 3 SoC Integration: soc_verification
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
