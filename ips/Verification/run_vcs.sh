#!/usr/bin/env bash
# =============================================================================
# RISCFORGE — Synopsys VCS & Verdi Automation Script
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

export SNPSLMD_LICENSE_FILE=27020@14.139.1.126
export VCS_HOME=/home/iiita/Synopsys/Installed_tools/vcs/U-2023.03
export VERDI_HOME=/home/iiita/Synopsys/Installed_tools/verdi/U-2023.03-SP1
export PATH="${VCS_HOME}/bin:${VERDI_HOME}/bin:${PATH}"

echo "============================================================"
echo "  RISCFORGE Core Interrupt Verification (Synopsys VCS)"
echo "============================================================"

# 1. Generate Hex Test Files from Assembly
echo "[1/3] Compiling Assembly Sources to Hex Images..."
python3 compile_asm.py

# 2. Compile with VCS
echo "[2/3] Compiling RTL and Testbench with VCS..."
vcs -sverilog -full64 +v2k -timescale=1ns/1ps -debug_access+all -kdb +define+FSDB -f tb1_interrupts.f -o simv -l compile.log

# 3. Execute Simulation
echo "[3/3] Executing Simulation..."
./simv -l sim.log

echo ""
echo "============================================================"
echo "  SIMULATION FINISHED"
echo "  - Compile Log: compile.log"
echo "  - Sim Log:     sim.log"
echo "  - Verdi FSDB:  core_interrupt_tb.fsdb"
echo ""
echo "  To inspect waveforms in Verdi, run:"
echo "    verdi -ssf core_interrupt_tb.fsdb -f tb1_interrupts.f &"
echo "============================================================"

