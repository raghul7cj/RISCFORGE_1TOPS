# CJ learning and progress route

**Maintained reviewer entry:** [CJ unified documentation](../cj_review/index.html) groups the current architecture, verification boundaries, benchmark/SPI evidence and gate-readiness map. Older source documents below retain historical scope and must be read with their correction notices.

Created 10 November 2026. Purpose: understand, review and account for AI-assisted RTL/verification work before choosing the next engineering task. This is a documentation/learning plan; it does not claim new simulation or checklist closure.

## Start with one evidence-backed example

Use **an older load waiting in MEM while a younger MUL is in EX**. This single example connects the pipeline, LSU, hazard control, MDU completion, testbench model, checker and evidence. First read its behavior, then follow the relevant files, then inspect one before/after result. You do not need to read every file in the repository first.

1. Read the [merged port status](https://github.com/raghul7cj/RISCFORGE_1TOPS/blob/a91edb7e666d5c374af70809703f52eb5513d96f/ips_reorganized/documentation/core/MALAY_CORE_PORT_20261109.md) for what changed and what remains unresolved.
2. Read the [original waveform investigation, older-load loss](../../../benchmarks/docs/RTL_FAILURE_ISOLATION.md:87). This is the retained failure, not evidence that the merged source still has that mechanism.
3. Follow the synchronized local source: [hazard_unit.v](../../../riscv_core/rtl/hazard_unit.v), [execute_cycle.v](../../../riscv_core/rtl/execute_cycle.v), and [core top](../../../riscv_core/rtl/top.v). Their bytes match the pinned merged source; the [offline identity](../../../OFFLINE_SOURCE_STATUS.md) records the revision.
4. Read [tb_core_port.sv](../../../Verification/core_port_20261109/tb_core_port.sv) and the `load_mdu` program in [run_tests.py](../../../Verification/core_port_20261109/run_tests.py). Identify what the instruction/data models do, how memory waits are generated, where expected values come from and how FAIL/PASS is signaled.
5. Inspect the [base failure](../../../../artifacts/core_port_20261109/logs/base_load_mdu_w4.log), [candidate result](../../../../artifacts/core_port_20261109/logs/candidate_load_mdu_w4.log) and [validation record](../../../../artifacts/core_port_20261109/candidate/ips_reorganized/Verification/core_port_20261109/validation.json). A firmware check passing is scoped evidence; it is not a benchmark score or full precise-exception proof.

A useful first notebook entry is a short timing sketch: which instruction owns EX and MEM before the edge, what holds or flushes at the edge, when the M operation is issued, when its result is owned/held/consumed, and which GPR/memory effect should happen once. Record an uncertainty instead of inventing an explanation. We can review the sketch together; this is a learning aid, not a prerequisite gate for every future request.

## Reading order for all responsibilities

| Study area | Existing starting documents | What CJ should be able to account for |
|---|---|---|
| Current baseline and progress | [18-item inventory](../cj_inventory_20261108/README.md), [merged status](https://github.com/raghul7cj/RISCFORGE_1TOPS/blob/a91edb7e666d5c374af70809703f52eb5513d96f/ips_reorganized/documentation/core/MALAY_CORE_PORT_20261109.md) | Which source version a claim refers to; what was coded, simulated, reviewed, merged, left open or merely proposed |
| Architecture and CSR contract | [Core microarchitecture](../Core_Microarchitecture.md), [CSR/trap model](../CSR_and_Trap_Model.md), [SoC map/boot](../SoC_Architecture_Map_Boot.md) | ISA/privilege/CSR reset/WARL rules, trap boundary, nesting policy, interrupt map and controller departures; these are older as-coded descriptions needing reconciliation with the merged source |
| Pipeline, LSU and MDU | The worked example above; [hazard/pipeline architecture](../../../Verification/hazard_tb/docs/architecture.html), [skeleton validation](../../../Verification/hazard_tb/docs/validation.md) | Holds versus flushes, source dependencies, completion ownership, memory request/completion timing and what the current harness actually checks |
| CSR, traps, MRET and IRQ entry | [Corner-case plan](../../../Verification/doc/CSR_TRAP_CORNER_TESTPLAN.md), [architecture](../../../Verification/doc/CSR_TRAP_TESTBENCH_ARCHITECTURE.html), [skeleton README](../../../Verification/infrastructure/tb/csr_trap/README.md) | Which stimulus, independent reference model and coverage hooks are still CJ-owned; why the reset-held skeleton cannot establish correctness |
| Architectural software/random checks | [Historical RISC-DV audit](../../core/RISCV_DV_FAILURE_AUDIT.md), [RISCOF folder](../../../../verification/riscof) | Reference expectations, signature versus trace comparison, first divergence, source/seed provenance, and why a current rerun is distinct from an earlier reported pass |
| Benchmark qualification | [Benchmark deliverables](../../../benchmarks/docs/DELIVERABLES.md), [firmware guide](../../../benchmarks/docs/FIRMWARE.md), [harness guide](../../../benchmarks/docs/HARNESS.md) | Correct workload result before score, image/configuration identity, measurement boundaries, known counter limitations and reproducibility |
| Peripheral IRQ integration and load stress | [Event/commit plan](../irq_event_commit_plan_20261104/PLAN.md), [proposed TB file map](../irq_event_commit_plan_20261104/TB_FILE_PLAN.md), [IRQ unit coverage scope](../../../Verification/IRQ_UNIT_COVERAGE_PLAN.md) | Real event to pending/winner/commit/handler/MRET/resume; unit coverage versus unimplemented integration plan; source/subevent and memory-side-effect checks |
| External SPI boot | [Boot evidence and limitations](../../../Verification/components/memory/boot_path.md), [SoC boot architecture](../SoC_Architecture_Map_Boot.md) | Flash image/read protocol, SRAM transfer, core release, ROM handoff and executed-result proof; distinguish real SPI transfer from payload preload |

The local `ips/` tracked-source subset now matches remote `verification_infra/ips_reorganized` at merge `a91edb7...`, with local-only work preserved. See [current remaining work](../CJ_REMAINING_WORK_20261110.md) and [sync identity](../../../OFFLINE_SOURCE_STATUS.md). This is a pinned offline copy, not automatically the latest branch head or a Git checkout. The earlier pre-port files are backed up; the original tested candidate under artifacts remains available for historical study.

## Documentation to maintain or create next

Avoid starting a parallel set of reports for everything. Extend the owning document and link the evidence; add a new document only for a distinct missing purpose.

| Document/work product | Existing basis / proposed action | Responsibility IDs |
|---|---|---|
| Reviewed architecture and decision record | Reconcile the three architecture documents; record exact approved choices, remaining spec differences and controller dispositions | 1.1, 1.3, 1.4, 1.5, 1.9, 2.10, 3.4, 3.6 |
| Current LSU qualification map | Missing dedicated current-candidate feature-to-test/evidence map; reuse legacy LSU checks and current pipeline model descriptions | 2.7 |
| CSR/trap executable verification map | Extend the corner plan with actual implemented test IDs, checker/reference responsibilities, run links and unimplemented hooks | 2.9, 4.12, 5.3 |
| Current architectural-test run record | Recover the reported newer RISCOF pass, identify compiled source/plugin/reference and applicable suite; record a current rerun separately | 5.2, supports 5.3 |
| Unified core issue/evidence register | Use the merged port note and historical audits; distinguish implemented correction, directed check, seed regression and closure | 5.10 |
| Benchmark qualification record | Extend existing deliverables with current image/configuration, correct results, counter qualification, measured metrics and limitations | 5.7 |
| Peripheral event/commit results map | Extend the existing plan as scenarios/checkers become executable; don't turn planning rows into passing results | 6.5 |
| Current external-SPI boot run record | Missing focused current-candidate qualification record; reuse historical boot manifest/logs without claiming source equivalence | 6.10 |
| Trap-under-load results map | Extend shared CSR/trap and peripheral plans with the actual arrival windows, latency schedules and checked effects | 6.13 |

## A small repeatable review cycle

For one responsibility at a time:

- State the approved expected behavior and the exact source boundary/version being studied.
- Trace one design transaction and one corresponding test/checker path through the linked files.
- Explain the existing result and its limit: static review, compile, simulation, checker, coverage or system proof.
- Record what is understood, uncertain, implemented but unverified, missing or blocked on a named decision.
- Choose the next distinguishing experiment or documentation update. Let CJ own core reasoning/models/coverage/stimulus as requested; routine evidence organization can be automated within the authorized task.

Keep a compact per-item row: requirement ID, intended behavior, design/TB/document links, source/run identity, evidence level/result, open issue/decision, next action, owner. A merge updates implementation history, not every associated verification status. This route adds no new pass claims and changes no official checklist cells.
