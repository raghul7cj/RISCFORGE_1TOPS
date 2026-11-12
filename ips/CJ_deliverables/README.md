# CJ deliverables

Owner: CJ. Scope: the checklist subgates assigned to CJ in the 1-TOPS project signoff workbook. This folder is a navigation and handoff area; source RTL and raw run artifacts stay in their canonical locations.

## Layout

- `gates/G1_architecture/` — copied architecture and platform references plus CJ's G1 subgate map.
- `gates/G2_core_rtl/` — CJ's core implementation subgate map.
- `gates/G3_interrupt_integration/` — controller requirements, actual integration evidence and gaps.
- `gates/G4_core_verification/` — copied CSR/trap plan and status, plus CJ's verification map.
- `gates/G5_architectural_verification/` — benchmark references and architectural verification map.
- `gates/G6_soc_verification/` — SoC plan and CJ's system verification map.
- `shared/evidence_index/` — consolidated evidence index and candidate identity records.
- `shared/references/` — supporting material used across gates.

## Coach-facing gate reports

One report per gate, with that gate's CJ subgates grouped inside it:

- [G1 report](gates/G1_architecture/G1_report.html)
- [G2 report](gates/G2_core_rtl/G2_report.html)
- [G3 report](gates/G3_interrupt_integration/G3_report.html)
- [G4 report](gates/G4_core_verification/G4_report.html)
- [G5 report](gates/G5_architectural_verification/G5_report.html)
- [G6 report](gates/G6_soc_verification/G6_report.html)

Individual requirement pages live in each gate's `subgates/` folder. Open issues are consolidated in [open_items.md](open_items.md). The report SVG status summaries are saved under `diagrams/`.

## Gate-prefixed local HTML snapshots

Each file is a local copy of the canonical source listed here. The original remains untouched; relative links in the gathered copy are rebased to workspace sources.

| Gate | Local copy | Canonical source |
|---|---|---|
| G0/G4 | `shared/references/RISCFORGE_Verification_Infrastructure.html` | `ips/Verification/documentation/RISCFORGE_Verification_Infrastructure.html` |
| G2 | `gates/G2_core_rtl/G2_hazard_tb_architecture.html` | `ips/Verification/hazard_tb/docs/architecture.html` |
| G3 | `gates/G3_interrupt_integration/G3_IRQ_Architecture.html` | `ips/documentation/RISCFORGE IRQ Architecture.html` |
| G3 | `gates/G3_interrupt_integration/G3_core_interrupts.html` | `ips/documentation/html/core_interrupts.html` |
| G3 | `gates/G3_interrupt_integration/G3_vf_interrupt_verification.html` | `ips/documentation/html/vf_interrupt_verification.html` |
| G4 | `gates/G4_core_verification/G4_CSR_TRAP_TESTBENCH_ARCHITECTURE.html` | `ips/Verification/doc/architecture/CSR_TRAP_TESTBENCH_ARCHITECTURE.html` |
| G5 | `gates/G5_architectural_verification/G5_minstret_coverage.html` | `ips/Verification/minstret_retirement/checklist/coverage.html` |
| G5 | `gates/G5_architectural_verification/G5_riscv_dv_soc_roadmap.html` | `ips/Verification/plans/riscv-dv-soc-roadmap.html` |
| G6 | `gates/G6_soc_verification/G6_SOC_TESTBENCH_ARCHITECTURE.html` | `ips/Verification/plans/soc_testbench_framework_20261104/SOC_TESTBENCH_ARCHITECTURE.html` |

Start at [the CJ subgate map](CJ_SUBGATE_MAP.md). Every row separates the official workbook status from the present evidence assessment. A copied document is a point-in-time copy; its canonical source path is recorded in that document's gate README. Verify source identity and links before treating a copied result as current.

## Status authority

The supplied `1TOPS_Project_Signoff_Checkl.xlsx` is the official status authority. The repository's [checklist mirror](../Verification/signoff/1TOPS_PROJECT_CHECKLIST.md) reports workbook status per item; CJ_SUBGATE_MAP.md transcribes the CJ subset directly from the current workbook. Technical observations in this folder do not change workbook status or imply approval.
