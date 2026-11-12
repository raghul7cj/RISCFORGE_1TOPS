#!/usr/bin/env bash
set -euo pipefail

# Unit Regression Runner (Checklist 4.9)
# Runs all unit testbenches (directed + constrained random) and verifies zero failures.
# Usage:
#   ./run_unit_regression.sh [auto|vcs|xrun|iverilog] [num_seeds]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TOOL="${1:-auto}"
NUM_SEEDS="${2:-1}"
OUT_DIR="build/unit_regress"
mkdir -p "$OUT_DIR"

if [ "$TOOL" = "auto" ]; then
    if command -v vcs >/dev/null 2>&1; then
        TOOL="vcs"
    elif command -v xrun >/dev/null 2>&1; then
        TOOL="xrun"
    elif command -v iverilog >/dev/null 2>&1; then
        TOOL="iverilog"
    else
        echo "ERROR: No supported simulator found (vcs, xrun, iverilog)."
        exit 1
    fi
fi

TOTAL_FAIL=0
RUN_COUNT=0

check_log() {
    local name="$1"
    local log="$2"
    if ! grep -q "FAIL=0" "$log" || grep -q "\[FAIL\]" "$log"; then
        echo "[REGRESS FAIL] $name (see $log)"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    else
        local summary
        summary="$(grep "SUMMARY:" "$log" | tail -n 1)"
        echo "[REGRESS PASS] $name -> $summary"
    fi
}

run_one() {
    local name="$1"
    local seed="$2"
    shift 2
    local log="$OUT_DIR/${name}_seed${seed}.log"
    RUN_COUNT=$((RUN_COUNT + 1))

    case "$TOOL" in
        vcs)
            vcs -full64 -sverilog +v2k -timescale=1ns/1ps \
                -cm line+cond+fsm+tgl+branch -cm_dir "$OUT_DIR/cov.vdb" -cm_name "${name}_s${seed}" \
                -o "$OUT_DIR/simv_${name}" "$@" > "$OUT_DIR/${name}_compile.log" 2>&1
            "./$OUT_DIR/simv_${name}" +ntb_random_seed="$seed" \
                -cm line+cond+fsm+tgl+branch -cm_dir "$OUT_DIR/cov.vdb" -cm_name "${name}_s${seed}" \
                -l "$log" >/dev/null
            ;;
        xrun)
            xrun -64bit -sv -access +rwc -timescale 1ns/1ps -seed "$seed" \
                -coverage all -covoverwrite -covtest "${name}_s${seed}" \
                -xmlibdirname "$OUT_DIR/xcelium_${name}.d" \
                -l "$log" "$@" >/dev/null
            ;;
        iverilog)
            iverilog -g2012 -DNO_COVERGROUP -Wall -o "$OUT_DIR/${name}.vvp" "$@"
            vvp "$OUT_DIR/${name}.vvp" > "$log"
            ;;
        *)
            echo "ERROR: Unknown tool '$TOOL'. Use vcs, xrun, iverilog, or auto."
            exit 1
            ;;
    esac

    check_log "${name} (seed=${seed})" "$log"
}

echo "============================================================"
echo "Running Unit Regression (tool=$TOOL, seeds=$NUM_SEEDS)"
echo "============================================================"

for ((s = 1; s <= NUM_SEEDS; s++)); do
    run_one "pc_unit"       "$s" ../PC.v ../PC_Adder.v tb_pc_unit.sv
    run_one "register_file" "$s" ../Register_File.v tb_register_file.sv
    run_one "branch_unit"   "$s" ../JB_unit.v ../ALU.v tb_branch_unit.sv
done

echo "============================================================"
echo "UNIT REGRESSION SUMMARY: RUNS=${RUN_COUNT}, FAILED_RUNS=${TOTAL_FAIL}"
echo "============================================================"

if [ "$TOTAL_FAIL" -ne 0 ]; then
    exit 1
fi
