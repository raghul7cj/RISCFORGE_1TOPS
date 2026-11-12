# Portable reproduction notes

Original retained evidence was generated from the local `rtl/` workspace with
`ips/...` paths using WSL Icarus Verilog 12.0. The repository layout on
`verification_infra` uses `ips_reorganized/...`.

- Original runner/provenance: `run.ps1` (unchanged).
- Portable runner: `run_portable.sh` (repository-root paths; does not overwrite
  `compile.log` or `simulation.log`).
- Expected result: compilation succeeds; simulation exits nonzero with 7 failing
  standard-contract checks and 1 passing timer control baseline. This is retained
  negative evidence, not a passing test.
- `sim.vvp` is intentionally not published.
- No production RTL, test expectations, coverage exclusions, or workbook statuses
  were changed.
