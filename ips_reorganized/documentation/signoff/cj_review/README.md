# CJ signoff review documentation

Maintained documentation entry point: [HTML index](index.html).
Baseline: verification_infra/ips_reorganized at a91edb7e666d5c374af70809703f52eb5513d96f.
Review date: 11 November 2026. Local ips/ is an augmented offline copy, not a Git checkout.

Documentation status: structural v3 refined and visually inspected at report, narrow-screen and A4 layouts; static source inspection only. Earlier text reviews and rejected v2 visuals are historical, not approval of this replacement.

This package reconciles known source, contract and evidence records for CJ's 18 responsibilities. A reviewed document does not close a gate. No new simulations, reference models, stimuli, coverage bins, design/TB changes or waivers were produced.

## Documents

**Structural views:** [compact catalogue](diagram_index.html) links six source-bound SVGs to their owning captions and interface/source/evidence keys. Gate readiness uses a traceability matrix, without a process SVG.

| Order | Maintained detailed source | Reviewer view | Purpose |
|---|---|---|---|
| 01 | [Core architecture](01_core_architecture.md) | [HTML](01_core_architecture.html) | G1–G3: ISA, privilege, CSR/trap, interrupt/LSU interfaces and unresolved contracts |
| 02 | [Verification architecture](02_verification_architecture.md) | [HTML](02_verification_architecture.html) | Bench boundaries, user hooks, checking, sampling, coverage and evidence limits |
| 03 | [Benchmark / external SPI](03_benchmark_spi_evidence.md) | [HTML](03_benchmark_spi_evidence.html) | Historical workloads and boot results versus current qualification |
| 04 | [Gate readiness](04_gate_readiness.md) | [HTML](04_gate_readiness.html) | All 18 responsibilities, open defects/decisions and next closure evidence |
| 05 | [Hazard and pipeline gate](05_hazard_pipeline_gate.md) | [HTML](05_hazard_pipeline_gate.html) | Hazard-unit and pipeline benches, campaign evidence, and open finding HZ-F001 (issue #30) |

## Scope of document 05

Document 05 is the only part of this package backed by a fresh execution campaign. It reports a bounded development run on Verilator, keeps the open finding open, and claims no sign-off, no coverage closure and no decision on the interrupt/MDU policy. Its two figures are rendered from saved ground-truth specs under `ips/Verification/hazard_tb/docs/diagrams/`, each validated with zero rejected elements; the other six structural figures are hand-authored. The bench and script files it cites are local to the workspace and are not yet upstreamed, so the reproducer is not runnable from a fresh clone.
## Authority and maintenance

- Maintain each Markdown source and its concise HTML together. The HTML is a reviewer summary, not the only evidence record.
- Use [current corrected findings](../CJ_FINDING_RECONCILIATION_20261110.md), [remaining work](../CJ_REMAINING_WORK_20261110.md), [source sync validation](../../../../artifacts/verification_infra_sync_20261110/validation/POST_SYNC_VALIDATION.json) and [GitHub register #24](https://github.com/raghul7cj/RISCFORGE_1TOPS/issues/24).
- JALR issue #17 is withdrawn: the existing decode→ALU path already clears bit zero. Runtime low-bit coverage remains distinct.
- Open bug records #16/#18 and verification bugs #25–#27 differ from qualification gaps #19–#23 and legacy triage #28.
- Frozen/approved contract, as-coded behavior, independent expected result and observed evidence remain separate. Unknowns and user-reported results stay labelled.
- No per-item coach waiver, accepted-tool substitution, no-C applicability disposition or gate closure is inferred.
- Older HTML, logs and reports are retained as dated evidence; current-entry notices point here without erasing their history. The older dashboard's browser-local edits are not imported or treated as official dispositions.
- Relative evidence links need the accompanying workspace. The dated handoff copy rewrites source/evidence links back to this workspace; the ZIP is a review-document snapshot, not a standalone simulation archive.

## Named handoff copy

The current handoff is `1TOPS OFFICIAL DELIVERABLES/RISCFORGE_CJ_Signoff_Review_20261111_a91edb7_v3_structural_docs/` with the same-named ZIP. The v2 directory/ZIP are preserved. Rebuild with `py artifacts/cj_documentation_unification_20261110/build_review_package.py --copy`. The builder validates the structural set and refuses rejected active visuals; it never runs the old diagram generator.

## Learning route

Begin with [the load/MUL worked example](../cj_learning/START_HERE.md): distinguish instruction ownership, hold/flush, MDU completion and the effect that occurs exactly once. Then follow the requirement→source→test→evidence path in the topic you own.

