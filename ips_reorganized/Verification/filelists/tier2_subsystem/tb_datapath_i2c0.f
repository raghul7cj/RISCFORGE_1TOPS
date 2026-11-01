// RISCFORGE 1TOPS — Tier 2 Subsystem Datapath: tb_datapath_i2c0
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

// Packages
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
