# Execution roadmap and evidence contract

## 1. Implementation sequence

Complete one vertical slice before broadening stimulus. Each stage below defines a reviewable output and a distinguishing check. Expected durations are deliberately omitted until the first build and runtime measurements exist. Keep implementation, compilation, simulation, verification and validation statuses distinct.

### Step 0 Agree the implemented configuration

**Build:** a short configuration/decision record, resolved source list, register inventory outline, current IRQ/CSR policy and tool capability checklist. Choose pure OOP SV as proposed; record its relationship to literal checklist 6.1. Choose a coverage-of-record tool and version. Declare shipping parameters, supported boot paths, tied IRQ inputs and excluded unintegrated blocks.

**Inspect:** current top and leaf RTL, not old comments. Verify UART dependencies, GPIO aperture, both timer channels, current 13-source mapping, event/edge/level gateway and software-managed trap context. Reconcile mailbox and linker layout across the competing BSPs.

**Exit:** one versioned contract, every scope discrepancy named, no undefined source ownership. Unresolved architectural expectations can block affected tests without blocking unrelated infrastructure work.

### Step 1 Reproducible build and observation slice

**Build:** manifests, source/include resolution, top/interface/adapter, finding sink, time-zero watchdog, image/mailbox checks and minimal event recorder. Extend current `gen_filelists.py` and packaging infrastructure; do not create a second hand-maintained design list. Fail on missing mandatory source or silent optional checker omission.

**Check:** compile/elaborate the current source set; retain module hierarchy against the expected module set and parameter values. Run one firmware test with one real register transaction and one checked UART/GPIO pin path. Independently compare a known bus trace with captured events. Test held-valid and same-address repeats so transaction counts cannot be inflated by stall cycles.

**Exit:** reproducible build, valid observed activity, exact counters and useful firmware completion. This establishes a vertical slice, not full environment closure.

### Step 2 Qualify agents and instruments

**Build:** pin drivers/decoders, event broadcast, protocol assertions, queued path scoreboard, reset epochs and end-of-test drain. Correct verification-only I2C polarity/wiring and stale IRQ observations after reviewing the expected behavior. Qualify lightweight SPI address/command decoding and I2C multi-byte read before using them as oracles.

**Check:** missing, duplicate, reordered, corrupted, unknown, late and reset-aborted event traces; APB wait stability; AW-before-W/W-before-AW; finite queue overflow detection; pre-boot timeout; no mailbox completion; and checker-disabled detection. Pin-agent tests must show expected payloads and deliberately wrong payloads. Retain the initial failing tests and the qualified reruns.

**Exit:** each enabled check has a mapped self-test/negative proof and all queues drain on clean traffic. A self-test on a stub earns instrument viability only.

### Step 3 Close register semantics first

**Build:** reviewed descriptors, C/SV views, register model and firmware operation executor. Audit and reuse existing `soc_regtest_tb`/regtest firmware concepts and Stage5 where valid. Implement one peripheral end to end, then all six, including both timer channels and banked/alias views.

**Check:** every case in [03_REGISTER_VERIFICATION.md](03_REGISTER_VERIFICATION.md), independent response/effect comparisons and per-register obligation reports. Use a targeted model mutation or wrong-observation trace to show each semantic family can fail.

**Exit:** 6.2's applicable obligations have current attributed results; remaining field/mode coverage holes are explicit. No skipped offset disappears from the denominator. This is the first major verification milestone.

### Step 4 Complete directed software and pin paths

**Build:** memory pattern kernels, peripheral duplex/loopbacks, 13-source IRQ/trap observations, real cold-boot and warm tests. Reuse drivers after checking actual map/masks and binary instructions. Add bounded waits and independent pin/device checks.

**Check:** safe SRAM ranges and guards, every required pin direction, source-to-ISR-to-return, mask/threshold behavior, source clear/reassert and reset recovery. Run at least one genuine cold flash image; fast warm preload cannot satisfy flash-loader bins.

**Exit:** implemented portions of 6.12 and the directed foundations for 6.8/6.13 pass. MSIP/MEIP and strap discrepancies remain open unless separately dispositioned; passing other IRQs does not hide them.

### Step 5 Trap context and mixed stress

**Build:** assembly stress kernels and the checkpoint-relative scheduler, software-managed nesting policy, mixed peripheral traffic and reset sequences.

**Check:** qualified dynamic-instruction/effect ledger, exact-once side effects, GPR/CSR/stack context, resume PC, coalesced versus delivered IRQ accounting, expected overlap/event quotas, progress bounds and replay of a fixed realized schedule. Include duplicate-native-request and squashed-effect negative proofs. First run directed interleavings; then use the nightly random floor and measured throughput.

**Exit:** 6.8 and applicable 6.13 behavior demonstrated at declared event volume, with no unresolved scoreboard or protocol findings. Long-run liveness is supported only for the exercised workloads and bounds.

### Step 6 Add fabric stress where needed

**Build:** the F-APB harness first, then F-XBAR/F-SRAM if their uncovered obligations require them. Add F-AXI-TMO containing the actual AXI timeout monitor before claiming controlled AXI timeout/drain coverage. Reuse bus agents and semantic data types. If literal UVM is required, activate the thin shell and optional real-peripheral integration profile described in the architecture document.

**Check:** independent channel timing/backpressure, two-master contention, response errors, decode holes, byte enables, timeout/late drain and reset at in-flight phases. State which unchanged modules and replaced boundaries each result includes.

**Exit:** fabric-specific 6.14 obligations covered; complementary S evidence proves the real system path. No claim that a synthetic-responder test proves peripheral functionality.

### Step 7 Close functional and code coverage

**Build:** native coverage merge, uncovered-bin export, explicit exclusions/waivers, per-module code report and generated traceability. Map each new check ID to the original requirement/checklist and Rev B check ID when available; do not invent a match where the old plan is ambiguous.

**Check:** bin sampling against hand-constructed traces, compatible merge identities, assertion evaluation counts and current checker viability. Classify holes and add targeted stimuli. Report raw and adjusted counts, masks and exclusions. Evaluate convergence independently of one clean run.

**Exit:** 6.15/6.16 either meet their exact predicates or remain explicitly open with quantified shortfalls. High IRQ-unit coverage cannot substitute for full DUT coverage.

### Step 8 Freeze a candidate and run the complete manifest

**Build:** candidate manifest listing every required directed/random/software test, profiles, seeds, expected-negative suite, run IDs and hashes. Use the exact RTL intended for synthesis. Hash input contents, includes, defines, parameters, ROM image, firmware and generated verification schema.

**Check:** all required tests executed; zero unexpected failures/incomplete runs; current viability, drain and coverage/traceability predicates; no unexplained drops. Compare pre/post source hashes and handoff source identity. Retain failures and reruns as separate immutable records.

**Exit:** candidate-level 6.17 evidence is ready for engineering review. Release tagging/approval under 6.19 is a separate action. Any later RTL change invalidates exact-candidate claims until impact analysis and required reruns complete.

## 2. Run evidence directory

```text
artifacts/runs/<run_id>/
  manifest.json                  inputs, tool, command, seed and scope identity
  inputs/resolved_sources.json   ordered source/include paths + content hashes
  inputs/scenario.json           requested workload and per-stream seeds
  inputs/firmware/                ELF, disassembly, map, hex and image hashes
  inputs/generated/               register/model/bin schema or immutable locators
  logs/build.log
  logs/elaborate.log
  logs/sim.log
  logs/host_commands.json         exact argv, cwd, environment names; no secrets
  events/transactions.jsonl       scoring-relevant normalized events or compact equivalent
  events/replay_schedule.jsonl    realized pin/reset/BFM schedule
  findings.jsonl                 check ID, class, expected/actual, epoch and cycle
  counters.json                  attempted/observed/checked; per-device/source
  scoreboard_drain.json           queue counts and terminal dispositions
  checker_evaluation.json         binding/enabled/evaluation counts
  register_results.csv           view/operation comparisons and obligations
  coverage/native/               tool-native functional/code/assertion database
  coverage/summary.json           raw covered/total per family/metric/scope
  coverage/holes.csv              uncovered bins/items and assigned action
  waveforms/                     focused first-failure/replay waves
  verdict.json                   typed final result and per-run predicate operands
  checks/input_unchanged.json     pre/post content identities
```

The host packager owns metadata/result serialization; SV emits events and facts in a stable schema. Tool-native databases are copied only after a successful save/close. Capture all mandatory scoring events or a losslessly equivalent transaction summary; diagnostic circular buffers alone cannot support global accounting. For long runs, compress/stream to disk and retain full failures/replay plus per-obligation counts. Never truncate silently. Record retention/storage limits before a campaign.

## 3. Identity and manifest contract

`manifest.json` includes schema version, run ID, UTC timestamp, profile/top, repository path/commit when available, dirty state, actual ordered source list, `H_rtl`, `H_tb`, `H_model`, `H_filelist`, `H_fw`, `H_scenario`, parameters/defines/includes, tool/compiler/model versions, command argv, cwd, named seed streams, boot/load method and expected outcome class.

Canonical hash input is a documented serialization of normalized repository-relative paths, file contents and compile-order/option fields. Resolve includes recursively. Absolute runtime paths belong in the execution log; machine-specific path prefixes must not change content identity. A current hash is recomputed, not copied from the October P0 manifest. Pre/post comparison detects source drift during a run.

A candidate coverage merge requires identical relevant RTL, structural parameters/defines, instrumentation and coverage-model schema; tool version/settings must be compatible and recorded. Firmware and seed identities vary by test and remain linked. Across deliberate parameter profiles, report separate scopes and apply a reviewed bin-union policy; never use one smaller configuration to cover a larger shipping configuration invisibly.

## 4. Verdict semantics

Allowed terminal classes: `PASS`, `FAIL_DUT`, `FAIL_HARNESS`, `FAIL_MODEL_OR_SPEC`, `INCOMPLETE`, `BLOCKED_TOOL`, `EXPECTED_NEGATIVE_PASS`. Ambiguous findings remain unresolved instead of being mislabeled a DUT bug. An unexpected simulator crash, missing coverage database, empty test list or unexecuted required test cannot become PASS.

An expected-negative test passes only if the intended fault is activated, the exact expected check reports in the intended window and no unrelated unexpected failure occurs. A watchdog deliberately triggered to prove diagnostics is not a clean positive long-run pass. Separate these tests in regression totals.

Rev B predicates apply at their declared tier:

| Gate | How this framework evaluates it |
|---|---|
| G0, per run | Resolved/canonical module set, tool/inputs pinned, artifacts writable, mandatory checks bound and inputs attributable |
| G1, per system partition | Nonzero expected retirement, AXI, APB and committed firmware attestation for the applicable SoC partition; add scenario-specific work quotas |
| G2, per candidate | Every bound check ID has current checker viability evidence, including adapted binding and negative path |
| G3, per run | No unresolved unexpected finding, no unexplained scoring loss, all scoreboards drain or reach checked terminal dispositions |
| G4, per candidate | Declared coverage predicate closed, assertion evaluation/non-vacuity and reviewed exclusions/waivers |
| G5, release | Compliance/formal closure remains a separate required input; this plan does not create those results |
| G6, per candidate | Generated links have zero orphan requirement/check/test/result and every defect has its regression link |

For F/H/unit tests, record profile-specific activity such as completed BFM transfers or injected/observed fault counts. They cannot satisfy the literal full-SoC G1 predicate and do not receive a misleading system-gate PASS; report that gate as not applicable for their declared evidence role. Candidate aggregation names which S runs discharge system activity. The legacy testbench comment calling a minstret check "G6" must not determine report naming.

## 5. Candidate evidence and signoff review

Create `artifacts/candidates/<candidate_id>/` with `candidate_manifest.json`, selected `run_ids`, suite completeness report, primary-tool merge input list/log, per-family functional report, raw/adjusted code report, checker viability ledger, register completion matrix, waiver/exclusion records, defect status and generated traceability.

The generated trace rows contain: requirement ID/source, design element/configuration, original checklist item, Rev B check ID or pending mapping, new check ID, test/scenario, run/result, coverage bin/proof, artifact locator, defect/regression and disposition. A test with no result is an orphan even when it compiled. A result with no attributable input identity is not accepted evidence.

Present a short review table for 6.1/6.2/6.8/6.12–6.17: exact criterion, applicable configuration, achieved result, raw coverage/quotas, remaining exceptions and acceptance owner. No automatic promotion to Done merely because the framework exists.

## 6. First implementation batch

Keep the first batch small and independently reviewable:

1. Reconcile the selected source manifest and mailbox/linker contract; document current IRQ capture and software trap policy.
2. Build adapter width/reset checks, a time-zero guard and immutable event capture around one existing firmware test.
3. Prove one held AXI/APB transaction and one deliberately missing transaction are counted/detected correctly.
4. Complete one stable RW register plus one genuine W1C/event case through firmware and the independent model.
5. Package the build/elaboration/simulation/event/drain evidence with recomputed identities.

Only after this slice works should the inventory, pin modes and random campaigns expand. That sequence makes 6.1 useful to 6.2 immediately and prevents weeks of framework construction without a trustworthy result.
