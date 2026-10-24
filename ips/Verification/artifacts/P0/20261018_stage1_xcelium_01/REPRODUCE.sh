#!/usr/bin/env bash
# Execute only in a fresh copied run directory on the Cadence server.
set -euo pipefail
cd -- "$(dirname -- "$0")"
if [ -e snapshot ] || [ -e results ]; then
  echo 'Use a fresh directory containing only inputs/, run_stage1.py and REPRODUCE.sh.' >&2
  exit 2
fi
mkdir snapshot
tar xzf inputs/source_snapshot.tar.gz -C snapshot
cp inputs/rf_monitors_xcelium.sv snapshot/Verification/infrastructure/monitors/rf_monitors.sv
export PATH=/home/iiita/riscv_tools/bin:/home/install/XCELIUM2409/tools/bin:$PATH
python3 run_stage1.py