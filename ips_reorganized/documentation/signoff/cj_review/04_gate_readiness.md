# CJ gate readiness — current review snapshot

Reviewed 10 November 2026. **Open work remains; this is not technical signoff, a gate approval, or a tapeout freeze.** This document maps exactly the 18 CJ responsibilities in the [8 November inventory][inventory]. It preserves official status and approval cells. The concise [HTML reviewer dashboard](04_gate_readiness.html) carries the same conclusions.

[Review home](README.md) · [Core architecture](01_core_architecture.md) · [Verification architecture](02_verification_architecture.md) · [Benchmark and SPI evidence](03_benchmark_spi_evidence.md) · [Gate readiness](04_gate_readiness.md)


## Authority, identity and corrections

- Source baseline: `verification_infra/ips_reorganized` at `a91edb7e666d5c374af70809703f52eb5513d96f`. Local `ips/` is an augmented offline copy, not a Git checkout. This review compared 14 selected source/TB files with the retained pinned snapshot and found matching SHA-256 values; that is a bounded fingerprint check, not a whole-workspace clean-state assertion. Parent packaging owns final hashes. See [offline identity][identity] and [sync review][sync].
- The [finding reconciliation][reconciliation] owns current finding disposition and the 35 historical B1–B21/V1–V14 entries. The [remaining-work list][remaining] owns execution obligations. This page is their reviewer map, not a second full defect ledger. Issue states below are those recorded in these local 10 November documents; no live tracker query was performed here.
- **Issue #17 / CORE-JALR is withdrawn.** `Main_Decoder` selects ALUOp `11`, `ALU_Decoder` selects `0110`, and [ALU.v][alu] computes `(A+B)&~1` before execute alignment. Raw target sums ending in `01` and `11` remain runtime coverage work, not a missing-mask bug.
- The integrated PR15 changes cover MDU valid/hold/origin/owner/cancel, cancellation of every multiplier valid stage, older-load preservation, redirect/link preservation while memory waits, RS2 hazard qualification, legality guards, software-write `mepc` masking, fetch-region faults and SoC wiring. [Retained development evidence][post-sync] establishes selected checks; it does not close original workloads or saved seeds.
- **Correction to the historical dashboard:** its definite waiver/approval language, including the account of six approved departures and UVM/tool acceptance, overstates the [verbal-decision record][verbal]. That record supplies no exact per-item scope, approving person or date. Controller alternatives, UVM, tools and boot pin departures remain unresolved; no-C applicability is an N/A candidate, not an inferred waiver. Do not promote approval cells from those claims.
- The historical inventory recorded **0 Done, 13 In Progress, 5 blank** on 8 November. The workbook was neither freshly read nor edited in this review. Every per-item status quoted below is historical inventory evidence, unchanged. The inventory's 12 November review date is a recorded planning date, not a new commitment.

## Read evidence in separate stages

| Stage | What is present | What it does not establish |
| --- | --- | --- |
| Plan / intended contract | Architecture descriptions, CSR/trap and peripheral-event plans; unresolved freeze decisions | An approved contract, executable stimulus or a passing check |
| Built / static inspection | Integrated core corrections, LSU/CSR/controller RTL; reset-held CSR skeleton and layered hazard skeleton | Runtime correctness or coverage of the planned scenarios |
| Compilation / elaboration | Historical hazard Slang semantic compilation; retained full-SoC Verilator zero errors / 107 warnings | Simulation, accepted-tool signoff or waived warnings |
| Run / effective checks | Focused core firmware checks, legality sweep and owner/abort leaf checks; historical IRQ/boot/benchmark artifacts | Full architectural, precise-effects, benchmark or system closure |
| Closure / item disposition | Requires criterion-specific evidence, reviewed scope and authorized disposition | A merged correction, green development log or a passing system demo alone does not close an item |

The independent expectation must come from the frozen contract, architectural reference, arithmetic or an independent effect ledger. Copying the DUT's present policy into a predictor does not resolve an intent mismatch. CJ owns stimulus, reference model, coverage and closure reasoning. Required architectural/coach and tool decisions need an identified approver; none is assigned by this document.

## Retained evidence and limits

| Evidence | Inspected basis and supported claim | Pending boundary |
| --- | --- | --- |
| Current-source development checks | [Post-sync record][post-sync], [13 core results][core-results], [legality log][legality-log], [owner/abort log][owner-log]. Icarus development flow; 13 directed configurations, 131,072 opcode/funct3/funct7 combinations plus exact SYSTEM guards, four owner/abort checks. Core arithmetic/load/redirect cases include 0/1/4-cycle waits. | No broad RISCOF, saved RISC-DV, complete SoC benchmark, coverage closure or board qualification. The legality sweep excludes full CSR access/state policy. Short-image `readmemh` warnings remain visible. |
| Checker meaning | [Core harness][core-tb] and [runner][core-runner]: firmware computes expected values and writes the reserved result address. Value 1 passes; another value or the bounded watchdog fails. Historical [base load/MUL failure][base-load] and [post-sync candidate result][candidate-load] retain the negative and positive observations. | This is a selected firmware result, not a unique-retirement oracle or proof of all externally visible effects. The source, program and run configurations must remain attached. |
| Full-SoC tool evidence | [Verilator log][soc-lint] and [original integration validation][port-validation]: Verilator 5.020, tier3 SoC filelist, `--lint-only --timing -DXSIM -Wno-fatal`; zero errors, 107 retained warnings. | Compatibility disables some unsupported assertions. This is development lint/elaboration, not clean VCS/SpyGlass acceptance. No warning waiver is inferred. |
| Harness readiness | [CSR skeleton README][csr-skeleton]: static port/path audit, reset held, no implemented model/stimulus/bins; no compile/runtime result. [Hazard validation][hazard-validation]: Slang unit 0 errors/0 warnings; pipeline 0 errors/3 warnings; Verilator stopped at clocking-block support. | CSR skeleton is `SKELETON/INCOMPLETE`; hazard semantic compilation does not demonstrate checks or runtime. CJ hooks remain engineering work. |
| IRQ unit | [Functional summary][irq-functional] retains 471/471 declared bins for `tb_irq_restructure`; [scope plan][irq-unit] defines the unit boundary. | It does not qualify the faulty SoC IRQ predictor, real peripheral pins/subevents, core entry/return or system load. This number is a retained unit result, not a readiness percentage. |
| Architectural software | [Historical RISC-DV audit][dv-audit] records 193/215 pass and 22 fail under its limited GPR comparator. Newer passing RISCOF was engineer-reported; the [local report][riscof] and [config][riscof-config] are historical. | 22 is an outcome count, not bug count or current failure rate. Recover the newer pass bundle; bind DUT/plugin/ISA/reference/images. Retire logging, repeated-PC suppression and extra-row truncation require qualification under #22. |
| Workloads and external boot | [Benchmark failures][bench-fail] retain smoke arithmetic failure, CoreMark initialization trap, Dhrystone output-path trap and limited counter-probe pass. [Boot record][boot] retains Oct 19 SoC 52/52 with staged bench/filelist; [Oct 31 unit verdict][boot-unit] retains 1,539 words, commit unknown. | Corrections address selected mechanisms, not complete workload results. Boot proof must be reproduced on the current candidate with real SPI transfer and executed-result evidence; payload preload cannot substitute. |

No simulations, builds, waveform generation, Git writes, expectation changes or official-status edits were performed for this documentation review. Retained runs retain their own dates and source identities.

## All 18 CJ responsibilities

The criterion text and quoted historical status come from [inventory.json][inventory]. Each row separates an implementation/evidence basis from the still-pending decision or test. **CJ is the item owner for every row.** A named coach/tool approver remains to be identified where acceptance is needed. The linked work product is the owning place for closure evidence; it is not already a closure record.

### Architecture and applicability

| ID · intended criterion · historical official status | Existing implementation / evidence | Pending gap or decision · relevant issue | Next closure evidence / owner / document |
| --- | --- | --- | --- |
| **1.1 — Core ISA frozen.** One of RV32I / RV32IM / RV32IMC declared in writing. **In Progress.** | RV32IM/Zicsr and no-C described; legality guards are integrated and the field sweep passed within its declared scope. See [core architecture](01_core_architecture.md), [decoder][decoder] and [legality log][legality-log]. | Freeze exact ISA/extensions, supported FENCE/WFI policy and unsupported encodings against source/build flags. #22 qualification; #19 timing separate. #17 withdrawn. | **CJ:** publish reviewed declaration with exact revision/configuration and architecture decision provenance in [core architecture](01_core_architecture.md); then bind official-test applicability. |
| **1.3 — Privilege modes frozen.** Machine mode minimum; Supervisor + MMU only if targeting Linux. **In Progress.** | M-only implementation described; [CSR RTL][csr] exposes current MPP/MRET behavior. | Intended privilege/MPP/WARL behavior remains to be agreed; as-coded policy is not the approved specification. #20. | **CJ + identified architecture approver:** record accepted M-only contract, required WARL behavior and out-of-scope modes in [core architecture](01_core_architecture.md); retain decision scope/person/date. |
| **1.4 — CSR list frozen.** Table of implemented CSRs with reset values and access type (RW/RO/WARL). **In Progress.** | CSR implementation exists, including custom `mintprio` at `0x7C0` and corrected software-write `mepc` mask. Older table remains historical. | Reconcile addresses, resets, masks, read-only/unsupported accesses and unconnected `csr_valid_o`; do not delete custom policy by importing another branch. #20; #28 stale-map triage. | **CJ:** compare the intended table against [CSR RTL][csr], record approved exceptions and feed an independent access/WARL model. Maintain [core architecture](01_core_architecture.md) and [CSR test plan][csr-plan]. |
| **1.5 — Trap and interrupt model defined.** mtvec mode, mepc/mcause behaviour, nested-interrupt policy and trap boundary written down. **In Progress.** | Direct trap/MRET path, selected cause metadata and MDU cancellation checks exist; no automatic hardware shadow stack is established. | Freeze boundary/resume PC, synchronous/IRQ priority, eligibility relative to older CSR writes, and nesting. Do not accept the existing predictor's stack as intent. #20/#21/#25. | **CJ + identified architecture approver:** write expected edge/order rules in [core architecture](01_core_architecture.md); map each collision to an independent check in [CSR plan][csr-plan] before interpreting runtime results. |
| **1.9 — Interrupt map frozen.** Every source numbered and mapped to a PLIC/CLINT input, with priority scheme stated. **In Progress.** | Custom gateway/arbiter map has 13 inputs: cause 7 and 16–27; [event plan][event-plan] records source/subevent, capture modes and priority/RR order. | Freeze subevents, masks, capture/rearm and priority with exact controller disposition. Existing GPIO and IRQ predictors cannot qualify it unchanged. #25/#27/#28. | **CJ + identified architecture approver:** reconcile [SoC map][soc-history] with current source and accepted alternative in [core architecture](01_core_architecture.md); retain source/subevent-to-test evidence in [event plan][event-plan]. |
| **2.10 — Compressed decoder coded (if C extension).** 16-bit instructions expand correctly; misaligned fetch handled. **Blank.** | Current configuration describes no C decoder; instruction alignment and legality still apply. | Explicit N/A depends on frozen ISA and build flags. No inferred waiver. JALR low-bit coverage remains applicable; #17 withdrawn, #20 contract context. | **CJ:** record conditional N/A and supporting `-march`/configuration identity after 1.1; preserve no-C target-alignment checks in [core architecture](01_core_architecture.md) and [verification map](02_verification_architecture.md). |
| **3.4 — PLIC integrated (mandatory).** 16-32 sources supported; every peripheral interrupt wired in. **Blank.** | Current integrated design uses a 13-source in-core custom gateway/arbiter, not a demonstrated integrated PLIC. | This implementation does not itself satisfy the workbook wording. Exact approved alternative/waiver or required implementation scope is absent. #25/#28; architecture register #24. | **CJ + identified coach/architecture approver:** retain item, scope, reason, alternative, person and date in the [decision record][verbal] and [core architecture](01_core_architecture.md), or create separately authorized implementation work. Then test accepted scope. |
| **3.6 — CLINT / CLIC integrated (mandatory).** Timer and software interrupts reach the core. **Blank.** | Timer/custom fast paths exist; SoC software/external IRQ inputs are tied low. A standalone CLIC directory is not integration evidence. | Resolve software/timer delivery and exact CLINT/CLIC/custom-controller disposition. Testing cannot create a tied-off path. #20/#25/#28; #24 delivery gap. | **CJ + identified coach/architecture approver:** document accepted source delivery and criterion disposition in [core architecture](01_core_architecture.md) / [event plan][event-plan]; implement and test any required new path only under separate authorization. |

### Implementation and core qualification

| ID · intended criterion · historical official status | Existing implementation / evidence | Pending gap or decision · relevant issue | Next closure evidence / owner / document |
| --- | --- | --- | --- |
| **2.7 — Memory interface unit coded.** Byte enables, store alignment, load sign/zero extension, one outstanding transaction. **In Progress.** | LSU RTL exists; retained core tests check selected load/MDU wait combinations and older-load preservation. [Core development record][core-results]. | Current-candidate size/offset/strobe/sign-extension/alignment/error/latency and effect qualification remains. DEF-001 exact MMIO→DSRAM reproducer/regressions remain distinct. #21/#28. | **CJ:** build feature-to-test map in [verification architecture](02_verification_architecture.md), reusing LSU/hazard infrastructure with legal timing and accepted-transaction ledger; retain current-source checks and exact DEF-001 before/after evidence. |
| **2.9 — CSR block and trap logic coded.** Matches the CSR table and trap model frozen in G1. **In Progress.** | CSR/trap RTL and selected integrated corrections; [CSR harness][csr-skeleton] is connected but reset-held and incomplete. | Frozen G1 expectations and independent model/stimulus/bins are missing. No current corner-suite pass. #20/#21/#25/#26. | **CJ:** implement the owned hooks only after contract review, then compile/elaborate and run WARL, operations, collisions and MRET scenarios; link actual checks/results in [CSR plan][csr-plan] and [verification architecture](02_verification_architecture.md). |
| **4.12 — Reset and interrupt entry verified.** Fetch starts at RESET_PC; IRQ taken at a clean boundary; mtvec jump and mepc save correct. **In Progress.** | Selected core trap metadata/MDU guards, historical IRQ unit checks and harnesses exist. These are partial evidence. | Full current reset/eligibility/entry path is not qualified by unit bins or semantic compilation. Legacy DIV/IRQ checker and predictor defects must be handled. #21/#25/#26. | **CJ:** retain RESET_PC, clean acceptance, committed cause/PC/state/redirect and negative eligibility checks; connect handler/MRET/resume as shared extra scope for 5.3/6.13. Maintain [CSR plan][csr-plan] / [verification architecture](02_verification_architecture.md). |
| **5.2 — Official RISC-V ISA tests pass.** 100% pass on rv32ui, plus rv32um if M and rv32uc if C are supported. **In Progress.** | Newer passing RISCOF is engineer-reported; historical local report/config exist. Current legality development checks are separate. | Newer pass not bound to this candidate; exact DUT/plugin/reference/simulator/suite applicability unresolved. Historical failed report is preserved, not treated as disproof of the reported newer pass. #22. | **CJ:** recover newer bundle and identify suite/signatures/exclusions, compile source and reference identity; perform separately authorized current candidate run and retain all applicable outcomes in [verification architecture](02_verification_architecture.md) and the [RISCOF folder][riscof-folder]. |
| **5.3 — Privileged / trap tests pass.** Minimal machine-mode trap and interrupt tests pass. **In Progress.** | Engineer-reported RISCOF trap scope and focused illegal/ECALL/`mepc` guards exist; detailed CSR/trap plan is built only as a skeleton. | Official-test coverage of async IRQ, CSR races, MRET and precise effects is not established. #20/#21/#22/#26. | **CJ:** map applicable machine-mode causes and asynchronous collision windows to independent expectations and effective checks, then retain current-source tests/results in [CSR plan][csr-plan] / [verification architecture](02_verification_architecture.md). |
| **5.10 — Core bug list closed.** All P0/P1 bugs fixed and re-verified; open P2/P3 listed with justification. **In Progress.** | PR15 corrections have scoped evidence; five recorded open bug-labelled issues remain, plus separate qualification work. | #16/#18/#25/#26/#27 remain open. #17 is withdrawn. #19–#23/#28 are investigation/contract/qualification/legacy triage, not six more reproduced bugs. Priority/closure decisions are not invented here. | **CJ; independent closer to be identified:** preserve current reproducers and before/after evidence, agree severity and required regression, rerun saved seeds on one bound candidate and justify allowed open lower-severity items. [Reconciliation][reconciliation] and [DEF ledger][defects] own disposition. |

### Workload and system evidence

| ID · intended criterion · historical official status | Existing implementation / evidence | Pending gap or decision · relevant issue | Next closure evidence / owner / document |
| --- | --- | --- | --- |
| **5.7 — Benchmarks run.** Dhrystone and/or CoreMark complete with correct results; score recorded. **Blank.** | Firmware/ports/harness and historical workload failures retained. Selected MDU/load/redirect corrections now have development evidence. | No correct-result complete workload or defensible score on current integrated SoC. Held-WB `minstret` overcount #16 blocks instruction-count/CPI claims; #19 timing is investigatory; #23 workload qualification. #17 withdrawn. | **CJ:** bind ELF/images/build/SoC, smoke first, then complete correct-result benchmark; qualify counter/window and score method/duration. Maintain [benchmark/SPI evidence](03_benchmark_spi_evidence.md) and [benchmark deliverables][bench-deliverables]. |
| **6.5 — Interrupt path verified end to end.** Every source verified from peripheral event to controller input; masking and priority checked. **In Progress.** | Historical controller unit bins and detailed [real-event plan][event-plan] exist. The plan does not establish its proposed TB implementation. | Real pin/protocol/timer events and per-source/subevent masking/winner/priority checks pending; #25 IRQ predictor and #27 GPIO predictor require qualified expectations, #28 legacy triage. | **CJ:** implement and qualify actual source stimuli, event ledger and checker negatives, then retain all 13 input/subevent results in [event plan][event-plan] / [verification architecture](02_verification_architecture.md). **This criterion ends at controller input/masking/priority; handler/MRET belong to 4.12/5.3/6.13.** |
| **6.10 — Boot from external SPI flash passes.** Boot mode pin = 1: code fetched from the SPI flash model and executed. **In Progress.** | Historical Oct 31 bootloader 1,539-word verdict and Oct 19 SoC 52/52 checks include real SPI/SRAM/result observations under their recorded setup. | Not current-candidate proof; staged bench/filelist and unknown unit commit limit binding. Resolve boot-mode-pin departure and tool acceptance explicitly. #28 provenance/legacy context; current boot run record missing. | **CJ + identified approver for departures:** retain flash/image/protocol identity, real transfer, SRAM byte integrity, core release, ROM→SRAM handoff and independent executed-result proof in [benchmark/SPI evidence](03_benchmark_spi_evidence.md) / [boot record][boot]. |
| **6.13 — Trap robustness under load passes.** Interrupts during load/store/branch-dense code; nested interrupt policy exercised if supported. **Blank.** | CSR/trap/event/hazard plans and selected MDU cancellation/hold guards exist. | Planned legal load/branch/M/IRQ schedules have no full runtime qualification. Need precise GPR/CSR/store/MMIO effects, bounded progress, return and declared nesting; no assumed hardware stack. #21/#22/#25/#26. | **CJ:** after oracle/contract readiness, schedule arrivals across MDU issue/busy/done, older stalls and trap completion; check accepted effects exactly once and resume. Extend [CSR plan][csr-plan], [event plan][event-plan] and [verification architecture](02_verification_architecture.md) with run IDs and limits. |

## Issue disposition without duplicating the legacy register

| Recorded category | Items and evidence boundary | Required reviewer action |
| --- | --- | --- |
| Open RTL/static core defects | **#16:** historical held-WB overcount waveform and unchanged `valid_W & ~exc_valid_W` input in [top.v][core-top]. **#18:** RS2 qualified, RS1 still drawn from raw instruction fields in [decode_cycle.v][decode]. | Current reproducers and independent checks; agree correction and severity. Neither is closed by the integration. |
| Open TB/reference bugs | **#25:** [IRQ predictor][irq-predictor] models an absent hardware stack, wrong classes and no expected-winner arbitration. **#26:** [legacy TB][legacy-tb] has no explicit failure after its trap wait expires and an unbounded busy loop; [assembly][legacy-asm] uses 1,000,000/7 while TB expects 33,333. **#27:** [register predictor][reg-predictor] treats INFO/CFG/RISE_EN/FALL_EN as aliases; [GPIO package][gpio-package] places status at `0x580`. | Bind actual loaded HEX before changing an expectation; approve IRQ defer/abort policy first. Qualify repaired models with negative cases and runtime checks. These are verification bugs, not three new CPU execution failures. |
| Withdrawn | **#17**, missing JALR mask allegation. Decode→ALU chain supplies the mask. | Keep correction visible in historical documents; schedule coverage without an RTL defect claim. |
| Investigation / contract / qualification | **#19** fetch recovery timing; **#20** CSR/privilege contract; **#21** broader precise effects/ordering; **#22** RISC-DV/comparator/current campaign; **#23** benchmarks. **#24** is the umbrella responsibility register. | Preserve uncertainties and define distinguishing observations. Do not rebrand every risk as a reproduced bug. |
| Legacy triage | **#28** owns B1–B21/V1–V14, 35 historical entries. DEF-001 has a specific remaining closure; DEF-002/003/006/007/009 record corrected/verified, DEF-004 convergence; DEF-005/008/010/011/012 require scoped review. | Use the [owning reconciliation][reconciliation] and [DEF ledger][defects]. Do not revive superseded claims or label all 35 active bugs. Stored failure reports may be intended watchdog negative tests; bind purpose before interpreting verdict. |

Local records link to [GitHub umbrella #24](https://github.com/raghul7cj/RISCFORGE_1TOPS/issues/24) and child issues. This snapshot does not replace that tracker or claim a new live tracker audit.

## Dependency sequence and actionable decisions

The following actions describe evidence dependencies; none changes item disposition.

1. **Bind the candidate.** CJ records source hashes including local-only/generated inputs, active top/filelist, defines/parameters, tool/version/command, image/ELF hashes, seed/reference and pass criterion. The sync's identity is retained history; remote Cadence inputs are separate until matched.
2. **Resolve the contract and departures.** CJ prepares exact ISA/no-C, CSR/WARL, trap ordering/resume/nesting, source/subevent capture and controller decisions. An identified authorized approver must disposition the PLIC/CLINT/CLIC, boot-pin and tool departures. UVM disposition remains a separate obligation; a SystemVerilog bench does not silently waive it.
3. **Make the observation trustworthy.** Review #16/#18 and #25–#27, bind the DIV HEX, and define unique retirement/accepted memory effects, extra/missing trace-row rejection and negative checker tests. Preserve existing expectations until the contract resolves a disagreement.
4. **Close one bounded defect before broadening.** Retain current failure, source/TB identity, independent expectation and decisive observation; review any separately authorized correction and required regressions. Distinguish original DEF-001 regression from related load/MDU passes.
5. **Run the criterion-specific campaigns when authorized.** Restore saved RISC-DV seeds/images/reference; applicable official suite; smoke then correct-result CoreMark/Dhrystone; real peripheral events and current external SPI. Counter correctness is required before CPI/instruction counts. A short benchmark image may establish correctness without a compliant published score.
6. **Extend to interaction and package closure.** Check legal latency/load/branch/M/IRQ schedules, all allowed external effects and return/nesting. Each item needs its contract, immutable input identity, actual command/tool, effective checks, outcomes including failures, coverage scope, unresolved limits, owner and reviewed disposition. The official workbook owner decides any status update outside this task.

The [learning route][learning] starts with an older load held in MEM while a younger MUL occupies EX. CJ's useful checkpoint is to sketch ownership before/after the relevant edge: why the older load survives, when M issues and completes, where its result is held, and which external effect happens exactly once. Then explain what the firmware pass proves and what an independent effect ledger must add. This supports understanding; it is not an invented approval gate.

## Source and historical-document index

The current [core](01_core_architecture.md), [verification](02_verification_architecture.md) and [benchmark/SPI](03_benchmark_spi_evidence.md) pairs own detailed mechanisms. Older [microarchitecture][arch-history], [CSR/trap model][csr-history], [SoC map][soc-history], [pre-port bug status][core-history] and [dashboard][dashboard-history] are preserved as historical evidence. Their pre-port missing-fix or approval statements require the reconciliation corrections above; they were not rewritten here.

[inventory]: ../cj_inventory_20261108/inventory.json
[reconciliation]: ../CJ_FINDING_RECONCILIATION_20261110.md
[remaining]: ../CJ_REMAINING_WORK_20261110.md
[learning]: ../cj_learning/START_HERE.md
[identity]: ../../../OFFLINE_SOURCE_STATUS.md
[sync]: ../../../../artifacts/verification_infra_sync_20261110/REVIEW.md
[post-sync]: ../../../../artifacts/verification_infra_sync_20261110/validation/POST_SYNC_VALIDATION.json
[core-results]: ../../../../artifacts/verification_infra_sync_20261110/validation/core/results.json
[legality-log]: ../../../../artifacts/verification_infra_sync_20261110/validation/leaf/tb_legality.log
[owner-log]: ../../../../artifacts/verification_infra_sync_20261110/validation/leaf/tb_mdu_owner.log
[soc-lint]: ../../../../artifacts/verification_infra_sync_20261110/validation/soc_lint.log
[port-validation]: ../../../Verification/core_port_20261109/validation.json
[core-tb]: ../../../Verification/core_port_20261109/tb_core_port.sv
[core-runner]: ../../../Verification/core_port_20261109/run_tests.py
[base-load]: ../../../../artifacts/core_port_20261109/logs/base_load_mdu_w4.log
[candidate-load]: ../../../../artifacts/verification_infra_sync_20261110/validation/core/logs/candidate_load_mdu_w4.log
[alu]: ../../../riscv_core/rtl/ALU.v
[decoder]: ../../../riscv_core/rtl/Control_Unit_Top.v
[csr]: ../../../riscv_core/rtl/csr_regfile.v
[core-top]: ../../../riscv_core/rtl/top.v
[decode]: ../../../riscv_core/rtl/decode_cycle.v
[irq-predictor]: ../../../Verification/infrastructure/checkers/irq_predictor.sv
[reg-predictor]: ../../../Verification/infrastructure/checkers/register_predictor.sv
[gpio-package]: ../../../gpio-master/gpio_reg_pkg.sv
[legacy-tb]: ../../../Verification/tb1_interrupts.sv
[legacy-asm]: ../../../Verification/asm/test5_hazard.S
[csr-plan]: ../../../Verification/doc/plans/CSR_TRAP_CORNER_TESTPLAN.md
[csr-skeleton]: ../../../Verification/infrastructure/tb/csr_trap/README.md
[hazard-validation]: ../../../Verification/hazard_tb/docs/validation.md
[event-plan]: ../irq_event_commit_plan_20261104/PLAN.md
[irq-unit]: ../../../Verification/IRQ_UNIT_COVERAGE_PLAN.md
[irq-functional]: ../../../Verification/artifacts/xcelium_irq_20261030_004317/functional_summary.txt
[dv-audit]: ../../core/RISCV_DV_FAILURE_AUDIT.md
[riscof]: ../../../../verification/riscof/report.html
[riscof-config]: ../../../../verification/riscof/config.ini
[riscof-folder]: ../../../../verification/riscof
[bench-fail]: ../../../benchmarks/docs/KNOWN_FAILURES.md
[bench-deliverables]: ../../../benchmarks/docs/DELIVERABLES.md
[boot]: ../../../Verification/components/memory/boot_path.md
[boot-unit]: ../../../Verification/artifacts/runs/tb_bootloader_20261031_183859_f178e58b/verdict.json
[defects]: ../../../Verification/status/defects.csv
[verbal]: ../evidence_review_20261102/VERBAL_DECISIONS.md
[arch-history]: ../Core_Microarchitecture.md
[csr-history]: ../CSR_and_Trap_Model.md
[soc-history]: ../SoC_Architecture_Map_Boot.md
[core-history]: ../../core/CORE_BUG_STATUS_20261109.md
[dashboard-history]: ../evidence_review_20261102/signoff_evidence_dashboard.html

<a id="structural-traceability"></a>

## Structural traceability (assessment, not official status)

Every link below is a source, bench, retained record or gap; no row assigns completion. Open the [structural catalogue](diagram_index.md) for A1/A2/V1/V2/S1/B1.

| Criterion IDs | Source / interface | Actual bench / check | Retained evidence identity | Assessment / remaining gap |
|---|---|---|---|---|
| 1.1 / 1.3 / 1.4 / 1.5 / 1.9 / 2.10 | A1/A2: ISA, CSR and source map; [Core top](../../../riscv_core/rtl/top.v) · [CSR](../../../riscv_core/rtl/csr_regfile.v) | [CSR plan](../../../Verification/doc/plans/CSR_TRAP_CORNER_TESTPLAN.md) | [Source identity](../../../OFFLINE_SOURCE_STATUS.md) | Static implementation; freeze, privilege/WARL, no-C applicability and ordering decisions pending. |
| 2.7 | A1/S1: LSU / direct DSRAM / MMIO; [Memory](../../../riscv_core/rtl/memory_cycle.v) · [Router](../../../riscv_core/rtl/hybrid_mem_interface.sv) | [Core-port TB](../../../Verification/core_port_20261109/tb_core_port.sv) | [10-Nov core results](../../../../artifacts/verification_infra_sync_20261110/validation/core/results.json) · [Retained baseline failure](../../../../artifacts/core_port_20261109/logs/base_load_mdu_w4.log) | Selected wait/load checks; complete size/error/effect matrix and original DEF-001 closure pending. |
| 2.9 / 4.12 / 5.3 / 6.13 | A2/V1/V2: CSR, trap and load interactions; [WB controller](../../../riscv_core/rtl/wb_trap_mret_commit_controller.v) | [CSR top](../../../Verification/infrastructure/tb/tb_core_csr_trap.sv) · [Pipeline top](../../../Verification/hazard_tb/pipeline/pipeline_tb.sv) | [Historical compile](../../../../artifacts/hazard_tb_skeleton_20261104/slang_pipeline_final.log) · [Focused trap results](../../../../artifacts/verification_infra_sync_20261110/validation/core/results.json) | Compile is historical; hooks incomplete; current reset/IRQ/precise effects/under-load qualification pending. |
| 3.4 / 3.6 / 6.5 | A2/S1: custom controller, real peripheral events; [SoC wiring](../../../RTL_SOC/riscforge_soc_subsystem.sv) | [IRQ unit](../../../Verification/tb_irq_restructure.sv) · [Real-event plan](../irq_event_commit_plan_20261104/PLAN.md) | [30-Oct unit functional summary](../../../Verification/artifacts/xcelium_irq_20261030_004317/functional_summary.txt) | Unit scope only; controller alternative disposition and real source/subevent→input, masks and priority pending. Handler/MRET is extra scope. |
| 5.2 / 5.10 | A1/A2: ISA behavior and issue disposition; [Core top](../../../riscv_core/rtl/top.v) | [Core runner](../../../Verification/core_port_20261109/run_tests.py) | [Historical RISC-DV audit](../../core/RISCV_DV_FAILURE_AUDIT.md) · [Reconciliation](../CJ_FINDING_RECONCILIATION_20261110.md) | Focused checks do not close official suites. Newer RISCOF pass reported/unbound; #16 open, #17 withdrawn; saved failures preserved. |
| 5.7 / 6.10 | S1/B1: warm workload versus cold SPI execution; [Loader](../../../bootloader/bootloader.sv) · [SoC](../../../RTL_SOC/riscforge_soc_subsystem.sv) | [Benchmark TB](../../../benchmarks/tb/soc_benchmark_tb.sv) | [4-Nov workload failures](../../../benchmarks/docs/KNOWN_FAILURES.md) · [31-Oct unit verdict](../../../Verification/artifacts/runs/tb_bootloader_20261031_183859_f178e58b/verdict.json) · [19-Oct staged boot](../../../Verification/components/memory/boot_path.md) | Warm preload bypasses SPI. Historical unit commit unknown / staged source distinct. No qualifying current-candidate workload/cold-SPI evidence identified in inspected records. |

## Literal historical statuses — 8 November inventory

Blank cells below are literally empty. This historical table is separate from present assessment and does not update the official workbook.

| ID | Historical official status |
|---|---|
| 1.1 | In Progress |
| 1.3 | In Progress |
| 1.4 | In Progress |
| 1.5 | In Progress |
| 1.9 | In Progress |
| 2.7 | In Progress |
| 2.9 | In Progress |
| 2.10 |  |
| 3.4 |  |
| 3.6 |  |
| 4.12 | In Progress |
| 5.2 | In Progress |
| 5.3 | In Progress |
| 5.7 |  |
| 5.10 | In Progress |
| 6.5 | In Progress |
| 6.10 | In Progress |
| 6.13 |  |
