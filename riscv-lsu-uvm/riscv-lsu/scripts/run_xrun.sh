#!/usr/bin/env bash
# =============================================================================
# run_xrun.sh — Cadence Xcelium execution script for RV32I ls_unit UVM TB
#
# Usage:
#   ./run_xrun.sh [test_name] [seed]   Run a simulation
#   ./run_xrun.sh clean                Remove all simulation outputs
#
# Examples:
#   ./run_xrun.sh lsu_smoke_test
#   ./run_xrun.sh lsu_regression_test
#   ./run_xrun.sh lsu_stress_test 2002
#
# All simulation artifacts (xcelium.d, cov_work, logs, snapshots) are written
# to ./sim/<test>_<seed>/ to keep this directory clean.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TB_DIR="$SCRIPT_DIR/../tb"
DESIGN_DIR="$SCRIPT_DIR/../design"
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
           "$SCRIPT_DIR"/work 2>/dev/null
    echo "Done. Removed: sim/, xcelium.d, cov_work, waves.shm, xrun_*.log, xrun_*.history"
    exit 0
fi

TEST=${1:-lsu_regression_test}
SEED=${2:-1001}
SIM_DIR="$SIM_ROOT/${TEST}_${SEED}"

mkdir -p "$SIM_DIR"

echo "=== Running Cadence Xcelium for RV32I ls_unit ==="
echo "Test: ${TEST} | Seed: ${SEED} | Output: sim/${TEST}_${SEED}/"

cd "$SIM_DIR" || exit 1

xrun -64bit -sv \
  -uvmhome /home/install/XCELIUM2409/tools/methodology/UVM/CDNS-1.2 \
  +incdir+$TB_DIR \
  $DESIGN_DIR/ls_unit.v \
  $TB_DIR/top_tb.sv \
  +UVM_TESTNAME=${TEST} \
  -svseed ${SEED} \
  +UVM_VERBOSITY=UVM_MEDIUM \
  -timescale 1ns/1ps \
  -access +rwc \
  -coverage all \
  -covoverwrite \
  -l xrun_${TEST}_${SEED}.log
