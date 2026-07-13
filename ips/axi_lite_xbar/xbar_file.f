// =============================================================================
// AXI-Lite Crossbar — Compilation Filelist
// Usage: vlog -f xbar_file.f
//   or:  xvlog --sv -f xbar_file.f
// =============================================================================

// Include paths for header files
+incdir+include/axi
+incdir+include/common_cells

// --- Packages (compile first) ---
include/common_cells/cf_math_pkg.sv
include/common_cells/axi_pkg.sv

// --- Common Cells (dependencies) ---
include/common_cells/addr_decode_dync.sv
include/common_cells/addr_decode.sv
include/common_cells/fifo_v3.sv
include/common_cells/fall_through_register.sv
include/common_cells/spill_register.sv
include/common_cells/spill_register_flushable.sv
include/common_cells/counter.sv
include/common_cells/rr_arb_tree.sv
include/common_cells/lzc.sv

// --- AXI Modules ---
include/axi/axi_err_slv.sv
include/axi/axi_atop_filter.sv
include/axi/axi_lite_to_axi.sv
include/axi/axi_lite_demux.sv
include/axi/axi_lite_mux.sv

// --- DUT ---
axi_lite_xbar.sv

// --- Testbench ---
tb_axi_lite_xbar.sv
