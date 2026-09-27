#!/usr/bin/env bash
# =============================================================================
# RISCFORGE 1TOPS — SpyGlass Lint Execution Script
# =============================================================================
export SNPSLMD_LICENSE_FILE=27020@14.139.1.126
export SPYGLASS_HOME=/home/iiita/Synopsys/Installed_tools/spyglass/U-2023.03-SP2/SPYGLASS_HOME
export PATH=$SPYGLASS_HOME/bin:$PATH

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$WORKDIR"

mkdir -p reports

echo "==============================================================="
echo "   RISCFORGE 1TOPS — Running SpyGlass Lint on Whole SoC        "
echo "==============================================================="
echo "Working directory : $WORKDIR"
echo "Top-level module  : riscforge_soc_subsystem"
echo "SpyGlass Version  : $($SPYGLASS_HOME/bin/spyglass -version 2>&1 | head -n 4)"
echo "==============================================================="

$SPYGLASS_HOME/bin/sg_shell -tcl run_spyglass.tcl | tee spyglass_run.log

# Copy all native spyglass generated reports to reports/ folder
find riscforge_soc_lint/ -type f -name "*.rpt" -exec cp -v {} reports/ \; 2>/dev/null || true
find riscforge_soc_lint/ -type f -name "spyglass.log" -exec cp -v {} reports/ \; 2>/dev/null || true

echo ""
echo "==============================================================="
echo "   SpyGlass Lint Execution Complete! Checking Reports...       "
echo "==============================================================="
ls -la reports/

