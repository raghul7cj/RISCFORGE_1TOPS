// RISCFORGE 1TOPS — Tier 2 Subsystem Fabric: soc_gpio_aperture
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
