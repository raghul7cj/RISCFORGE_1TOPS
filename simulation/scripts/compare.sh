#!/bin/bash
# =============================================================================
# compare.sh — Spike vs RTL Golden Reference Comparison
# =============================================================================
# Usage: ./scripts/compare.sh <test_program.c>
# Example: ./scripts/compare.sh add_test.c
# =============================================================================

set -e

PROGRAM="${1:-add_test.c}"
PROGRAM_NAME=$(basename "$PROGRAM" .c)

# Resolve project root (one level up from scripts/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Directories
TEST_DIR="$PROJECT_DIR/tests"
START_DIR="$PROJECT_DIR/startup"
BUILD_DIR="$PROJECT_DIR/build"
RTL_DIR="$PROJECT_DIR/rtl"
SIM_DIR="$PROJECT_DIR/sim"

# Spike address offset
SPIKE_OFFSET=0x80000000

# Registers modified by Spike's internal bootloader (skip these)
# t0(5) = boot entry point, a1(11) = device tree pointer
SPIKE_BOOT_REGS="5 11"

# Registers that contain address values (need offset normalization)
ADDR_REGS="1 2"

# Toolchain
CROSS=riscv64-unknown-elf-
CC=${CROSS}gcc
CFLAGS="-march=rv32i -mabi=ilp32 -O0 -ffreestanding -nostdlib"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  GOLDEN REFERENCE VERIFICATION: ${CYAN}${PROGRAM_NAME}${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"

mkdir -p "$BUILD_DIR"

# ─────────────────────────────────────────────────────────────
# STEP 1: Build for both RTL and Spike
# ─────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}[1/4]${NC} Building firmware for RTL and Spike..."

# Build for RTL (base = 0x0)
$CC $CFLAGS -T "$START_DIR/linker.ld" "$START_DIR/start.S" "$TEST_DIR/$PROGRAM" -o "$BUILD_DIR/program.elf"
${CROSS}objcopy -O binary -j .text "$BUILD_DIR/program.elf" "$BUILD_DIR/program.bin"
hexdump -v -e '1/4 "%08x\n"' "$BUILD_DIR/program.bin" > "$BUILD_DIR/memfile.hex"
echo -e "  RTL build ............. ${GREEN}✓${NC}"

# Build for Spike (base = 0x80000000)
$CC $CFLAGS -T "$START_DIR/linker_spike.ld" "$START_DIR/start_spike.S" "$TEST_DIR/$PROGRAM" -o "$BUILD_DIR/program_spike.elf"
echo -e "  Spike build ........... ${GREEN}✓${NC}"

# ─────────────────────────────────────────────────────────────
# STEP 2: Run Spike
# ─────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}[2/4]${NC} Running Spike (golden reference)..."

SPIKE_CMDS=$(mktemp)
cat > "$SPIKE_CMDS" << 'EOF'
run 5000
reg 0
quit
EOF

SPIKE_OUT=$(spike --isa=rv32i -m0x80000000:0x10000 -d \
    --debug-cmd="$SPIKE_CMDS" "$BUILD_DIR/program_spike.elf" 2>&1)
rm -f "$SPIKE_CMDS"

# Parse Spike registers
declare -a SPIKE_VALS
spike_reg_lines=$(echo "$SPIKE_OUT" | grep -A3 "^zero:")
idx=0
while read -r val; do
    SPIKE_VALS[$idx]="$val"
    idx=$((idx + 1))
done < <(echo "$spike_reg_lines" | grep -oP '0x[0-9a-fA-F]+')

echo -e "  Spike done ............ ${GREEN}✓${NC}  (a0=${SPIKE_VALS[10]})"

# ─────────────────────────────────────────────────────────────
# STEP 3: Run RTL
# ─────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}[3/4]${NC} Running RTL simulation..."

cd "$PROJECT_DIR"
iverilog -o "$BUILD_DIR/tb.vvp" -I "$RTL_DIR" "$SIM_DIR/RISC_top_tb.v" > /dev/null 2>&1
RTL_OUT=$(vvp "$BUILD_DIR/tb.vvp" 2>&1)

# Parse RTL registers
declare -a RTL_VALS
while IFS= read -r line; do
    if echo "$line" | grep -qP '║\s*x[0-9]+'; then
        hex=$(echo "$line" | grep -oP '0x[0-9a-fA-F]{8}' | head -1)
        if [[ -n "$hex" ]]; then
            reg_num=$(echo "$line" | grep -oP 'x([0-9]+)' | head -1 | sed 's/x//')
            RTL_VALS[$reg_num]="$hex"
        fi
    fi
done <<< "$RTL_OUT"

echo -e "  RTL done .............. ${GREEN}✓${NC}  (a0=${RTL_VALS[10]})"

# ─────────────────────────────────────────────────────────────
# STEP 4: Compare
# ─────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}[4/4]${NC} Comparing register files..."
echo ""

ABI_NAMES=("zero" "ra" "sp" "gp" "tp" "t0" "t1" "t2"
           "s0/fp" "s1" "a0" "a1" "a2" "a3" "a4" "a5"
           "a6" "a7" "s2" "s3" "s4" "s5" "s6" "s7"
           "s8" "s9" "s10" "s11" "t3" "t4" "t5" "t6")

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

echo -e "  ${BOLD}┌──────────┬───────────┬──────────────┬──────────────┬──────────┐${NC}"
echo -e "  ${BOLD}│ Register │ ABI       │ Spike (Gold) │ RTL (DUT)    │ Status   │${NC}"
echo -e "  ${BOLD}├──────────┼───────────┼──────────────┼──────────────┼──────────┤${NC}"

for i in $(seq 0 31); do
    spike_val="${SPIKE_VALS[$i]:-}"
    rtl_val="${RTL_VALS[$i]:-}"
    abi="${ABI_NAMES[$i]}"

    # Skip Spike boot-artifact registers
    is_boot_reg=0
    for br in $SPIKE_BOOT_REGS; do
        [[ $i -eq $br ]] && is_boot_reg=1
    done

    if [[ $is_boot_reg -eq 1 ]]; then
        status="${YELLOW}~ skip${NC}"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        printf "  │ %-8s │ %-9s │ %-12s │ %-12s │ " "x$i" "$abi" "${spike_val:---}" "${rtl_val:---}"
        echo -e "$status │"
        continue
    fi

    # Check if address-relative register
    is_addr_reg=0
    for ar in $ADDR_REGS; do
        [[ $i -eq $ar ]] && is_addr_reg=1
    done

    if [[ -z "$spike_val" || -z "$rtl_val" ]]; then
        printf "  │ %-8s │ %-9s │ %-12s │ %-12s │ " "x$i" "$abi" "${spike_val:---}" "${rtl_val:---}"
        echo -e "${YELLOW}?${NC}        │"
        continue
    fi

    if [[ $is_addr_reg -eq 1 ]]; then
        spike_normalized=$(printf "0x%08x" $(( spike_val - SPIKE_OFFSET )) 2>/dev/null)
        if [[ "$spike_normalized" == "$rtl_val" ]]; then
            status="${GREEN}✓ adj${NC}"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            status="${RED}✗ FAIL${NC}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        spike_norm=$(printf "0x%08x" $spike_val 2>/dev/null)
        rtl_norm=$(printf "0x%08x" $rtl_val 2>/dev/null)
        if [[ "$spike_norm" == "$rtl_norm" ]]; then
            status="${GREEN}✓${NC}"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            status="${RED}✗ FAIL${NC}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    fi

    printf "  │ %-8s │ %-9s │ %-12s │ %-12s │ " "x$i" "$abi" "$spike_val" "$rtl_val"
    echo -e "$status   │"
done

echo -e "  ${BOLD}└──────────┴───────────┴──────────────┴──────────────┴──────────┘${NC}"

# ─────────────────────────────────────────────────────────────
# RESULT
# ─────────────────────────────────────────────────────────────
echo ""
SPIKE_A0="${SPIKE_VALS[10]}"
RTL_A0="${RTL_VALS[10]}"
COMPARED=$((PASS_COUNT + FAIL_COUNT))

if [[ $FAIL_COUNT -eq 0 && $PASS_COUNT -gt 0 ]]; then
    echo -e "  ${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${GREEN}${BOLD}║  ✅ PASS — ${PASS_COUNT}/${COMPARED} compared registers match (${SKIP_COUNT} skipped)     ║${NC}"
    echo -e "  ${GREEN}${BOLD}║  Return value (a0): Spike=${SPIKE_A0}  RTL=${RTL_A0}       ║${NC}"
    echo -e "  ${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 0
else
    echo -e "  ${RED}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${RED}${BOLD}║  ❌ FAIL — ${FAIL_COUNT}/${COMPARED} registers DIFFER (${SKIP_COUNT} skipped)              ║${NC}"
    echo -e "  ${RED}${BOLD}║  Return value (a0): Spike=${SPIKE_A0}  RTL=${RTL_A0}       ║${NC}"
    echo -e "  ${RED}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 1
fi
