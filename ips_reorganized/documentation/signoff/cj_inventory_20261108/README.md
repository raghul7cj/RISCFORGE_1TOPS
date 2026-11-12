# CJ responsibility inventory — review 12 November 2026

**10 November local state:** `ips/` is synchronized to merged `verification_infra` commit `a91edb7...`. Use [CJ_REMAINING_WORK_20261110.md](../CJ_REMAINING_WORK_20261110.md) for all 18 current engineering obligations and [the sync review](../../../../artifacts/verification_infra_sync_20261110/REVIEW.md) for exact file changes. The inventory below remains historical evidence; no official checklist status was promoted by this sync.

**Merged core update:** [PR #15](https://github.com/raghul7cj/RISCFORGE_1TOPS/pull/15) selectively integrates the core changes into remote `verification_infra` at `a91edb7e666d5c374af70809703f52eb5513d96f`. Use the [merged status document](https://github.com/raghul7cj/RISCFORGE_1TOPS/blob/a91edb7e666d5c374af70809703f52eb5513d96f/ips_reorganized/documentation/core/MALAY_CORE_PORT_20261109.md) for current port status and remaining benchmark/RISC-DV obligations. The inventory below is the 8 November baseline, not a new gate-closure claim.

**Historical 9 November core review:** [Core claims cross-check](../../core/CORE_BUG_STATUS_20261109.md) records the pre-port source. DEF-001's load-use mask was already implemented. Selected MDU corrections were subsequently integrated; retirement counting and full campaign closure remain open as described in the current list.

Assessed 8 November 2026 from the official workbook, eight referenced discussions and targeted local evidence. CJ owns all 18 items below, including the transferred benchmark and external-SPI responsibilities. No new simulation, RTL fix, stimulus, coverage bin or expected-result change was made. The official workbook is unchanged.

**Path rebase, 11 November 2026:** `ips/Verification/doc/` was split into `plans/`, `architecture/`, `status/` and `briefs/`. The three CSR/trap `path` values in `inventory.json` were rebased and marked with `path_rebased`; their recorded `sha256` values remain the 8 November snapshot and the plan and architecture guide have since been edited, so those hashes no longer match the current files.

## What is actually done

**Formal status: 0/18 marked Done in the official workbook; 13 In Progress and 5 blank.** This is the recorded checklist state, not a claim that no engineering work exists. None is newly promoted to closed by this inventory.

- Architecture, CSR/trap and SoC map documents exist as implementation descriptions. Frozen/approved contracts remain to be established.
- Scoped IRQ unit execution has retained Xcelium evidence: 471/471 declared functional bins covered. The code report records 68.60% covered (579/844) and 66.16% code average; these are different report metrics. Neither establishes full CSR/trap or SoC path closure.
- CSR/trap skeleton is implemented and statically inspected; reset stays asserted and checking/stimulus/coverage are absent. It has no compilation or simulation qualification.
- Hazard/pipeline skeleton has semantic compilation evidence; runtime simulation and functional verification remain unperformed in its validation record.
- Peripheral-event verification has a detailed scenario plan, TB file map and delegation briefs. That thread did not implement the planned TB.
- Benchmark infrastructure is implemented, reviewed and exercised: its deliverables record four firmware builds, SoC compile/elaboration, 39 host checks and retained target runs. Counter-probe PASS is limited to its diagnostic purpose. Smoke, CoreMark and Dhrystone do not pass.
- Historical SPI evidence is real reusable work: a unit verdict reports all 1,539 words passed, and an older full-SoC boot/Timer0 record reports 52/52 checks. Current-source reproduction is still needed.
- RISCOF pass is engineer-reported in the planning thread. The locally retained older report contains a failed result; the newer passing bundle is not identified here. Preserve both facts.
- RISC-DV saved logs have 193 pass / 22 fail comparisons, with decode and precise-exception investigations. These are not a current-source regression or 22 independently diagnosed bugs.

## All 18 responsibilities

Official criteria are copied verbatim into inventory.json. The assessment below records the remaining work separately from the workbook status.

| ID | Responsibility | Current assessment | Existing plan |
|---|---|---|---|
| 1.1 | Core ISA frozen | Documented; freeze pending | Generic freeze steps only |
| 1.3 | Privilege modes frozen | Documented; freeze pending | Generic freeze steps only |
| 1.4 | CSR list frozen | Table exists; decisions pending | CSR test plan exists; freeze incomplete |
| 1.5 | Trap and interrupt model defined | Model exists; decisions pending | Detailed corner plan exists |
| 1.9 | Interrupt map frozen | Map exists; alternative unresolved | Detailed event plan exists |
| 2.7 | Memory interface unit coded | RTL exists; current qualification pending | Partial: legacy LSU + hazard scenarios |
| 2.9 | CSR block and trap logic coded | RTL exists; open correctness findings | Detailed plan; skeleton only |
| 2.10 | Compressed decoder coded (if C extension) | N/A candidate; disposition pending | No decoder work needed if no C is frozen |
| 3.4 | PLIC integrated (mandatory) | Architecture disposition pending | Gap identified; no final disposition |
| 3.6 | CLINT / CLIC integrated (mandatory) | Architecture disposition pending | Gap identified; no final disposition |
| 4.12 | Reset and interrupt entry verified | Planned; no current core pass established | Detailed plan; skeleton only |
| 5.2 | Official RISC-V ISA tests pass | Engineer reports pass; current evidence unqualified | Generic rerun step; run binding missing |
| 5.3 | Privileged / trap tests pass | Reported RISCOF scope; additional checks pending | Detailed CSR/trap plan; skeleton only |
| 5.7 | Benchmarks run | Infrastructure complete; benchmark runs failing | Detailed plan implemented; RTL closure pending |
| 5.10 | Core bug list closed | Open bugs; closure pending | Separate investigations; unified closure campaign missing |
| 6.5 | Interrupt path verified end to end | Planned; source-to-core proof pending | Detailed plan and file map; no TB implementation |
| 6.10 | Boot from external SPI flash passes | Historical unit and SoC passes; refresh pending | Historical procedure; focused qualification plan missing |
| 6.13 | Trap robustness under load passes | Scenarios planned; execution pending | Detailed cross-layer plans; implementations incomplete |

## Pending work and its documents

### 1.1 — Core ISA frozen

- **Exists:** RV32IM + Zicsr and no C are described.
- **Pending:** Confirm exact ISA string/extensions, unsupported-encoding policy and approved revision.
- **Documents:** [Core architecture](../../../documentation/signoff/Core_Microarchitecture.md); [Earlier overall action plan; dates superseded](../../../documentation/signoff/SIGNOFF_ACTION_PLAN.md).

### 1.3 — Privilege modes frozen

- **Exists:** M-mode-only implementation is described.
- **Pending:** Resolve MPP/WARL behavior against the intended M-only contract; record reviewed scope.
- **Documents:** [CSR and trap model](../../../documentation/signoff/CSR_and_Trap_Model.md); [Earlier overall action plan; dates superseded](../../../documentation/signoff/SIGNOFF_ACTION_PLAN.md).

### 1.4 — CSR list frozen

- **Exists:** CSR addresses, reset values and access masks are tabulated as coded.
- **Pending:** Agree intended WARL/read-only/unimplemented-CSR behavior, resolve observations, then freeze the table.
- **Documents:** [CSR and trap model](../../../documentation/signoff/CSR_and_Trap_Model.md); [CSR/trap scenario plan](../../../Verification/doc/plans/CSR_TRAP_CORNER_TESTPLAN.md).

### 1.5 — Trap and interrupt model defined

- **Exists:** Trap/MRET boundary, direct mtvec and IRQ ordering are documented as coded.
- **Pending:** Approve the intended trap priority, resume PC, nesting and CSR-write race rules; verify independently.
- **Documents:** [CSR and trap model](../../../documentation/signoff/CSR_and_Trap_Model.md); [CSR/trap scenario plan](../../../Verification/doc/plans/CSR_TRAP_CORNER_TESTPLAN.md).

### 1.9 — Interrupt map frozen

- **Exists:** Cause 7 and local causes 16–27, gateway modes and priority are described.
- **Pending:** Freeze source/subevent map and approved controller alternative; retain exact exception to PLIC/CLINT wording.
- **Documents:** [SoC architecture, interrupt map and boot](../../../documentation/signoff/SoC_Architecture_Map_Boot.md); [Peripheral-event and interrupt-commit scenario plan](../../../documentation/signoff/irq_event_commit_plan_20261104/PLAN.md); [Original verbal-decision record](../../../documentation/signoff/evidence_review_20261102/VERBAL_DECISIONS.md).

### 2.7 — Memory interface unit coded

- **Exists:** LSU/interface RTL exists; older LSU infrastructure can be reused.
- **Pending:** Audit current byte-enable/size/offset/sign/zero-extension/alignment/one-outstanding behavior; adapt legacy checks and run current source, including stalls/errors.
- **Documents:** [Core architecture](../../../documentation/signoff/Core_Microarchitecture.md); [Hazard and pipeline skeleton entry point](../../../Verification/hazard_tb/README.md); [CSR/trap scenario plan](../../../Verification/doc/plans/CSR_TRAP_CORNER_TESTPLAN.md).

### 2.9 — CSR block and trap logic coded

- **Exists:** CSR/trap RTL and reset-held skeleton exist.
- **Pending:** Resolve approved contract versus implementation; implement independent checking and scenarios for WARL, CSR operations/races, trap/MRET and precise effects. No current corner-suite pass.
- **Documents:** [CSR and trap model](../../../documentation/signoff/CSR_and_Trap_Model.md); [CSR/trap scenario plan](../../../Verification/doc/plans/CSR_TRAP_CORNER_TESTPLAN.md); [CSR/trap skeleton state and extension points](../../../Verification/infrastructure/tb/csr_trap/README.md); [Saved RISC-DV failures and proposed closure checks](../../../documentation/core/RISCV_DV_FAILURE_AUDIT.md); [Waveform-based RTL failure isolation](../../../benchmarks/docs/RTL_FAILURE_ISOLATION.md).

### 2.10 — Compressed decoder coded (if C extension)

- **Exists:** Architecture document states no compressed decoder.
- **Pending:** Record N/A tied to the frozen ISA and build flags; keep applicable instruction-alignment/illegal-encoding checks. Do not mark waived by inference.
- **Documents:** [Core architecture](../../../documentation/signoff/Core_Microarchitecture.md).

### 3.4 — PLIC integrated (mandatory)

- **Exists:** Current plans describe a custom in-core gateway/arbiter rather than integrated PLIC.
- **Pending:** Record explicit approved alternative with item/scope/reason/person/date, or define implementation work. Verbal report is not a per-item waiver.
- **Documents:** [SoC architecture, interrupt map and boot](../../../documentation/signoff/SoC_Architecture_Map_Boot.md); [Peripheral-event and interrupt-commit scenario plan](../../../documentation/signoff/irq_event_commit_plan_20261104/PLAN.md); [Original verbal-decision record](../../../documentation/signoff/evidence_review_20261102/VERBAL_DECISIONS.md).

### 3.6 — CLINT / CLIC integrated (mandatory)

- **Exists:** No qualifying integrated CLINT/CLIC established; software IRQ delivery is an identified gap.
- **Pending:** Resolve timer/software delivery and custom-controller alternative. Tests cannot repair tied-off/unserviced IRQ paths.
- **Documents:** [SoC architecture, interrupt map and boot](../../../documentation/signoff/SoC_Architecture_Map_Boot.md); [Peripheral-event and interrupt-commit scenario plan](../../../documentation/signoff/irq_event_commit_plan_20261104/PLAN.md); [Original verbal-decision record](../../../documentation/signoff/evidence_review_20261102/VERBAL_DECISIONS.md).

### 4.12 — Reset and interrupt entry verified

- **Exists:** Reset/entry rules and CSR/trap and pipeline harnesses exist. Hazard semantic compilation is recorded.
- **Pending:** Execute RESET_PC, clean acceptance, mtvec redirect, mepc save, MRET/resume and IRQ/CSR-race checks on current core. Compilation and arbiter-unit coverage do not close this.
- **Documents:** [CSR/trap scenario plan](../../../Verification/doc/plans/CSR_TRAP_CORNER_TESTPLAN.md); [CSR/trap skeleton state and extension points](../../../Verification/infrastructure/tb/csr_trap/README.md); [Hazard skeleton compilation and runtime limits](../../../Verification/hazard_tb/docs/validation.md); [IRQ unit scope and coverage plan](../../../Verification/IRQ_UNIT_COVERAGE_PLAN.md).

### 5.2 — Official RISC-V ISA tests pass

- **Exists:** Passing RISCOF was reported in the planning chat; the retained local report is older and includes a failure.
- **Pending:** Locate reported passing bundle and exact DUT/plugin/filelist/ISA/simulator; identify full applicable suite and exclusions; reproduce on candidate after fixes. Preserve older failure.
- **Documents:** [Historical local RISCOF report](../../../../verification/riscof/report.html); [Historical RISCOF configuration](../../../../verification/riscof/config.ini); [Earlier overall action plan; dates superseded](../../../documentation/signoff/SIGNOFF_ACTION_PLAN.md).

### 5.3 — Privileged / trap tests pass

- **Exists:** Engineer reports privilege/trap testing in RISCOF; no current qualifying pipeline/IRQ corner run established.
- **Pending:** Map actual tests to machine trap and asynchronous IRQ obligations; execute uncovered causes, ordering, MRET and CSR races. CSR tests alone do not prove interrupt entry.
- **Documents:** [Historical local RISCOF report](../../../../verification/riscof/report.html); [CSR/trap scenario plan](../../../Verification/doc/plans/CSR_TRAP_CORNER_TESTPLAN.md); [CSR/trap skeleton state and extension points](../../../Verification/infrastructure/tb/csr_trap/README.md); [Peripheral-event and interrupt-commit scenario plan](../../../documentation/signoff/irq_event_commit_plan_20261104/PLAN.md).

### 5.7 — Benchmarks run

- **Exists:** Firmware/ports, full-SoC harness, result checks, retained runs and reviews exist. Counter diagnostic ran; smoke/CoreMark/Dhrystone failed.
- **Pending:** Correct and reverify validity/older-load ordering; qualify measurement window and counters; obtain correct benchmark completion, validated result and score with reproducible configuration.
- **Documents:** [Benchmark workflow](../../../benchmarks/README.md); [Benchmark infrastructure plan](../../../benchmarks/docs/PLAN.md); [Benchmark deliverables, runs and evidence index](../../../benchmarks/docs/DELIVERABLES.md); [Benchmark runtime outcomes](../../../benchmarks/docs/KNOWN_FAILURES.md); [Waveform-based RTL failure isolation](../../../benchmarks/docs/RTL_FAILURE_ISOLATION.md); [Benchmark failure reproduction bundle](../../../benchmarks/deliverables/RTL_failure_isolation_20261104.zip).

### 5.10 — Core bug list closed

- **Exists:** Illegal-decode, younger-MDU-after-trap, benchmark validity/load-loss/counter findings have evidence. Fetch extra hold was statically analyzed.
- **Pending:** Agree priorities and individual experiments, preserve before/after bundles, close all P0/P1 on the same candidate; justify any open P2/P3. Do not merge related-looking findings without evidence.
- **Documents:** [Saved RISC-DV failures and proposed closure checks](../../../documentation/core/RISCV_DV_FAILURE_AUDIT.md); [Waveform-based RTL failure isolation](../../../benchmarks/docs/RTL_FAILURE_ISOLATION.md); [Earlier overall action plan; dates superseded](../../../documentation/signoff/SIGNOFF_ACTION_PLAN.md).

### 6.5 — Interrupt path verified end to end

- **Exists:** Peripheral event/subevent map, hardware observation layers and proposed TB files are specified. IRQ unit work is separate.
- **Pending:** Implement planned shell and engineer-owned scenarios/checkers/coverage; prove each real peripheral event through masking/priority/routing. Add acceptance/handler/MRET evidence where required.
- **Documents:** [Peripheral-event and interrupt-commit scenario plan](../../../documentation/signoff/irq_event_commit_plan_20261104/PLAN.md); [Peripheral-event proposed TB file plan](../../../documentation/signoff/irq_event_commit_plan_20261104/TB_FILE_PLAN.md); [Peripheral-event delegation briefs; not executed](../../../documentation/signoff/irq_event_commit_plan_20261104/DELEGATION_BRIEFS.md); [IRQ unit scope and coverage plan](../../../Verification/IRQ_UNIT_COVERAGE_PLAN.md).

### 6.10 — Boot from external SPI flash passes

- **Exists:** Unit verdict reports PASS for 1,539 words; Oct 19 full-SoC boot/Timer0 run reports 52/52 checks.
- **Pending:** Define current-candidate external image/flash settings, load/handoff/SRAM execution and pass proof; reproduce without preloading the payload in place of SPI transfer. Resolve boot-mode-pin departure and tool acceptance.
- **Documents:** [Historical full-SoC SPI boot evidence and limits](../../../Verification/components/memory/boot_path.md); [SPI bootloader unit passing verdict](../../../Verification/artifacts/runs/tb_bootloader_20261031_183859_f178e58b/verdict.json); [SoC architecture, interrupt map and boot](../../../documentation/signoff/SoC_Architecture_Map_Boot.md).

### 6.13 — Trap robustness under load passes

- **Exists:** CSR/trap plan and IRQ event plan include memory/branch/M-operation overlap and ordering cases.
- **Pending:** Finish scenarios/reference checks and legal latency model; demonstrate precise effects, bounded progress, correct return and declared nesting policy under load.
- **Documents:** [CSR/trap scenario plan](../../../Verification/doc/plans/CSR_TRAP_CORNER_TESTPLAN.md); [Peripheral-event and interrupt-commit scenario plan](../../../documentation/signoff/irq_event_commit_plan_20261104/PLAN.md); [Hazard and pipeline skeleton entry point](../../../Verification/hazard_tb/README.md); [Saved RISC-DV failures and proposed closure checks](../../../documentation/core/RISCV_DV_FAILURE_AUDIT.md); [Waveform-based RTL failure isolation](../../../benchmarks/docs/RTL_FAILURE_ISOLATION.md).

## What still needs a concrete plan

“Missing” below means no dedicated current-candidate execution/closure plan was established in the inspected material. Generic task lists exist. Detailed scenario plans for CSR/trap, hazard overlaps, peripheral events and benchmarks should be reused.

| Work package | Items supported | Missing planning content |
|---|---|---|
| Architecture freeze and exact dispositions | 1.1, 1.3–1.5, 1.9, 2.10, 3.4, 3.6 | One reviewed decision record for ISA, privilege/WARL/trap rules, C=N/A and controller alternative; exact approving identity/date/scope; software/external IRQ delivery decision. |
| Current LSU qualification | 2.7; supports 6.13 | Legacy-bench compatibility audit, feature-to-test matrix, size/offset/sign/error/stall expectations, one-outstanding checks and runnable current filelist. Hazard corner plans cover overlap, not all LSU behavior. |
| RISCOF evidence recovery and rerun | 5.2, 5.3 | Locate newest passing bundle; enumerate applicable tests, bind plugin and actual compiled source, accepted simulator, signatures and reproducer; identify missing asynchronous-IRQ tests. |
| Unified bug closure campaign | 5.10; blocks 2.9, 5.3, 5.7, 6.13 | Merge references into an issue register without conflating mechanisms; assign severity, minimal experiment, fix revision, before/after evidence and regression obligations. Existing reports have proposed checks, not executed closure. |
| Current external-SPI boot qualification | 6.10 | Current image/flash command/configuration, no-payload-preload cold boot, transfer integrity, core release, ROM handoff, SRAM fetch and independent result checks; identify boot strap exception and simulator of record. |
| Final common-candidate evidence release | All 18 | Choose the candidate/source manifest, scenario/coverage acceptance, legal latency bounds, runner commands and package index. Assign review dispositions and record remaining gaps for 12 November. |

### Planned work that is still unimplemented

- CSR/trap: implement engineer-owned reference model, stimulus and coverage hooks; replace placeholder memories with the reviewed interface contract before functional runs.
- Hazard/pipeline: implement user extensions and run in a capable simulator. Slang compilation does not establish executable lifecycle or checked scenarios.
- Peripheral events: implement the already specified TB shell, then engineer-owned event scenarios/checking/coverage. Start with Timer0 before expanding to all sources/subevents.
- Trap-under-load: reuse both detailed plans, but bind scenarios, memory schedules, observation/checker IDs and completion criteria to actual executable tests.
- Benchmark: infrastructure is available. RTL failure correction/reverification and measurement qualification remain; more infrastructure scaffolding is not the immediate need.

## Open engineering findings to carry into 5.10

| Finding | Evidence level | Required next experiment |
|---|---|---|
| Illegal subencoding accepted as legal | Saved illegal seed 22 plus static local opcode-only decoder; other 18 illegal failing seeds not individually attributed | Execute the illegal word 0x460446b3 on the candidate, check cause 2/mepc/no destination or younger effects; independent legality matrix. |
| Younger DIV/REM survives older synchronous trap | Saved remote traces; current local abort path differs and applicability is static | Directed older trap plus younger M operation, including issue/kill/completion coincidence; check GPR, CSR and memory effects. |
| Completed MDU result loses valid packet | Reproduced full-SoC benchmark waveforms | Minimal normal M operation with ownership/valid tracking through WB, dependent consumer and exactly-once write. |
| Younger M start flushes older waiting load | Reproduced full-SoC benchmark waveforms | Older load held by legal wait, younger M issue; prove older completion and ordered result preservation. |
| minstret repeats for held WB packet | Reproduced benchmark waveform observation | Compare unique architectural retirements with increments during a deliberately bounded memory wait and measurement window. |
| Fetch target held for an extra cycle | Static analysis in fetch discussion; no closure simulation established | Candidate waveform for target request/return/IF-ID acceptance, then redirect/stall/trap neighbors. Treat performance priority separately from correctness. |

These findings may share control logic, but that does not prove a shared correction. Severity is for CJ to approve; architectural corruption must be triaged before declaring 5.10 closed. Historical fixed-bug notes under `bug fixes/` remain history until reverified on the candidate.

## Proposed order through 12 November

This is a proposed sequence for review, not authorization for functional changes or a promise to close all items in four days.

1. **8 November: establish the baseline and decisions.** Review the inventory, recover current RISCOF evidence, choose the exact source/filelist and simulator, resolve architecture/disposition questions, prioritize correctness findings. Prepare the current SPI qualification procedure using retained evidence.
2. **9–10 November: focused engineering.** CJ develops hypotheses/corrections; run distinguishing tests for MDU validity, older-load preservation, trap cancellation and decode legality. Complete only the harness/checker extensions needed for these tests. Fetch work can proceed at the priority CJ chooses.
3. **10–11 November: reverify on one candidate.** Rerun applicable architectural tests and targeted CSR/trap/IRQ checks after corrections. Exercise legal data-latency schedules and precise side effects. Reproduce external-SPI boot. Benchmark smoke precedes correct-result benchmark runs and measurement.
4. **12 November: present evidence and explicit gaps.** Link each run to its item and source snapshot; retain failed baselines and open issues. Update official status only where the exact criterion and required disposition are satisfied.

Dependencies outside these 18 IDs remain relevant: memory-latency randomization (5.6), riscv-dv integration/regression (5.4/5.5), hazard/MDU unit coverage and whole-project gates. Supporting work does not transfer those owners or close their checklist rows.

## Evidence discipline and tracker use

For each run retain: run ID/time, checklist IDs, RTL and harness filelist/parameter hashes, dirty-source manifest or revision, test/firmware/image hashes, compiler/simulator/reference versions, exact command, ISA/memory/clock configuration, seed or latency schedule, independent expected results, exit status, raw logs/signatures, required waveform slice, checked coverage and verdict. Store a failure before a correction and a separate rerun afterward.

Use inventory.json as the structured inventory and this file as its readable view. Change an item only with new evidence/disposition; do not infer a pass from a skeleton, simulation exit code, working game, final GPR convergence or a benchmark counter-liveness check. Per-item closing review remains distinct from an implementation claim.

The original verbal-decision Markdown explicitly lacks per-item attestation. The older interactive dashboard describes broader approvals; this inventory follows the original record and does not invent an approved waiver. Architecture departures, simulator acceptance and final gate approval are separate.

No Git clean-state claim is made: git was unavailable on this shell PATH. inventory.json hashes the inspected local evidence and official workbook; historical source equivalence remains subject to each run manifest.

## Document and discussion index

- **ARCH:** [Core architecture](../../../documentation/signoff/Core_Microarchitecture.md)
- **CSR:** [CSR and trap model](../../../documentation/signoff/CSR_and_Trap_Model.md)
- **SOC:** [SoC architecture, interrupt map and boot](../../../documentation/signoff/SoC_Architecture_Map_Boot.md)
- **DECISIONS:** [Original verbal-decision record](../../../documentation/signoff/evidence_review_20261102/VERBAL_DECISIONS.md)
- **OLDPLAN:** [Earlier overall action plan; dates superseded](../../../documentation/signoff/SIGNOFF_ACTION_PLAN.md)
- **CSRPLAN:** [CSR/trap scenario plan](../../../Verification/doc/plans/CSR_TRAP_CORNER_TESTPLAN.md)
- **CSRBRIEF:** [CSR/trap skeleton brief](../../../Verification/doc/briefs/csr_trap/CSR_TRAP_SKELETON_BRIEF.md)
- **CSRHTML:** [CSR/trap architecture guide](../../../Verification/doc/architecture/CSR_TRAP_TESTBENCH_ARCHITECTURE.html)
- **CSRREADY:** [CSR/trap skeleton state and extension points](../../../Verification/infrastructure/tb/csr_trap/README.md)
- **HAZARD:** [Hazard and pipeline skeleton entry point](../../../Verification/hazard_tb/README.md)
- **HAZHTML:** [Hazard and pipeline architecture](../../../Verification/hazard_tb/docs/architecture.html)
- **HAZVALID:** [Hazard skeleton compilation and runtime limits](../../../Verification/hazard_tb/docs/validation.md)
- **IRQPLAN:** [Peripheral-event and interrupt-commit scenario plan](../../../documentation/signoff/irq_event_commit_plan_20261104/PLAN.md)
- **IRQFILES:** [Peripheral-event proposed TB file plan](../../../documentation/signoff/irq_event_commit_plan_20261104/TB_FILE_PLAN.md)
- **IRQBRIEF:** [Peripheral-event delegation briefs; not executed](../../../documentation/signoff/irq_event_commit_plan_20261104/DELEGATION_BRIEFS.md)
- **IRQUNIT:** [IRQ unit scope and coverage plan](../../../Verification/IRQ_UNIT_COVERAGE_PLAN.md)
- **IRQFUNC:** [Retained IRQ unit functional coverage](../../../Verification/artifacts/xcelium_irq_20261030_004317/functional_summary.txt)
- **IRQCODE:** [Retained IRQ unit code coverage and scope limits](../../../Verification/artifacts/xcelium_irq_20261030_004317/code_summary.txt)
- **DV:** [Saved RISC-DV failures and proposed closure checks](../../../documentation/core/RISCV_DV_FAILURE_AUDIT.md)
- **DVHTML:** [RISC-DV failure report](../../../documentation/core/RISCV_DV_FAILURE_AUDIT.html)
- **RISCOF:** [Historical local RISCOF report](../../../../verification/riscof/report.html)
- **RISCONF:** [Historical RISCOF configuration](../../../../verification/riscof/config.ini)
- **BENCH:** [Benchmark workflow](../../../benchmarks/README.md)
- **BENCHPLAN:** [Benchmark infrastructure plan](../../../benchmarks/docs/PLAN.md)
- **BENCHDONE:** [Benchmark deliverables, runs and evidence index](../../../benchmarks/docs/DELIVERABLES.md)
- **BENCHFAIL:** [Benchmark runtime outcomes](../../../benchmarks/docs/KNOWN_FAILURES.md)
- **ISOLATION:** [Waveform-based RTL failure isolation](../../../benchmarks/docs/RTL_FAILURE_ISOLATION.md)
- **REPRO:** [Benchmark failure reproduction bundle](../../../benchmarks/deliverables/RTL_failure_isolation_20261104.zip)
- **BOOT:** [Historical full-SoC SPI boot evidence and limits](../../../Verification/components/memory/boot_path.md)
- **BOOTUNIT:** [SPI bootloader unit passing verdict](../../../Verification/artifacts/runs/tb_bootloader_20261031_183859_f178e58b/verdict.json)

### Referenced discussions

These discussions supply context and ownership history; their conclusions are bounded by the local evidence linked above.

- Debug RISC-DV: <t3-thread://v2/e1cc5bc4-c32d-4a6f-a00b-2dff41d3f6db/0ce99a5f-d80e-42bb-bdd5-c644e4af9539>
- Plan 1TOPS Tapeout Signoff: <t3-thread://v2/e1cc5bc4-c32d-4a6f-a00b-2dff41d3f6db/7963c045-979d-46a2-bdd8-94ab74c47050>
- CSR TRAP coverage closurre: <t3-thread://v2/e1cc5bc4-c32d-4a6f-a00b-2dff41d3f6db/7a224d12-7ef4-4a42-8657-b4995729ee0e>
- Pipeline Hazard Unit Testbench: <t3-thread://v2/e1cc5bc4-c32d-4a6f-a00b-2dff41d3f6db/4164adbc-b4fe-4135-9793-7460cedd9307>
- peripheral event verification: <t3-thread://v2/e1cc5bc4-c32d-4a6f-a00b-2dff41d3f6db/80922e17-afa8-426b-829a-a3ee63dc0daa>
- Core benchmark: <t3-thread://v2/e1cc5bc4-c32d-4a6f-a00b-2dff41d3f6db/910b6c7f-437f-427d-a12f-507d12e488b1>
- Evidence and Decision Tracker: <t3-thread://v2/e1cc5bc4-c32d-4a6f-a00b-2dff41d3f6db/4a32ff25-b0bd-492f-8ac3-ce2342e83be9>
- Fix Fetch Branch Delay Bug: <t3-thread://v2/e1cc5bc4-c32d-4a6f-a00b-2dff41d3f6db/128053f2-ae43-4c16-bc50-d6e41eb0e1cc>
