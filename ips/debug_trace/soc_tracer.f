// =============================================================================
// RISCFORGE 1TOPS - SoC transaction tracer filelist (testbench only)
// =============================================================================
// Add AFTER any SoC filelist, from RTL_SOC/ (paths are relative to the
// directory xrun runs in, like every other filelist here):
//
//     xrun -f rtl/soc_regtest.f -f ../debug_trace/soc_tracer.f +TRACE_FILE=regtest_trace.log
//
// Then, on any machine with the RISC-V toolchain:
//
//     python ../debug_trace/soc_trace.py regtest_trace.log --elf ../mem_files/regtest/regtest.elf
//
// Leaving this filelist out removes the tracer completely.
// =============================================================================
../debug_trace/soc_tracer_pkg.sv
../debug_trace/soc_tracer.sv
../debug_trace/soc_tracer_bind.sv
