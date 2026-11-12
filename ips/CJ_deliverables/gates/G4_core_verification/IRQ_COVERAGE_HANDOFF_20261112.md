# IRQ documentation and coverage handoff — 12 November 2026

## Current disposition

- G3 source map and design/TB links documented; PLIC and CLIC not used. Direct IRQ is a speed/simplicity design rationale, not a measured advantage.
- `mintprio` exists: CSR 0x7C0, 2 bits, software-written; no automatic nesting stack/depth gate.
- 4.12 is partially complete: scoped timer entry checks pass; independent general pipeline/commit coverage remains open. No separate entry-to-commit gate is named in the checklist. G6.5 covers E2E integration; G6.13 covers trap robustness under load. Workbook unchanged.
- Active page: [G3 architecture and TB](../G3_interrupt_integration/G3_IRQ_ARCH_and_TB.html). Figure 1 is embedded inline; source map, design tags, two relevant TBs and done/left list retained.

## Retained remote run

- Alias: `ssh vlsi`; tools: Xcelium 24.09-s001 / IMC 24.09.
- Run: `irq-unit_20261111T185206Z_03e8a574`.
- [Local summary](../../../Verification/artifacts/vlsi_auto/irq-unit_20261111T185206Z_03e8a574/summary.json): pass; 196,608 arbitration snapshots; 471/471 declared functional bins. Report generation complete.
- Logs, coverage DB, IMC HTML/text and hashed tested input archive are local in that run directory. Remote run path: `/tmp/riscforge-xcelium/irq-unit_20261111T185206Z_03e8a574` (not re-probed today).
- [Current integrity recheck](../../../Verification/artifacts/vlsi_auto/irq-unit_20261111T185206Z_03e8a574/evidence_recheck_20261112.json): 28/28 saved output files match; all four RTL sources match; the TB source hash differs.
- TB diff includes named constants and extracted helper/checker tasks. It has not been established equivalent by a new run; do not represent the retained result as execution of the current TB.

| Instance | Block | Expression | Toggle |
| --- | --- | --- | --- |
| Gateway | 100% (3/3) | Not scored | 70.75% (75/106) |
| Arbiter | 98.21% (55/56) | 100% (3/3) | 95.74% (90/94) |
| WB controller | 100% (7/7) | 83.33% (5/6) | 10.21% (49/480) |
| CSR file | 51.02% (25/49) | 75% (9/12) | 18.02% (151/838) |

[IMC source report](../../../Verification/artifacts/vlsi_auto/irq-unit_20261111T185206Z_03e8a574/results/metrics_summary.txt). Instance-local unit metrics; no exclusions/refinements and no full code-coverage closure. The four blocks are separately driven, not a connected pipeline.

## Refresh attempt and next action

- Attempt `irq-unit_20261112T043538Z_c91939b7` was blocked before upload/simulation: Plink and direct OpenSSH both reported connection-level Permission denied for the resolved `ssh vlsi` address, port 22. No new simulation/coverage result exists.
- [Attempt status and logs](../../../Verification/artifacts/vlsi_auto/irq-unit_20261112T043538Z_c91939b7/ATTEMPT_STATUS.md) preserved. Do not infer remote directory creation from its allocated plan path.
- After connectivity returns, run directly from the rtl PowerShell terminal:

```powershell
vlsi-run .\scripts\vlsi\irq-unit.json
```

- The installed function uploads selected inputs, runs Xcelium/IMC and copies reports back. Do not nest another pwsh. Use existing private credential storage; no passwords belong in this handoff.
- Read the new summary first. Update current-source evidence links only after a functional pass, complete reports and verified source/result hashes. Keep failed evidence.
- No RTL, TB logic, expectations or official workbook statuses were changed in this final recording task.

## IRQ folder organization

Canonical bench and coverage plan now live in [Verification/irq_unit](../../../Verification/irq_unit/README.md), with stimulus map, filelist and run entry point. The TB was moved byte-for-byte; active manifests/filelists/HTML links were updated. Historical simulation artifacts were not rewritten. A move is not a refreshed simulation result.

## Standards review follow-up

[12-Nov compliance review and retained negative evidence](../../../Verification/artifacts/irq_compliance_review_20261112/RESULTS.md): GitHub #33/#34/#35 created; concrete M-only WARL evidence added to #20. Focused local real-block simulation, not new Xcelium coverage or full-core signoff. Production RTL and existing tests unchanged. Resolve these standard/custom-contract findings alongside the remaining 4.12 work.
