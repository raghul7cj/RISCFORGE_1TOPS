#!/usr/bin/env bash
# =============================================================================
# run_xrun.sh — Cadence Xcelium execution script for RV32M Coprocessor UVM TB
#
# Usage:
#   ./run_xrun.sh [test_name] [seed]   Run a simulation
#   ./run_xrun.sh clean                Remove all simulation outputs
#
# Examples:
#   ./run_xrun.sh rv32m_directed_test
#   ./run_xrun.sh rv32m_rand_test 1001
#   ./run_xrun.sh rv32m_regression_test 2002
#   ./run_xrun.sh rv32m_stress_test
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_ROOT="$SCRIPT_DIR/sim"

# ── Clean mode ───────────────────────────────────────────────────────────────
if [ "$1" = "clean" ]; then
    echo "Cleaning simulation outputs..."
    rm -rf "$SIM_ROOT" \
           "$SCRIPT_DIR/xcelium.d" \
           "$SCRIPT_DIR/cov_work" \
           "$SCRIPT_DIR"/xrun_*.log \
           "$SCRIPT_DIR"/xrun_*.history \
           "$SCRIPT_DIR"/waves.shm \
           "$SCRIPT_DIR"/work \
           "$SCRIPT_DIR"/*.vcd 2>/dev/null
    echo "Done. Removed simulation artifacts."
    exit 0
fi

TEST=${1:-rv32m_regression_test}
SEED=${2:-1001}
SIM_DIR="$SIM_ROOT/${TEST}_${SEED}"

mkdir -p "$SIM_DIR"

echo "=================================================================="
echo " Running Cadence Xcelium for RV32M Coprocessor Unit UVM TB       "
echo " Test: ${TEST} | Seed: ${SEED} | Output: sim/${TEST}_${SEED}/   "
echo "=================================================================="

cd "$SIM_DIR" || exit 1

# If XCELIUM2409 is available in standard path, use its built-in CDNS-1.2 UVM library
UVM_FLAGS=""
if [ -d "/home/install/XCELIUM2409/tools/methodology/UVM/CDNS-1.2" ]; then
    UVM_FLAGS="-uvmhome /home/install/XCELIUM2409/tools/methodology/UVM/CDNS-1.2"
fi

xrun -64bit -sv \
  $UVM_FLAGS \
  +incdir+"$SCRIPT_DIR" \
  +incdir+"$SCRIPT_DIR/rtl" \
  +incdir+"$SCRIPT_DIR/tb" \
  "$SCRIPT_DIR/rtl/booth_enc.v" \
  "$SCRIPT_DIR/rtl/csa.v" \
  "$SCRIPT_DIR/rtl/pp_gen.v" \
  "$SCRIPT_DIR/rtl/rv32m_mul.v" \
  "$SCRIPT_DIR/rtl/rv32m_div.v" \
  "$SCRIPT_DIR/rtl/rv32m_unit.v" \
  "$SCRIPT_DIR/tb/testbench.sv" \
  +UVM_TESTNAME="${TEST}" \
  -svseed "${SEED}" \
  +UVM_VERBOSITY=UVM_MEDIUM \
  -timescale 1ns/1ps \
  -access +rwc \
  -assert \
  -coverage all \
  -covoverwrite \
  -log "xrun_${TEST}_${SEED}.log"

EXIT_CODE=$?
echo "=================================================================="
echo " Simulation finished with exit code $EXIT_CODE"
echo " Log file: $SIM_DIR/xrun_${TEST}_${SEED}.log"
echo "=================================================================="
exit $EXIT_CODE
