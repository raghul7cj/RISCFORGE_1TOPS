-sv
-timescale 1ns/1ps
-access +rwc

-top tb_axi_lite_to_apb

// Include paths for PULP common_cells and AXI headers
+incdir+../apb_uart-main/include/common_cells
+incdir+../apb_uart-main/include/axi
+incdir+../apb_uart-main/include

// Packages (compile first — order matters)
../apb_uart-main/include/common_cells/cf_math_pkg.sv
axi_pkg.sv

// Common cells dependencies
../apb_uart-main/include/common_cells/addr_decode_dync.sv
../apb_uart-main/include/common_cells/addr_decode.sv
../apb_uart-main/include/common_cells/rr_arb_tree.sv
../apb_uart-main/include/common_cells/fifo_v3.sv
../apb_uart-main/include/common_cells/fall_through_register.sv
../apb_uart-main/include/common_cells/spill_register.sv
../apb_uart-main/include/common_cells/lzc.sv
../apb_uart-main/include/common_cells/onehot_to_bin.sv

// DUT
axi_lite_to_apb.sv

// Testbench
tb_axi_lite_to_apb.sv
