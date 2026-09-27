#!/usr/bin/env bash
# =============================================================================
# RISCFORGE 1TOPS — JasperGold Superlint Execution Script
# =============================================================================
set -e

export LM_LICENSE_FILE=5280@14.139.1.126
export CDS_LIC_FILE=5280@14.139.1.126
JG_BIN="/home/install/jasper_2025.06/bin/jg"

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$WORKDIR"

mkdir -p reports

echo "==============================================================="
echo "   RISCFORGE 1TOPS — Running JasperGold Superlint on Whole SoC "
echo "==============================================================="
echo "Working directory : $WORKDIR"
echo "Top-level module  : riscforge_soc_subsystem"
echo "JasperGold Path   : $JG_BIN"
echo "==============================================================="

$JG_BIN -allow_unsupported_OS -superlint -batch -tcl lint.tcl | tee jg_run.log

echo ""
echo "==============================================================="
echo "   JasperGold Superlint Complete! Generated Reports:          "
echo "==============================================================="
ls -la reports/

