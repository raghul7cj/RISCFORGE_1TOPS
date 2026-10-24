// =============================================================================
// RISCFORGE 1TOPS — Monitor-layer self-test filelist (files only)
//
// Vivado XSim 2022.2:
//   xvlog --sv -timescale 1ns/1ps -f rf_mon_smoke.f
//   xelab rf_mon_smoke_tb -s rf_mon_smoke_sim
//   xsim rf_mon_smoke_sim -runall
//
// VCS U-2023.03:
//   vcs -sverilog -full64 -timescale=1ns/1ps -f rf_mon_smoke.f -top rf_mon_smoke_tb
// Cadence Xcelium:
//   xrun -sv -timescale 1ns/1ps -f rf_mon_smoke.f -top rf_mon_smoke_tb
// =============================================================================

// ---- Step 3 monitor layer (order matters: interfaces -> package -> classes) --
tb/rf_monitor_if.sv
tb/tb_pkg.sv
monitors/rf_monitors.sv
monitors/rf_monitor_env.sv
tb/rf_mon_probe.sv

// ---- structural stub DUT + self-test top ----
tb/rf_mon_stub_dut.sv
tb/rf_mon_smoke_tb.sv