#!/usr/bin/env bash
# Portable Icarus Verilog runner for the focused IRQ compliance reproducer.
# This is NOT the command that produced the retained compile.log/simulation.log.
# Those files are the original WSL/PowerShell run.ps1 evidence from the local
# rtl/ workspace. This script adapts paths to the repository-root layout
# ips_reorganized/... and writes only to a temporary VVP file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BUNDLE_REL="ips_reorganized/Verification/artifacts/irq_compliance_review_20261112"
SRC_PREFIX="ips_reorganized/riscv_core/rtl"

if ! command -v iverilog >/dev/null 2>&1; then
  echo "iverilog not found. Install Icarus Verilog 12.0 or run under WSL." >&2
  exit 127
fi
if ! command -v vvp >/dev/null 2>&1; then
  echo "vvp not found. Install Icarus Verilog 12.0." >&2
  exit 127
fi

TMP_VVP="$(mktemp "${TMPDIR:-/tmp}/irq_compliance_review.XXXXXX.vvp")"
trap 'rm -f "$TMP_VVP"' EXIT

iverilog -g2012 -s tb_irq_compliance -o "$TMP_VVP" \
  "$REPO_ROOT/$SRC_PREFIX/irq_gateway.v" \
  "$REPO_ROOT/$SRC_PREFIX/irq_arbiter.v" \
  "$REPO_ROOT/$SRC_PREFIX/csr_regfile.v" \
  "$REPO_ROOT/$BUNDLE_REL/tb_irq_compliance.sv"

# The retained evidence intentionally fails (7 standard-contract checks).
# vvp is expected to return nonzero; do not treat that as a runner failure.
set +e
vvp "$TMP_VVP"
SIM_RC=$?
set -e
echo "portable_runner_exit=$SIM_RC (expected nonzero for retained negative evidence)"
exit 0