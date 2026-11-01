// RISCFORGE 1TOPS — Tier 1 IP Unit: gpio
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
