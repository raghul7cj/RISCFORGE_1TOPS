# G2.12 — Current core JasperGold lint evidence

Run: `core_superlint_20261104_01`, 4 November 2026 IST. Scope: current `ips/riscv_core/rtl` core, top module `top`, complete descendant hierarchy, synthesis configuration.

**Result: completed; lint not clean.** The final ungrouped LINT report has **16 errors and 187 warnings**, with no waivers. A further 25 design-build warnings are retained separately; overlapping messages do not necessarily represent separate bugs. The setup report lists no black boxes. Tool exit code 0 confirms completion of analysis.

All errors are multiplier `INS_MS_PSIZ` findings: 65-bit connections to 66-bit `co` ports in `rv32m_mul.v`. Warning families include unconnected outputs, unused inputs, reset/style checks, default-case coding, overflow/width checks and combinational boundary paths. Their engineering disposition remains open.

The [complete run bundle](../../../../jaspergold/runs/lint/core/core_superlint_20261104_01/README.md) contains the input manifest and source snapshot, final Tcl/shell/PowerShell commands, raw reports and CSV, console logs, source-hash verification, native session archive, prior setup attempts, findings inventory and artifact hashes. Its [machine-readable result](../../../../jaspergold/runs/lint/core/core_superlint_20261104_01/result.json) records the exact counts and configuration.

The run used JasperGold 2025.06 on the Cadence server, LINT domain, `SYNTHESIS` defined, clock `clk`, active-low `rst`, and the standalone core's default reset PC. SoC integration, external memory bridge, peripherals, CDC/RDC, formal proofs and functional verification are outside its scope. Source identity is recorded with per-file SHA-256 hashes because Git metadata was unavailable.

The initial top-instance-only report is archived as an incomplete-scope attempt. The final hierarchy-wide extraction is authoritative for this run. See the run README for the retained setup failure and grouping differences.

**G2.12 remains open.** This is the requested JasperGold engineering evidence. The original checklist names SpyGlass; no item-specific tool-substitution approval or coach gate approval is asserted. No RTL fixes, waivers or workbook updates were performed.

## Written waiver addendum — 2026-11-04

The engineer approved the specific multiplier port/expression width behavior as intended. [Waiver scope and remaining review](../../../../jaspergold/runs/lint/core/waivers/20261104_multiplier_widths/README.md) records 16 lint errors, 18 lint warnings and 18 design-build warnings dispositioned. Remaining: 169 lint warnings and 7 design-build warnings. This is a written finding disposition; native tool reports retain their baseline counts and were not rerun. G2.12 remains open.

