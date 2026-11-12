# CJ open items

Owner scope only; this is a navigation register, not a replacement for the issue tracker or workbook. CJ's current owned list excludes 5.2 (official ISA/RISCOF) and 6.10 (external SPI boot, transferred to Malay); their historical records remain in the [out-of-scope archive](shared/references/out_of_scope/README.md). Source: [CJ remaining work](shared/references/CJ_REMAINING_WORK_20261110.md), [finding reconciliation](shared/references/CJ_FINDING_RECONCILIATION_20261110.md), [local defects register](../Verification/status/defects.csv), and the subgate evidence paths.

| Item | Affected subgates | Current evidence / state | Closure record needed |
|---|---|---|---|
| CSR decision set D1–D6: collision and counter policy | 1.3, 1.4, 1.5, 2.9, 5.3, 6.13 | 56 CSR unit observations are `spec_pending`; existing observations do not establish expected behavior. See copied [CSR/trap status](gates/G4_core_verification/CSR_TRAP_VERIFICATION_STATUS.md). | Approved expected contract with approver/date/scope, then convert cases to independent expected checks and retain candidate-bound run results. |
| HZ-F001 ghost store / issue #30 | 2.7, 5.10, 6.13 | Hazard pipeline finding remains open in `Verification/hazard_tb/docs/validation.md`. | Reproducer, before/after results, accepted-effect check and required regression reviewed by a closer. |
| MDU declaration-order / XSim compile finding | 2.9, 5.10, 6.13 | Flagged Git issues are being handled by the user; no issue status is changed here. | User's issue-tracker closure evidence and any required regression. |
| Privileged/trap qualification | 1.5, 2.9, 4.12, 5.3 | Unit CSR run has 552 expected checks and 56 specification-pending observations; current interrupt replay covers a limited timer-entry path. | Resolve expected behavior, add independent checks for remaining trap/IRQ/CSR race/MRET cases, and retain candidate-bound closure evidence. |
| PLIC / CLINT / CLIC requirement disposition | 1.9, 3.4, 3.6, 6.5 | Custom local controller and core-level injected IRQ tests exist; no integrated PLIC/CLINT/CLIC path established by these tests. | Implement stated requirement or record authorized item-specific architecture disposition, then verify accepted scope. |
| End-to-end interrupt path | 1.9, 4.12, 6.5, 6.13 | SoC-level peripheral event to controller, core, handler and return chain remains pending. | Real event/source tests, independent mask/priority checks, committed entry and handler/return evidence. |
| CoreMark duration / benchmark score | 5.7 | CRC match recorded, duration requirement failed; Dhrystone smoke/probe evidence is scoped. | Complete qualifying workload and candidate-bound executable/configuration/metrics/reproducibility record. |

Do not infer that a linked issue is closed because the workbook is marked In Progress, or that an empty workbook cell means an accepted N/A. Official workbook statuses are shown in [CJ_SUBGATE_MAP.md](CJ_SUBGATE_MAP.md).
