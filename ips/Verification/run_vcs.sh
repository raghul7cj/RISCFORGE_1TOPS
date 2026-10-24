#!/usr/bin/env bash
# =============================================================================
# RISCFORGE — Synopsys VCS / Cadence Xcelium SoC Regression Script
# =============================================================================
# Elaborates and runs the SoC-level testbench on the remote Linux server using
# the canonical compile list.
#
#   Synopsys host : iiita@172.16.33.48   (VCS U-2023.03, Verdi U-2023.03-SP1)
#   Cadence host  : iiita@172.16.33.51   (Xcelium, JasperGold)
#
# The compile list is NOT hard-coded here. It comes from the canonical manifest
#     Verification/infrastructure/rf_filelist.txt
# via
#     Verification/infrastructure/gen_filelists.py
# which emits soc_verification.esi.f with ABSOLUTE paths in the VCS/Xcelium
# dialect (includes: +incdir+<dir>, defines: +define+<name>).
#
# Why a generated list and not the checked-in RTL_SOC/soc_subsystem.f:
#
#   1. The old hand-written lists were authored against a different tree layout
#      (/home/iiita/MALAY_SOC/rtl/): SOC_FILES/, uart/, spi/, apb_timer/ and an
#      RTL_SOC/rtl/ level that do not exist in this repository. Every one of
#      those 46 paths resolved to nothing.
#   2. A `-f` list resolves entries against the tool's WORKING DIRECTORY, not
#      against the list's own location. Absolute paths remove that whole class
#      of failure, which is why the same generated list works here on Linux and
#      under Vivado XSim on Windows.
#   3. The Vivado and VCS/Xcelium include syntax is not interchangeable
#      (`-i` vs `+incdir+`), so the generator emits one list per dialect rather
#      than trying to make a single hand-written list serve both.
#
# The OBI UART chain (apb_uart_wrap -> apb_to_obi -> obi_uart*) that the old
# lists carried has been dropped: the SoC instantiates the self-contained
# `apb_uart` directly, and those obi_uart sources are not in this repository.
#
# USAGE
#   ./run_vcs.sh                          # all suites, WARM boot
#   ./run_vcs.sh --suite stage1_hello     # one suite
#   ./run_vcs.sh --suite stage1_hello,stage5_reg_sweep
#   ./run_vcs.sh --boot COLD
#   ./run_vcs.sh --elab-only              # compile + elaborate, run nothing
#   ./run_vcs.sh --tool xrun              # force Cadence Xcelium
#   ./run_vcs.sh --allow-missing          # emit lists despite missing sources
#
# EXIT CODES
#   0  every selected suite passed
#   1  at least one suite failed
#   2  the compile list did not preflight clean (missing sources)
#   3  no usable simulator found
# =============================================================================

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

BUILD_DIR="${REPO_ROOT}/Verification/build/vcs"
LOG_DIR="${BUILD_DIR}/logs"

TOOL="auto"
SUITE="all"
BOOT="WARM"
ELAB_ONLY=0
ALLOW_MISSING=0
KEEP_SIMV="${RF_KEEP_SIMV:-0}"

ALL_SUITES="stage1_hello stage2_watchdog stage3_monitor_count stage4_fault_inject stage5_reg_sweep stage6_polled_periph stage7_nested_irq"

while [ $# -gt 0 ]; do
    case "$1" in
        --suite)         SUITE="${2:-all}"; shift 2 ;;
        --boot)          BOOT="${2:-WARM}"; shift 2 ;;
        --tool)          TOOL="${2:-auto}"; shift 2 ;;
        --elab-only)     ELAB_ONLY=1; shift ;;
        --allow-missing) ALLOW_MISSING=1; shift ;;
        -h|--help)       sed -n '2,45p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done

mkdir -p "${LOG_DIR}"

echo "============================================================"
echo "  RISCFORGE SoC-Level Verification (VCS / Xcelium)"
echo "============================================================"
echo "  Repo root    : ${REPO_ROOT}"
echo "  Suites       : ${SUITE}"
echo "  Boot mode    : ${BOOT}"
echo "  Elaborate    : $([ ${ELAB_ONLY} -eq 1 ] && echo yes || echo no)"
echo "============================================================"

# -----------------------------------------------------------------------------
# Toolchain discovery
# -----------------------------------------------------------------------------
export SNPSLMD_LICENSE_FILE="${SNPSLMD_LICENSE_FILE:-27020@14.139.1.126}"
export CDS_LIC_FILE="${CDS_LIC_FILE:-5280@14.139.1.126}"

if [ "${TOOL}" = "auto" ]; then
    if command -v vcs >/dev/null 2>&1; then
        TOOL="vcs"
    elif command -v xrun >/dev/null 2>&1; then
        TOOL="xrun"
    else
        for p in /home/iiita/Synopsys/Installed_tools/vcs/U-*/bin \
                 /opt/synopsys/vcs/*/bin; do
            [ -d "${p}" ] && export PATH="${p}:${PATH}"
        done
        command -v vcs >/dev/null 2>&1 && TOOL="vcs" || TOOL="none"
    fi
fi

if [ "${TOOL}" = "none" ]; then
    echo "ERROR: neither vcs nor xrun is on PATH." >&2
    echo "       Source the Synopsys or Cadence setup, or pass --tool." >&2
    exit 3
fi

# Verdi is optional; only used for waveform browsing hints.
if [ -z "${VERDI_HOME:-}" ]; then
    for p in /home/iiita/Synopsys/Installed_tools/verdi/U-*/bin; do
        [ -d "${p}" ] && export PATH="${p}:${PATH}"
    done
fi

# -----------------------------------------------------------------------------
# Python 3 (for the filelist generator and the ELF->hex converter)
# -----------------------------------------------------------------------------
PY=""
for c in python3 python; do
    if command -v "${c}" >/dev/null 2>&1 && "${c}" -c 'import sys; sys.exit(0)' 2>/dev/null; then
        PY="${c}"; break
    fi
done
if [ -z "${PY}" ]; then
    echo "ERROR: no working python3 found (needed by gen_filelists.py)." >&2
    exit 2
fi

# -----------------------------------------------------------------------------
# Step 1: preflight + emit the VCS/Xcelium-dialect filelist
# -----------------------------------------------------------------------------
GENERATOR="Verification/infrastructure/gen_filelists.py"
GEN_ARGS="${GENERATOR} --emit --print-cmd"
[ "${ALLOW_MISSING}" -eq 1 ] && GEN_ARGS="${GEN_ARGS} --allow-missing"

echo ""
echo "[1/4] Preflighting the compile list..."
"${PY}" ${GEN_ARGS}
GEN_RC=$?

if [ ${GEN_RC} -ne 0 ] && [ "${ALLOW_MISSING}" -ne 1 ]; then
    echo ""
    echo "ABORT: the compile list did not preflight clean. Nothing was compiled." >&2
    echo "      Restore the sources named above, or re-run with --allow-missing." >&2
    exit 2
fi

FL="Verification/infrastructure/soc_verification.esi.f"
if [ ! -f "${FL}" ]; then
    echo "ERROR: generator did not produce ${FL}" >&2
    exit 2
fi

TOP="soc_tb_top"

# -----------------------------------------------------------------------------
# Step 2: compile + elaborate
# -----------------------------------------------------------------------------
COMPILE_LOG="${LOG_DIR}/compile.log"

if [ "${TOOL}" = "vcs" ]; then
    echo ""
    echo "[2/4] Compiling with VCS..."
    rm -rf "${BUILD_DIR}/csrc" "${BUILD_DIR}/simv" "${BUILD_DIR}/simv.daidir"
    vcs -sverilog -full64 \
        -timescale=1ns/1ps \
        -debug_access+all -kdb \
        +define+FSDB \
        -file "${FL}" \
        -top "${TOP}" \
        -o "${BUILD_DIR}/simv" \
        -l "${COMPILE_LOG}" \
        -Mdir="${BUILD_DIR}/csrc"
    RC=$?
    SIM="${BUILD_DIR}/simv"
else
    echo ""
    echo "[2/4] Compiling with Xcelium..."
    rm -rf "${BUILD_DIR}/xcelium.d" "${BUILD_DIR}/simv"
    xrun -sv \
        -timescale 1ns/1ps \
        +define+FSDB \
        -f "${FL}" \
        -top "${TOP}" \
        -elaborate \
        -l "${COMPILE_LOG}" \
        -xmlibdirname "${BUILD_DIR}/xcelium.d"
    RC=$?
    SIM="${BUILD_DIR}/simv"
fi

if [ ${RC} -ne 0 ]; then
    echo ""
    echo "COMPILE/ELABORATION FAILED (${TOOL} exit ${RC})." >&2
    echo "Log: ${COMPILE_LOG}" >&2
    grep -E '^Error|^ERROR|\*E,|VRFC 10-[0-9]+' "${COMPILE_LOG}" 2>/dev/null | head -40 >&2
    exit 1
fi

if [ ${ELAB_ONLY} -eq 1 ]; then
    echo ""
    echo "[3/4] --elab-only: elaboration succeeded; no suite was run."
    echo "[4/4] Nothing to execute."
    echo ""
    echo "  RESULT: elaboration OK, 0 suites executed, 0 passed."
    exit 0
fi

# -----------------------------------------------------------------------------
# Step 3: build firmware for each suite
# -----------------------------------------------------------------------------
GCC=""
for c in riscv64-unknown-elf-gcc riscv32-unknown-elf-gcc riscv-none-elf-gcc; do
    command -v "${c}" >/dev/null 2>&1 && { GCC="${c}"; break; }
done

if [ -z "${GCC}" ]; then
    echo ""
    echo "ERROR: no RISC-V GCC on PATH; cannot build suite firmware." >&2
    exit 1
fi

BSP="Verification/tests/bsp"
DRV="Verification/tests/drivers"
SUITES_DIR="Verification/tests/suites"

if [ "${SUITE}" = "all" ]; then
    SUITE_LIST="${ALL_SUITES}"
else
    SUITE_LIST="${SUITE//,/ }"
fi

BUILD_OK=1
for T in ${SUITE_LIST}; do
    if [ ! -f "${SUITES_DIR}/${T}/main.c" ]; then
        echo "ERROR: suite source not found: ${SUITES_DIR}/${T}/main.c" >&2
        exit 1
    fi
    echo ""
    echo "[3/4] Building firmware: ${T}"
    "${GCC}" -march=rv32im_zicsr -mabi=ilp32 -mcmodel=medlow -mno-relax \
        -O2 -g -ffreestanding -nostdlib \
        -I"${BSP}" -I"${DRV}" -T "${BSP}/link.ld" \
        "${BSP}/crt0.s" "${BSP}/trap_handler.s" "${BSP}/isr_dispatch.c" \
        "${DRV}/uart_driver.c" "${DRV}/timer_driver.c" "${DRV}/gpio_driver.c" \
        "${DRV}/i2c_driver.c" "${DRV}/spi_driver.c" \
        "${SUITES_DIR}/${T}/main.c" \
        -o "${BUILD_DIR}/${T}.elf" || { BUILD_OK=0; break; }

    "${PY}" Verification/regression/elf_to_hex_clean.py \
        "${BUILD_DIR}/${T}.elf" \
        "${BUILD_DIR}/${T}_imem.hex" \
        "${BUILD_DIR}/${T}_dmem.hex" || { BUILD_OK=0; break; }
done

if [ ${BUILD_OK} -ne 1 ]; then
    echo ""
    echo "FIRMWARE BUILD FAILED; no suite was run and nothing is reported as passed." >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 4: run each suite and grade it from the log
# -----------------------------------------------------------------------------
PASSED=""
FAILED=""

echo ""
echo "[4/4] Running suites (boot mode ${BOOT})..."

for T in ${SUITE_LIST}; do
    LOG="${LOG_DIR}/sim_${T}_${BOOT}.log"
    echo ""
    echo "---- ${T} ----"
    # Run from BUILD_DIR: the testbench $readmemh's the image paths relative to
    # the process working directory, so it is handed bare basenames.
    ( cd "${BUILD_DIR}" && "${SIM}" \
        -l "$(basename "${LOG}")" \
        "+BOOT_MODE=${BOOT}" \
        "+IMEM_HEX=${T}_imem.hex" \
        "+DMEM_HEX=${T}_dmem.hex" ) >/dev/null 2>&1
    SIM_RC=$?

    # Grade from the markers rather than the exit code: the testbench calls
    # $finish(0/1/2) and VCS propagates that, but the same grading has to hold
    # under Xcelium and XSim, whose exit-code conventions differ.
    if [ ! -f "${LOG}" ]; then
        echo "  FAIL  (no log produced, exit ${SIM_RC})"
        FAILED="${FAILED} ${T}(nolog)"
        continue
    fi

    if grep -q '\[MAILBOX PASS\]' "${LOG}" \
       && ! grep -qE '\[FATAL|\[MAILBOX FAIL\]|VACUOUS PASS' "${LOG}"; then
        echo "  PASS  ([MAILBOX PASS], exit ${SIM_RC})"
        PASSED="${PASSED} ${T}"
    else
        REASON="no pass marker"
        grep -q '\[FATAL VACUOUS PASS\]'   "${LOG}" && REASON="vacuous pass: zero instructions retired"
        grep -q '\[FATAL REGISTER PREDICTOR' "${LOG}" && REASON="register predictor mismatch"
        grep -q '\[FATAL INTERRUPT PREDICTOR' "${LOG}" && REASON="interrupt predictor mismatch"
        grep -q '\[MAILBOX FAIL\]'          "${LOG}" && REASON="firmware reported CMD_FAIL"
        grep -q '\[FATAL TIMEOUT\]'         "${LOG}" && REASON="watchdog timeout"
        echo "  FAIL  (${REASON}, exit ${SIM_RC})"
        echo "        log: ${LOG}"
        FAILED="${FAILED} ${T}(${REASON})"
    fi
done

if [ "${KEEP_SIMV}" -ne 1 ]; then
    rm -rf "${BUILD_DIR}/csrc" "${BUILD_DIR}/simv.daidir" "${BUILD_DIR}/xcelium.d"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
NPASS=0; [ -n "${PASSED}" ] && NPASS=$(echo "${PASSED}" | wc -w)
NTOTAL=$(echo "${SUITE_LIST}" | wc -w)

echo ""
echo "============================================================"
echo "  REGRESSION SUMMARY"
echo "============================================================"
echo "  Suites Selected : ${NTOTAL}"
echo "  Passed          : ${NPASS}"
echo "  Failed          : $(( NTOTAL - NPASS ))"
[ -n "${FAILED}" ] && echo "  Failures        :${FAILED}"
echo "  Compile log     : ${COMPILE_LOG}"
echo "  Suite logs      : ${LOG_DIR}"
if [ "${TOOL}" = "vcs" ]; then
    echo ""
    echo "  Waveforms:"
    echo "    verdi -ssf ${BUILD_DIR}/simv.fsdb &"
fi
echo "============================================================"

[ -n "${FAILED}" ] && exit 1
exit 0
