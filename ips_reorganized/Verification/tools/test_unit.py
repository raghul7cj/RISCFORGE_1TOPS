"""Run the CSR/trap benches through Vivado XSim.

Thin wrapper over ``run_csr_trap_units.ps1`` so there is one command recipe
and one evidence layout. Usage, from ``rtl/ips``:

    py Verification/tools/test_unit.py
    py Verification/tools/test_unit.py csr_corner_unit
    py Verification/tools/test_unit.py core_csr_trap
"""
import subprocess
import sys
from pathlib import Path

RUNNER = Path(__file__).resolve().parents[1] / 'run_csr_trap_units.ps1'
BENCH = sys.argv[1] if len(sys.argv) > 1 else 'both'

if BENCH not in ('csr_corner_unit', 'core_csr_trap', 'both'):
    raise SystemExit(f'unknown bench {BENCH!r}; use csr_corner_unit, core_csr_trap or both')

command = ['pwsh', '-NoProfile', '-File', str(RUNNER), '-Bench', BENCH]
raise SystemExit(subprocess.call(command))
