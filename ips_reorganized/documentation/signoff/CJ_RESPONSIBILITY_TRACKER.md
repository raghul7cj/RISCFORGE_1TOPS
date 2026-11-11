# CJ responsibility tracker: 18 checklist items, evidence and final documents

Maintained by CJ (raghul7cj). Created 11 Nov 2026 against `verification_infra` baseline `a91edb7e666d5c374af70809703f52eb5513d96f` (PR #15 merge).

**This tracker does not close anything.** Official status comes only from the workbook; this page adds where the evidence and plans live and what is still missing. Coach approval is not inferred.

## Source of truth

| Item | Value |
|---|---|
| Official workbook | [1TOPS_Project_Signoff_Checkl.xlsx](../../../1TOPS%20OFFICIAL%20DELIVERABLES/1TOPS_Project_Signoff_Checkl.xlsx) |
| Workbook last modified | 2 Nov 2026 23:06 |
| Workbook SHA-256 | `d14dab56e3c358add7759e36374313aaf01bb1fad6af41f361516391c706bffa` (also recorded in [inventory.json](cj_inventory_20261108/inventory.json)) |
| Workbook totals | 124 items: 3 Done, 62 In Progress, 59 blank |
| CJ's 18 items | 0 Done, 13 In Progress, 5 blank |
| Checklist index (all 124 items) | [1TOPS_PROJECT_CHECKLIST.md](../../Verification/signoff/1TOPS_PROJECT_CHECKLIST.md), refreshed to match the workbook on 11 Nov 2026 |
| Defect and gap register | issue #24 and children #16–#28 |
| Current engineering picture | [04_gate_readiness.md](cj_review/04_gate_readiness.md) and [CJ_REMAINING_WORK_20261110.md](CJ_REMAINING_WORK_20261110.md) |

### Known workbook gaps (as recorded 2 Nov 2026)
- No Owner is entered on any of the 18 rows.
- On the 13 In Progress rows, the Evidence cell holds a bare filename, not a repo path or link as Cover rule 4 requires, and Comments read "Partial evidence; see gate review." This tracker supplies the links.
- The 5 blank rows (2.10, 3.4, 3.6, 5.7, 6.13) have empty Evidence and empty Comments.
- The workbook Dashboard counts the 59 blank items as neither In Progress nor Not Started (its Not Started total is 0).
- Item names in the tables below are the workbook's text verbatim. Notes such as "from Malay" or "approved alternative" are in the other columns.

## Tags

| Tag | Meaning |
|---|---|
| `[ON-BRANCH]` | Already on `verification_infra` before this commit |
| `[UPLOADED]` | Added to `verification_infra` by the commit that introduced this tracker |
| `[LOCAL-ONLY]` | Exists on CJ's machine, not uploaded (logs, ELFs, large or generated artefacts) |
| `[MISSING]` | Required by the checklist, does not exist yet |

Links are relative to this file. Sibling folders added at the repo root: `verification/riscof/`, `1TOPS OFFICIAL DELIVERABLES/`, `docs/`.

## Plans and documents by date (newest first)

| Date | Document | Tag | Items |
|---|---|---|---|
| 11 Nov 2026 | [CJ review package](cj_review/README.md): [01 core](cj_review/01_core_architecture.md), [02 verification](cj_review/02_verification_architecture.md), [03 benchmark/SPI](cj_review/03_benchmark_spi_evidence.md), [04 gate readiness](cj_review/04_gate_readiness.md) | `[UPLOADED]` | all 18 (current authority) |
| 10 Nov | [CORE_BUG_STATUS_20261109.md](../core/CORE_BUG_STATUS_20261109.md) | `[UPLOADED]` | 5.10 |
| 10 Nov | [IRQ_ARCHITECTURE_REVIEW.md](../../RTL_SOC/IRQ_ARCHITECTURE_REVIEW.md) | `[UPLOADED]` | 1.5, 1.9, 3.4, 3.6, 6.5 |
| 10 Nov | [MALAY_CORE_PORT_20261109.md](../core/MALAY_CORE_PORT_20261109.md), [core_port_20261109/README.md](../../Verification/core_port_20261109/README.md) | `[ON-BRANCH]` | 5.2, 5.3, 5.10 |
| 10 Nov | [cj_inventory_20261108/README.md](cj_inventory_20261108/README.md) (8 Nov baseline) | `[UPLOADED]` | all 18 (historical) |
| 4 Nov | [soc_testbench_framework_20261104](../../Verification/plans/soc_testbench_framework_20261104/README.md) | `[UPLOADED]` | 6.5, 6.10, 6.13 |
| 4 Nov | [irq_event_commit_plan_20261104/PLAN.md](irq_event_commit_plan_20261104/PLAN.md), [TB_FILE_PLAN.md](irq_event_commit_plan_20261104/TB_FILE_PLAN.md) | `[UPLOADED]` | 6.5, 4.12, 6.13 |
| 4 Nov | [CSR_TRAP_CORNER_TESTPLAN.md](../../Verification/doc/CSR_TRAP_CORNER_TESTPLAN.md), [CSR_TRAP_TESTBENCH_ARCHITECTURE.html](../../Verification/doc/CSR_TRAP_TESTBENCH_ARCHITECTURE.html), [csr_trap/README.md](../../Verification/infrastructure/tb/csr_trap/README.md) | `[UPLOADED]` | 1.4, 2.9, 4.12, 5.3, 6.13 |
| 4 Nov | [benchmarks/README.md](../../benchmarks/README.md), [docs/PLAN.md](../../benchmarks/docs/PLAN.md), [RTL_FAILURE_ISOLATION.md](../../benchmarks/docs/RTL_FAILURE_ISOLATION.md), REVIEW_R1 to R3 | `[UPLOADED]` | 5.7 |
| 3 Nov | [documentation/html](../html/) explainers: `vf_interrupt_verification`, `verif_csr_trap`, `vf_boot_verification`, `verif_bootloader`, `verif_lsu_memif`, `verif_core_overview`, `vf_strategy_env`, `vf_coverage`, `tracker_status` | `[UPLOADED]` | 1.5, 2.7, 2.9, 6.5, 6.10 |
| 2 Nov | [Core_Microarchitecture.md](Core_Microarchitecture.md), [CSR_and_Trap_Model.md](CSR_and_Trap_Model.md), [SoC_Architecture_Map_Boot.md](SoC_Architecture_Map_Boot.md), [SIGNOFF_ACTION_PLAN.md](SIGNOFF_ACTION_PLAN.md) | `[UPLOADED]` | the workbook's Evidence cells for 1.1, 1.3 to 1.5, 1.9, 2.7, 2.9, 4.12, 6.10 |
| 31 Oct | [VERIFICATION_INFRA_ORGANIZATION_AND_COORDINATION_PLAN.md](../../Verification/VERIFICATION_INFRA_ORGANIZATION_AND_COORDINATION_PLAN.md), [verification_roadmap.md](../../Verification/verification_roadmap.md), [defects.csv](../../Verification/status/defects.csv) | `[ON-BRANCH]` | infrastructure; not CJ-item specific |
| 29 Oct | [IRQ_UNIT_COVERAGE_PLAN.md](../../Verification/IRQ_UNIT_COVERAGE_PLAN.md), [MINTPRIO_INTEGRATION_AND_PREEMPTION_PLAN.md](../../Verification/MINTPRIO_INTEGRATION_AND_PREEMPTION_PLAN.md) | `[ON-BRANCH]` | 6.5, 4.12, 1.5, 2.9, 6.13 |
| 21 Oct | [riscforge_verification_architecture_refined.html](../../../docs/riscforge_verification_architecture_refined.html) | `[UPLOADED]` | context |
| 5 Oct | [RISCFORGE_Verification_Plan_RevB.docx](../../RISCFORGE_Verification_Plan_RevB.docx) | `[UPLOADED]` | requirements baseline; see note below |
| 2 Oct | [soc_verification_plan.md](../../Verification/soc_verification_plan.md) | `[ON-BRANCH]` | 1.14, 6.1 (older than Rev B) |

**Rev B note.** Rev B is an intended-state plan with no executed checks. It uses its own gates G0–G6 and severities S1–S5, which are not the workbook's gates G0–G9 or the checklist's P0–P3 levels. `defects.csv` (31 Oct) and the legacy [INFRA_TRACKING.md](../../INFRA_TRACKING.md) follow Rev B, not the checklist. Issue #28 is therefore a low-priority background triage task: it is listed against items where legacy B/V records matter (see the issue columns), but it does not by itself drive any gate.

## G1: Architecture specification

| ID | Responsibility | Official status | Evidence and plans | Issues | Final documents still needed |
|---|---|---|---|---|---|
| 1.1 | Core ISA frozen | In Progress | [Core_Microarchitecture.md](Core_Microarchitecture.md) `[UPLOADED]`; [top.v](../../riscv_core/rtl/top.v) `[ON-BRANCH]` | #17 (withdrawn), #19, #22 | `[MISSING]` written ISA freeze (RV32IM_Zicsr, no C) bound to a source hash |
| 1.3 | Privilege modes frozen | In Progress | [CSR_and_Trap_Model.md](CSR_and_Trap_Model.md) `[UPLOADED]` | #20 | `[MISSING]` privilege contract incl. MPP/SIE WARL behaviour |
| 1.4 | CSR list frozen | In Progress | [CSR_and_Trap_Model.md](CSR_and_Trap_Model.md) `[UPLOADED]`; [csr_regfile.v](../../riscv_core/rtl/csr_regfile.v) `[ON-BRANCH]` | #20, #28 | `[MISSING]` approved CSR table: addresses, reset, masks, RW/RO/WARL; keep 0x7C0 mintprio |
| 1.5 | Trap and interrupt model defined | In Progress | [CSR_and_Trap_Model.md](CSR_and_Trap_Model.md) `[UPLOADED]`; [MINTPRIO plan](../../Verification/MINTPRIO_INTEGRATION_AND_PREEMPTION_PLAN.md) `[ON-BRANCH]` | #20, #21, #25 | `[MISSING]` frozen priority, trap boundary, resume and nesting policy |
| 1.9 | Interrupt map frozen | In Progress | [SoC_Architecture_Map_Boot.md](SoC_Architecture_Map_Boot.md) `[UPLOADED]`; [irq_arbiter.v](../../riscv_core/rtl/irq_arbiter.v) `[ON-BRANCH]` | #25, #27, #28 | `[MISSING]` 13-source map: class, capture mode, priority/RR, accepted controller |

## G2: Core RTL

| ID | Responsibility | Official status | Evidence and plans | Issues | Final documents still needed |
|---|---|---|---|---|---|
| 2.7 | Memory interface unit coded | In Progress | [Core_Microarchitecture.md](Core_Microarchitecture.md) `[UPLOADED]`; [memory_cycle.v](../../riscv_core/rtl/memory_cycle.v) `[ON-BRANCH]`; [verif_lsu_memif.html](../html/verif_lsu_memif.html) `[UPLOADED]` | #21, #28 | `[MISSING]` LSU qualification record: sizes, offsets, strobes, sign extension, alignment, latency/error |
| 2.9 | CSR block and trap logic coded | In Progress | [CSR_and_Trap_Model.md](CSR_and_Trap_Model.md), [CSR corner test plan](../../Verification/doc/CSR_TRAP_CORNER_TESTPLAN.md), [csr_trap/README.md](../../Verification/infrastructure/tb/csr_trap/README.md) `[UPLOADED]` | #20, #21, #25, #26 | `[MISSING]` reference model, checks, stimuli and coverage (skeleton only today) |
| 2.10 | Compressed decoder coded (if C extension) | blank | none needed if C unsupported | #17 (withdrawn), #20 | `[MISSING]` one-line N/A reason, coach-approved (Cover rule 5) |

## G3: Interrupt integration

| ID | Responsibility | Official status | Evidence and plans | Issues | Final documents still needed |
|---|---|---|---|---|---|
| 3.4 | PLIC integrated (mandatory) | blank | [IRQ_ARCHITECTURE_REVIEW.md](../../RTL_SOC/IRQ_ARCHITECTURE_REVIEW.md) `[UPLOADED]` (custom controller exists) | #25, #28 | `[MISSING]` implementation, or an approved architecture alternative/waiver recorded with the coach |
| 3.6 | CLINT / CLIC integrated (mandatory) | blank | [IRQ_ARCHITECTURE_REVIEW.md](../../RTL_SOC/IRQ_ARCHITECTURE_REVIEW.md) `[UPLOADED]`; [clic-master/](../../clic-master/) `[ON-BRANCH]` (not integrated) | #20, #25, #28 | `[MISSING]` implementation or approved architecture waiver, recorded |

## G4: Unit and core verification

| ID | Responsibility | Official status | Evidence and plans | Issues | Final documents still needed |
|---|---|---|---|---|---|
| 4.12 | Reset and interrupt entry verified | In Progress | [IRQ_UNIT_COVERAGE_PLAN.md](../../Verification/IRQ_UNIT_COVERAGE_PLAN.md) `[ON-BRANCH]`; [irq_unit_coverage_20261029 run](../../Verification/artifacts/irq_unit_coverage_20261029_233839_967/functional_report/xcrg_func_cov_report.txt) `[ON-BRANCH]` | #21, #25, #26 | `[MISSING]` reset PC, trap entry, mtvec/mepc and MRET results on the current candidate |

## G5: Architectural verification

| ID | Responsibility | Official status | Evidence and plans | Issues | Final documents still needed |
|---|---|---|---|---|---|
| 5.2 | Official RISC-V ISA tests pass | In Progress | [report.html](../../../verification/riscof/report.html) (3 Jun, contains a failed result), [run_compliance.bat](../../../verification/riscof/run_compliance.bat), [config.ini](../../../verification/riscof/config.ini) `[UPLOADED]` | #22 | `[MISSING]` newer passing bundle at current source and reference identity (engineer-reported pass; bundle not located) |
| 5.3 | Privileged / trap tests pass | In Progress | [run_compliance.bat](../../../verification/riscof/run_compliance.bat) `[UPLOADED]`; [core_port_20261109/README.md](../../Verification/core_port_20261109/README.md) `[ON-BRANCH]` | #20, #21, #22, #26 | `[MISSING]` trap/CSR test results and async-ordering corners on the current candidate |
| 5.7 | Benchmarks run | blank | [benchmarks/README.md](../../benchmarks/README.md), [RTL_FAILURE_ISOLATION.md](../../benchmarks/docs/RTL_FAILURE_ISOLATION.md), [03_benchmark_spi_evidence.md](cj_review/03_benchmark_spi_evidence.md) `[UPLOADED]`; ELFs and run logs `[LOCAL-ONLY]` | #16, #17 (withdrawn), #19, #23 | Transferred from Malay. `[MISSING]` benchmark configuration, images, metrics, reproducibility notes, scored report |
| 5.10 | Core bug list closed | In Progress | [PHASE_STATUS.md](../../Verification/status/PHASE_STATUS.md) `[ON-BRANCH]`; [CORE_BUG_STATUS_20261109.md](../core/CORE_BUG_STATUS_20261109.md) `[UPLOADED]` | #16–#28 (tracker #24) | `[MISSING]` all P0/P1 fixed and re-verified; open P2/P3 listed with justification |

## G6: SoC verification

| ID | Responsibility | Official status | Evidence and plans | Issues | Final documents still needed |
|---|---|---|---|---|---|
| 6.5 | Interrupt path verified end to end | In Progress | [IRQ_UNIT_COVERAGE_PLAN.md](../../Verification/IRQ_UNIT_COVERAGE_PLAN.md) `[ON-BRANCH]` (IRQ unit only); [irq_event_commit_plan PLAN.md](irq_event_commit_plan_20261104/PLAN.md) `[UPLOADED]` (plan only) | #25, #27, #28 | `[MISSING]` event-to-controller TB and results for all 13 sources, masking and priority |
| 6.10 | Boot from external SPI flash passes | In Progress | [SoC_Architecture_Map_Boot.md](SoC_Architecture_Map_Boot.md), [verif_bootloader.html](../html/verif_bootloader.html) `[UPLOADED]`; [bootloader/](../../bootloader/) `[ON-BRANCH]` | #28 | Transferred from Malay. `[MISSING]` SPI image, bootloader handoff, execution-in-SRAM and pass/fail proof on the current candidate |
| 6.13 | Trap robustness under load passes | blank | [soc_testbench_framework_20261104](../../Verification/plans/soc_testbench_framework_20261104/README.md) `[UPLOADED]` (plan only) | #21, #22, #25, #26 | `[MISSING]` interrupts during load/store/branch-dense code, with precise-effect checks |

## Gate closure documents (all `[MISSING]`)
Each gate sheet ends with "Gate closed - coach signature / Date". None is signed. A gate closes only when every item is Done or N/A and Coach Approved is Yes.

| Gate | CJ items in it | Signature recorded |
|---|---|---|
| G1 | 1.1, 1.3, 1.4, 1.5, 1.9 | no |
| G2 | 2.7, 2.9, 2.10 | no |
| G3 | 3.4, 3.6 | no |
| G4 | 4.12 | no |
| G5 | 5.2, 5.3, 5.7, 5.10 | no |
| G6 | 6.5, 6.10, 6.13 | no |

## Supporting deliverables to produce
- CSR WARL and CSR operation tests; trap-controller and MRET verification.
- Precise exception and interrupt acceptance ordering, including CSR write races.
- Benchmark configuration, executable images, metrics and reproducibility notes.
- External SPI image, bootloader handoff, execution-in-SRAM and pass/fail proof (Malay supports infrastructure).

## Other documents on the branch worth knowing
- [CJ_FINDING_RECONCILIATION_20261110.md](CJ_FINDING_RECONCILIATION_20261110.md): the map from findings to issues #16–#28.
- [evidence_review_20261102/](evidence_review_20261102/): per-gate missing-evidence reviews (G0 to G9) and the verbal-decisions record.
- [Clock_Reset_CDC_and_Pinlist.md](Clock_Reset_CDC_and_Pinlist.md) (2 Nov): supports G1 items outside the 18.
- [benchmarks/docs/REVIEW_R1.md](../../benchmarks/docs/REVIEW_R1.md), R2, R3: 4 Nov benchmark plan reviews (5.7).
- Two documents were touched on 10 Nov but carry earlier dates in their own headers: `tracker_status.html` (3 Nov) and `CSR_TRAP_TESTBENCH_ARCHITECTURE.html` (4 Nov).

## Not uploaded (`[LOCAL-ONLY]`)
`artifacts/`, benchmark ELFs, run logs and waveforms, RISCOF signatures and `riscv-arch-test`, `risc-dv/`, `OLD files rtl-dv/`, Cadence and lab folders, and `.agents/` (contains credentials; never upload).

## How to update
1. Change the official workbook first; refresh the status columns here from it.
2. Move a tag from `[MISSING]` to `[UPLOADED]` only when the file is on the branch and its path is linked.
3. Never mark an item Done here. Only the coach does that in the workbook.
