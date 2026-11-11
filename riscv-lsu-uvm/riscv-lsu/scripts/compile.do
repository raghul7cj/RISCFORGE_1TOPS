# =============================================================================
# compile.do — Questa / ModelSim compile + simulate script
# Updated for RV32I ls_unit.v
# Usage: vsim -do compile.do
# All artifacts (work library, transcript) go into sim/ to keep scripts/ clean.
# =============================================================================

file mkdir sim

# Create work library inside sim/
vlib sim/work
vmap work sim/work

# Compile (order: pkg → design → tb)
vlog -sv -mfcu -L uvm_lib \
    +incdir+../tb \
    ../tb/lsu_pkg.sv \
    ../design/ls_unit.v \
    ../tb/lsu_if.sv \
    ../tb/lsu_transaction.sv \
    ../tb/lsu_driver.sv \
    ../tb/lsu_monitor.sv \
    ../tb/lsu_scoreboard.sv \
    ../tb/lsu_coverage.sv \
    ../tb/lsu_sequences.sv \
    ../tb/lsu_agent.sv \
    ../tb/lsu_env.sv \
    ../tb/lsu_tests.sv \
    ../tb/lsu_assertions.sv \
    ../tb/top_tb.sv

# Simulate — override test with +UVM_TESTNAME= on command line
vsim -sv_seed 1001 \
     -l sim/vsim_lsu_regression_test.log \
     +UVM_TESTNAME=lsu_regression_test \
     +UVM_VERBOSITY=UVM_MEDIUM \
     top_tb

run -all
quit
