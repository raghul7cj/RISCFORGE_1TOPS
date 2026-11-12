# CJ subgate delivery map

Owner: CJ · Checklist source: `1TOPS OFFICIAL DELIVERABLES/1TOPS_Project_Signoff_Checkl.xlsx` · Scope: CJ responsibility subgates only.

**Status rule:** official status below follows the repository checklist mirror of the supplied workbook (status values read from workbook G1–G6 sheets on 2026-11-11; blank cells are explicitly shown as Blank). Evidence assessment is separate and does not override workbook status. Historical run claims remain tied to their recorded source/tool identity.

## G1 — Specification and architecture

| Subgate | CJ document | Source documents / actual RTL | TB, scripts, evidence and remaining work |
|---|---|---|---|
| 1.1 Core ISA frozen | [G1 architecture](gates/G1_architecture/README.md) | [Core microarchitecture copy](gates/G1_architecture/Core_Microarchitecture.md); RTL `riscv_core/rtl/`; `artifacts/core_port_20261109/results.json` | Core-port artifacts record RV32IM/Zicsr candidate configuration. Freeze exact ISA/extensions, build flags and FENCE/WFI policy. Workbook status: In Progress. |
| 1.3 Privilege modes frozen | [G1 architecture](gates/G1_architecture/README.md) | [CSR/trap model copy](gates/G1_architecture/CSR_and_Trap_Model.md); `riscv_core/rtl/csr_regfile.v` | `Verification/minstret_retirement/checklist/` and `artifacts/core_port_20261109/` trap cases. M-mode behavior exists; approved privilege/MPP/WARL contract remains to be recorded. Workbook status: In Progress. |
| 1.4 CSR list frozen | [G1 architecture](gates/G1_architecture/README.md) | [CSR/trap model copy](gates/G1_architecture/CSR_and_Trap_Model.md); active `csr_regfile.v` | `Verification/infrastructure/tb/csr_trap/`; [bench architecture](../Verification/doc/architecture/CSR_TRAP_TESTBENCH_ARCHITECTURE.html); [corner plan copy](gates/G4_core_verification/CSR_TRAP_CORNER_TESTPLAN.md). Reconcile implemented addresses, resets, masks and unsupported access policy. Workbook status: In Progress. |
| 1.5 Trap and interrupt model | [G1 architecture](gates/G1_architecture/README.md) | [CSR/trap model copy](gates/G1_architecture/CSR_and_Trap_Model.md); `riscv_core/rtl/wb_trap_mret_commit_controller.v`, `top.v` | `Verification/artifacts/csr_trap_closure_check_20261111/`; `artifacts/core_port_20261109/`; `minstret_retirement/checklist/`. Preserve unresolved CSR collision and interrupt ordering decisions; bind the approved boundary/resume-PC model. Workbook status: In Progress. |
| 1.9 Interrupt map frozen | [G1 architecture](gates/G1_architecture/README.md) | [SoC/boot map copy](gates/G1_architecture/SoC_Architecture_Map_Boot.md); `RTL_SOC/riscforge_soc_subsystem.sv`, `riscv_core/rtl/irq_gateway.v`, `irq_arbiter.v` | Architecture freeze record: source/subevent mapping, capture/rearm, masks and priority in the SoC/boot map and IRQ architecture page. Verification and coverage evidence is owned by [G4.12 IRQ unit evidence](gates/G4_core_verification/G4_IRQ_UNIT_VERIFICATION.html); its 471/471 declared unit bins are not architecture-freeze justification. `Verification/minstret_retirement/checklist/interrupt.S`, `hazard_tb/` and `documentation/signoff/irq_event_commit_plan_20261104/` remain crosschecks. Record the accepted controller disposition; approval is not decided by the HTML. Workbook status: In Progress. |

## G2 — Core RTL

| Subgate | CJ document | Source RTL | TB, scripts, evidence and remaining work |
|---|---|---|---|
| 2.7 Memory interface / LSU | [G2 core RTL](gates/G2_core_rtl/README.md) | `riscv_core/rtl/memory_cycle.v`, `ls_unit.v`, `hybrid_mem_interface.sv` | Old full LSU bench is under `OLD files rtl-dv/LSU verification/SV layered tb/` and `OLD files rtl-dv/lsu verification export/`; its 03-Jul-2026 log reports 15 pass / 6 fail and missing `dmem.hex`. Current core-port evidence is at `artifacts/core_port_20261109/`: candidate 13/13 cases pass, including load/MDU waits 0/1/4; base passes 2/13. Current tests cover selected word traffic, not the old suite's full byte/half/alignment/error/effect matrix. Rebind the old bench to current RTL and close those cases. Workbook status: In Progress. |
| 2.9 CSR block and trap logic | [G2 core RTL](gates/G2_core_rtl/README.md) | `riscv_core/rtl/csr_regfile.v`, `wb_trap_mret_commit_controller.v`, `top.v` | `Verification/run_csr_trap_units.ps1`; `infrastructure/tb/tb_csr_corner_unit.sv`; `artifacts/csr_trap_closure_check_20261111/`; `minstret_retirement/`. Unit has 552 expected checks / 0 failures, plus 56 spec-pending observations; not full core/trap closure. Workbook status: In Progress. |
| 2.10 Compressed decoder applicability | [G2 core RTL](gates/G2_core_rtl/README.md) | Current core has no compressed decoder | Build configuration uses RV32IM/Zicsr; retain exact no-C configuration and alignment evidence, then record approved N/A. Status: Not Started in workbook; N/A is proposed disposition only. |

## G3 — Interrupt integration

| Subgate | CJ document | Source / implementation | TB, evidence and remaining work |
|---|---|---|---|
| 3.4 PLIC | [G3 integration](gates/G3_interrupt_integration/README.md) | CJ architecture direction: PLIC not used; no RTOS; direct IRQ interface to the core is the intended interrupt path | `Verification/irq_unit/tb_irq_restructure.sv` is controller/unit-level evidence retained under [G4.12](gates/G4_core_verification/G4_IRQ_UNIT_VERIFICATION.html); it is a unit-scope cross-reference for the direct-interface disposition, not G3 evidence ownership and not SoC-path evidence. Record the direct-interface decision as the architecture disposition and get it accepted against the workbook criterion; no PLIC implementation is planned. Workbook status: Blank (cell empty). |
| 3.6 CLINT/CLIC | [G3 integration](gates/G3_interrupt_integration/README.md) | CLINT/timer integration is not complete in the SoC; direct core IRQ input exists | `minstret_retirement/` and `hazard_tb/` are core-level. CLINT is yet to be integrated; next evidence is timer source → core IRQ → handler, with source/mask behavior checked. Workbook status: Blank (cell empty). |

## G4 — Unit and core verification

| Subgate | CJ document | TB / scripts | Evidence and remaining work |
|---|---|---|---|
| 4.12 Interrupt entry (CJ scope; reset excluded) | [G4 verification](gates/G4_core_verification/README.md); [interrupt-entry record](gates/G4_core_verification/subgates/4_12.md); [IRQ unit verification](gates/G4_core_verification/G4_IRQ_UNIT_VERIFICATION.html); [IRQ unit coverage](gates/G4_core_verification/G4_IRQ_UNIT_COVERAGE.html) | `Verification/minstret_retirement/checklist/tb_checklist.sv`; canonical IRQ unit bench `Verification/irq_unit/tb_irq_restructure.sv` with plan `Verification/irq_unit/IRQ_UNIT_COVERAGE_PLAN.md`; historical `Verification/tb1_interrupts.sv` + `tb1_interrupts.f` | Engineering progress: PARTIALLY COMPLETE. Scoped timer-entry check done (cause 7, committed PC, handler/MRET/replay); the full campaign retains 12/12 runs and 29 scoped bins. Broader pipeline/commit checks remain open; no separate entry-to-commit gate is named in the checklist. G6.5/G6.13 cover end-to-end integration and load robustness. entry acceptance stays distinct from retirement counting. The retained 11-Nov IRQ unit run reports 196,608 arbitration snapshots and 471/471 declared bins, but gateway/arbiter/CSR/WB commit are separately driven, so it supports unit contracts and is not pipeline entry closure. A legacy tb1 log is now retained with seven historical scenario failures (stale expectations, `$readmem` image errors) needing reconciliation, not automatic DUT defects. Workbook status: In Progress. |

## G5 — Architectural verification

| Subgate | CJ document | TB / scripts | Evidence and remaining work |
|---|---|---|---|
| 5.3 Privileged and trap tests | [G5 verification](gates/G5_architectural_verification/README.md); [CSR/trap plan copy](gates/G4_core_verification/CSR_TRAP_CORNER_TESTPLAN.md) | `minstret_retirement/checklist/`; `infrastructure/tb/csr_trap/`; `artifacts/csr_trap_closure_check_20261111/`; `artifacts/core_port_20261109/results.json` | Coverage closure remains open: CSR unit retained 552 checks / 0 failures, with 56 specification-pending observations; directed replay and core-port tests cover selected trap/IRQ cases, not the full privileged/trap suite. Resolve expected behavior, map bins to independent checks, and retain current-candidate closure evidence. Workbook status: In Progress. |
| 5.7 Benchmarks (transferred from Malay) | [G5 verification](gates/G5_architectural_verification/README.md); [benchmark deliverables copy](gates/G5_architectural_verification/BENCHMARK_DELIVERABLES.md); [known failures copy](gates/G5_architectural_verification/BENCHMARK_KNOWN_FAILURES.md) | `Verification/minstret_retirement/`; `benchmarks/` | Retained Dhrystone pass; CoreMark CRC match but duration criterion fails. Current integrated candidate and defensible score remain unestablished. Workbook status: Blank (cell empty). |
| 5.10 Core bug list closed | [G5 verification](gates/G5_architectural_verification/README.md) | `Verification/status/defects.csv`; Git issue register | CJ-owned, user-handled: flagged Git issues remain the user's closure work. No issue status is changed here. Workbook status: In Progress. |

## G6 — SoC verification

| Subgate | CJ document | TB / scripts | Evidence and remaining work |
|---|---|---|---|
| 6.5 End-to-end interrupt path | [G6 verification](gates/G6_soc_verification/README.md); [framework copy](gates/G6_soc_verification/G6_SOC_TESTBENCH_ARCHITECTURE.html) | `Verification/plans/soc_testbench_framework_20261104/`; `RTL_SOC/riscforge_soc_subsystem.sv` | The framework is a valid architecture/stimulus/coverage plan: it defines TB structure, event stimuli, constraints, bins, evidence capture and closure. It is not an implemented/validated SoC E2E testbench; current IRQ evidence is controller/core-level. Build the real source→route→core→handler test and retain result. Workbook status: In Progress. |
| 6.13 Trap robustness under system load | [G6 verification](gates/G6_soc_verification/README.md); [subgate record](gates/G6_soc_verification/subgates/6_13.md) | `Verification/hazard_tb/`; `minstret_retirement/checklist/`; `plans/soc_testbench_framework_20261104/04_STIMULUS_AND_COVERAGE.md` | CJ work to build: prior plan covers instruction/load/branch/M/IRQ schedules, constraints, checkers, named bin families and closure. Existing runs characterize cases but have 0 named pipeline bins closed; HZ-F001 still fails waits 0/5. Create a focused load/branch/M/IRQ trap-under-load TB and close precise effects, progress and resume. Workbook status: Blank (cell empty). |

## Shared deliverables

- [CJ evidence index copy](shared/evidence_index/CJ_EVIDENCE_INDEX_20261111.md) — prior evidence inventory; reconcile its status labels against workbook before using them as official.
- [Core architecture copy](gates/G1_architecture/Core_Microarchitecture.md), [CSR/trap model copy](gates/G1_architecture/CSR_and_Trap_Model.md), [clock/reset/pin list copy](gates/G1_architecture/Clock_Reset_CDC_and_Pinlist.md), and [SoC/boot map copy](gates/G1_architecture/SoC_Architecture_Map_Boot.md).
- [CSR/trap verification status copy](gates/G4_core_verification/CSR_TRAP_VERIFICATION_STATUS.md) and [corner test plan copy](gates/G4_core_verification/CSR_TRAP_CORNER_TESTPLAN.md).

**CJ responsibility scope for this review:** 5.2 (official ISA/RISCOF) and 6.10 (external SPI boot, transferred to Malay) are intentionally excluded and moved to [out-of-scope archive](shared/references/out_of_scope/README.md). They are not active CJ closure items in this map. 5.10 remains CJ-owned but is being handled by the user.

The copied pages retain their historic text and may contain links relative to their original location. Their canonical source paths are recorded in the per-gate README files; update the canonical source first, then refresh the copy deliberately.
