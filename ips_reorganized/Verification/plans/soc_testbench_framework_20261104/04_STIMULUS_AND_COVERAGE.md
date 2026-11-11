# Stimulus campaigns and coverage closure

## 1. Produce meaningful workloads

Full-SoC stimulus is a combination of **executed firmware operations, real external device traffic and reset timing**. CFG-F stimulus is **legal bus transactions with independently randomized channel/response timing**. CFG-H stimulus is **known event traces and deliberate bad records**. Keep these populations separate in reports.

Start with directed boundary cases, then constrained random combinations of those cases. Random instruction bytes, uniform address writes over the whole peripheral map and unconstrained reset chaos are poor initial stimuli: they lose oracle quality and mostly generate uninteresting failures. Prefer small legal semantic operations whose expected effect can be checked independently.

## 2. Scenario descriptor and deterministic replay

A scenario contains profile/top, parameters, boot/load method, test/check IDs, workload seed, pin seed, bus seed (F only), reset seed, legal mode choices, operation count, payload data, checkpoint-relative event schedule and time/event budgets. Record the PRNG algorithm/version for host-generated tables; explicitly seed each SV object stream. A root seed alone is insufficient if constructor/thread order changes.

Before simulation, `build_scenario.py` emits the firmware operation table, expected peer payloads, scenario JSON and hashes. At simulation start SV agents randomize only their owned timing knobs from explicit streams. Record the realized schedule and bus transactions for replay. Use observed firmware checkpoint **commit** plus cycle offset, not a console print, as the trigger for important external events. A replay records divergence if the checkpoint or timeline is not reached.

Constraints include valid instance/mode, legal data lengths, finite FIFO rates, disjoint memory ownership, a bounded number of operations and timing sufficient to exercise rather than starve every actor. Keep legal traffic and deliberate protocol/device errors in different tests. Record solved values; randomization failure is a harness failure.

## 3. Directed baseline suites

| Suite | What to generate | What judges it | Primary items |
|---|---|---|---|
| BOOT | Genuine flash cold load, ROM trampoline, SRAM entry, warm retention/preload separately | Flash command/address/data, SRAM contents, reset sequence, fetch/retirement/checkpoint | 6.9–6.11, 6.15 |
| REG | Semantic cases from the complete inventory | Independent register model + observed bus response + effects | 6.2, 6.3 |
| MAP | Every region edge, register hole, GPIO hole and APB-unmapped range; fabric-only crossbar misses | Decode/error/path scoreboard; core trap when no bus access is issued | 6.6, 6.7, 6.15 |
| MEM | March C- style sequence, walking ones/zeros, address-as-data/inverse, byte/halfword lanes on safe SRAM regions | Per-address compare, guard words, checked native-memory events/signatures | 6.12 |
| UART | TX/RX independently and duplex; all implemented word/parity/stop/divisor settings; FIFO lengths 0/1/threshold/full/overflow; framing/parity/break/recovery | Independent frame decoder and received-byte checking, IRQ/status effects | 6.4, 6.12 |
| I2C | Address/write/read, repeated start, multi-byte boundary, ACK/NACK, supported stretch/stuck-low recovery | Pin decode, EEPROM content model, status/IRQ and bounded recovery | 6.4, 6.8 |
| SPI | Implemented modes/dividers/lengths, CS0 flash read/ID, CS1 peer duplex, FIFO boundary, threshold/EOT | Pin command/address/payload model, FIFO ordering, source/subevent IRQ | 6.4, 6.12 |
| GPIO | Input/output/loopback, aliases, each pin, rising/falling/high/low interrupt modes, W1C, rearm and width errors | Independent pin-to-status/IRQ model; output enable and synchronized input | 6.4, 6.12 |
| TIMER | Both channels of Timer0/1, enable/disable, prescaler boundaries, compare and wrap, write interactions | Time/counter model, raw event and service path | 6.5, 6.12 |
| IRQ | Each of 13 real sources, source masked/unmasked, global enable, threshold 0–3, same-class contention, higher-class preemption under selected software policy | IRQ/trap/context scoreboard and ISR progress | 6.5, 6.13, 6.15 |

Do not require unsupported peripheral modes merely because a generic VIP supports them. Enumerate implemented/required/unsupported modes in the configuration contract. If the specification requires an unimplemented mode, that is an open design requirement, not an automatic coverage exclusion.

## 4. Mixed full-SoC stress for 6.8

The base firmware loop alternates register-safe work, packet/FIFO transfers, DSRAM checks and bounded waits. It drives I2C/SPI masters and UART TX, receives UART input, exercises GPIO and programs timers. Independent peers provide UART RX streams, I2C ACK/NACK/data and selected SPI return data. Generate interrupts by causing real peripheral events; there is no generic external IRQ input to drive on this SoC.

Randomized knobs: order and burst length of semantic operations; valid UART frame configuration and inter-frame gap; I2C payload/NACK location/stretch where supported; SPI transfer length/divider/payload; GPIO pin and trigger mode; timer divider/compare; mask/threshold windows; ISR work length; and cross-peripheral overlap. Bias toward FIFO and timing boundaries, not just uniform payload values.

Each seed must perform checked TX and RX where applicable, service intended real IRQ sources, and reach named overlap phases. Polling and ISR modes run as separate subcases before mixing. Capture offered, accepted and checked bytes, raw IRQ events, pending captures/coalescing, service commits, ISR counts and completions. A pending latch can coalesce repeated source events; do not require one trap per raw event unless the source contract guarantees that behavior.

Required outcomes: zero unexpected protocol violations, data loss/duplication, unpredicted response, scoreboard leftovers or progress timeout. Expected device errors must recover and are counted by exact type, not ignored. Report max observed bus latency and retirement gap with the phase/assumptions under which each bound applies.

## 5. Trap and instruction-load stress for 6.13

Generate short assembly kernels with known instruction windows: dependent loads, stores to signatures, branch taken/not-taken loops, multiply/divide, CSR accesses and back-to-back MMIO. Inject **real peripheral events** before/during/after these windows and around trap entry and MRET. Schedule from checkpoint and observed operation phase; use isolated core/harness tests only for pipeline collision states not externally controllable.

Start with non-nested service: save GPRs/CSRs in software, service/clear source, restore context and return. Then test software-managed nesting only under a reviewed trap prologue/epilogue and `mintprio` policy. Current CSR RTL uses live `mepc/mcause/mtval`; do not assume Rev B's older hardware shadow stack. Save outer context before re-enabling interrupts. Same/lower-class deferral, threshold changes and return ordering must match the chosen software policy and implemented hardware.

Check GPR canaries, stack guards, saved/restored CSRs, precise `mepc`, resume PC and final memory signatures. Compare older versus younger effects relative to committed trap entry using the C07 dynamic-instruction/effect ledger; a native-to-bus join alone cannot establish exactly-once behavior. Side-effecting MMIO reads/writes must match the independent expected operation ordinal and permitted multiplicity or be explicitly canceled before taking effect. A duplicated UART read can consume two bytes even if the final register signature looks plausible; the pin/register/path models and instruction ledger must expose it. Preserve first trap, all nested entries and mret events for replay.

## 6. Random reset and fabric stress for 6.14

CFG-S: apply hard/soft resets at idle, boot load, APB activity, UART frame, SPI/I2C transfer and ISR boundaries. For filtered soft reset, include pulses below, at and above the observed acceptance boundary with phase variation; compute expectations from synchronizer/filter state rather than equating pin width with exact internal delay. Check clean release, legitimate reset-abort classification, mailbox epoch, retention/reload behavior and post-reset useful work. Qualify testbench X checks during valid sampling windows.

CFG-F: randomize two master mixes and address regions, independent AW/W arrival, B/R backpressure, target waits, protection bits, WSTRB patterns, legal concurrent reads/writes, errors, timeout boundaries and late responses. Drive stable payload under stall. Use isolated negative SVA tests for illegal master behavior. Include response-queue depth/ordering/drain checks and reset of each in-flight phase. Most full-SoC runtime traffic has only one active bus requester; arbitrary two-master saturation must not be claimed from firmware runs.

Use F-AXI-TMO with the actual AXI timeout monitor for upstream error/late-response swallowing and drain/recovery tests. Use F-APB with the actual APB timeout monitors for their separate abort/block behavior. Report each scope and its downstream-progress assumptions.

External serial delay is not automatically APB wait-state coverage. Observe actual waits in S; controlled wait-state obligations close in a named F configuration when appropriate, with the coverage provenance stated.

## 7. Functional coverage model

Declare bins before the campaign. Each bin has an ID, requirement, exact predicate, legal configuration, sampling point, expected checker and closure evidence locator. Use named legal combinations and small purposeful crosses. Avoid a single unbounded Cartesian product across source, mode, register, reset and pipeline state.

| Family | Required dimensions / targeted crosses | Sample when |
|---|---|---|
| BUS | Requester × region × R/W; decode hit/hole; WSTRB/lane policy; wait buckets 0/1/2–3/4–15/16+; response; channel order; timeout/late-drain outcome | Observed completed transaction; outcome bins after check |
| REG | View/access, bank/direction, field legal values/boundaries, enable/mode, alias effect, W1C event/clear overlap | Completed access and semantic comparison; mode entry confirmed |
| PIN | Instance × direction × legal mode; FIFO/length boundary; error × recovery; checked payload counts | Independently decoded frame/command and checked peer/device result |
| IRQ | Each source/subevent; mask/global-enable/threshold; capture/coalesce; selected source pairs; class outcome; accept/trap/return; reassert | Raw events and model-predicted eligibility, then actual checked commits |
| RESET | Domain × activity phase; accepted/rejected soft pulse; release order; retained/reloaded region | Observed internal reset transitions and verified recovery |
| BOOT | Genuine cold flash path, ROM fetch/trampoline, SRAM execution, warm retention; image/parameter profile | Checked phase transitions and useful firmware completion |
| TRAP | Load/store/branch/M/DIV/CSR/MMIO window × event timing; defer/entry/return; supported nesting depth/context restore | Actual operation/commit observation plus context comparison |
| STRUCTURAL | Declared FSM state/transition, decode region, arbitration outcome, spill/timeout/recovery paths | Valid state observation in actual scoped RTL |
| ASSERTION | Every bound check ID evaluated/non-vacuous; separate negative-proof viability record | Tool assertion counts and independently reviewed injected-fault result |

Maintain observed architectural bins separately from checked-success bins, or attach a successful-check reference to accepted bin hits. Do not earn a bin merely because the generator chose a value. Fault-injection/harness events earn checker viability, never the corresponding real-SoC behavioral bin. S-profile IRQ coverage must include all 13 sources, not just cause classes or synthetic input vectors.

## 8. Closure process

1. Validate schema, legal bin counts and requirement links. Review unsupported modes and impossible combinations before a merge. Store an explicit denominator per profile/family.
2. Run directed suites, compare attempted/observed/checked counts and fix model/instrument problems with evidence. Never respond to a coverage hole by deleting its expectation without a disposition.
3. Merge only passing, gate-eligible runs with compatible RTL/configuration/coverage-model identity. If allowed parameter profiles differ, report per-profile first; a combined view must retain provenance and must not hide an untested release profile.
4. Export every uncovered bin into `coverage_holes.csv`: missing stimulus, missing observation/checker, DUT failure, configuration-unreachable or design-unreachable. Give each an owner, action and source proof. Missing checks/observations are not waivable as unreachable design.
5. Add targeted directed tests or constrained-random bias for reachable holes. A waiver carries owner, reason, approval/reviewer, review date and exact bin/check scope. A design-unreachable exclusion additionally cites the structural rule and RTL locator. Recheck after source/configuration changes.
6. Re-run at the candidate identity. Evaluate `declared - hit - approved_waived - approved_excluded == 0`. Show raw hit percentage, adjusted closure and counts separately. An untested requirement remains open even when a percentage rounds to 100.
7. Evaluate checker viability independently: all bound check IDs have current negative-case evidence or a specifically applicable formal vacuity proof. An evaluated-but-incapable checker is not closed.

Use Rev B's convergence rule for the declared random convergence set: initial nightly floor **20 seeds**, saturation (last added seed gives no first-hit bin), and stability with **H=2 distinct seeds per selected bin over K=3 consecutive partitions**. Increase the campaign when those conditions fail. Single directed rare/error bins may belong outside that convergence set, but still require direct coverage and a documented reason; do not quietly shrink the random set after seeing results.

## 9. Code coverage

Collect line/statement, branch, condition, toggle and useful FSM metrics over the shipping DUT hierarchy reachable from the actual resolved filelist. Exclude TB/VIP/model code from the DUT denominator. Keep reset synchronizer chains in line/branch/condition scope as Rev B requires; report them as a named subgroup. Named constant-net exclusions need proof. Record both toggle directions, not a single generic activity flag.

Publish per-module and overall raw covered/total counts, excluded counts/reasons and adjusted coverage. Do not average module percentages. Compare checklist ≥95% statement/branch/toggle separately with Rev B's 100% line/branch/condition after exclusions. Record the chosen deferred toggle policy and retain the original checklist comparison. Different metrics cannot substitute for one another; functional bins never close an uncovered RTL branch.

Use one selected coverage tool and its native merge. Keep Xcelium and VCS databases separate; a secondary tool can compare named functional-bin outcomes, not contribute arithmetic coverage to the primary. XSim bring-up output is useful but not a substitute for the qualified coverage-of-record database.

## 10. Initial campaign sizes and escalation

These are **starting engineering budgets**, not signoff proof or measured throughput:

| Partition | Initial workload | Exit/escalation rule |
|---|---|---|
| Change smoke | Fixed seeds; boot, one operation/response per peripheral, one real IRQ, checker smoke | Finish useful work and all local checks/drain; no coverage-closure claim |
| Directed | All inventory semantic cases and named peripheral/IRQ/reset boundaries | Every required test executed, no unexpected failures |
| Nightly S mixed | At least 20 seeds; target 10,000 checked MMIO operations/seed plus nonzero checked TX/RX and IRQ service quotas | Calibrate runtime from first valid runs; all quotas and required overlap bins met |
| Nightly F | At least 20 seeds; target 50,000 completed transactions/seed across masters | Channel/backpressure/error/ordering bins met; no unresolved transactions |
| Trap campaign | Directed timing sweeps, then randomized checkpoint/event offsets over each kernel | Every declared instruction-window/policy bin hit with valid context checks |
| Candidate expansion | Extend seeds/event volume per saturation/stability and coverage holes | Stable coverage and zero unexpected failures at one candidate identity |
| Release soak | Separate event-qualified boot/reset/traffic campaign | Reconcile Rev B §11.7 simulation default 72 h, ≥1,000 cold boots and ≥4,000 reset events; preserve event quotas, no hangs/X/data mismatches/findings and late coverage-delta rule unless explicitly revised |

Per-source service and per-device transfer quotas are derived from the selected scenario, not a universal arbitrary threshold. A seed cannot pass after reaching only total MMIO count while starving UART RX or a scheduled IRQ. Keep wall-clock runtime as a capacity measure; useful event counts and checked outcomes establish the test's work.
