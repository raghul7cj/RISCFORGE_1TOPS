# Independent review and final decisions

## 1. Review method

The engineer explicitly requested GPT-6.1 Sol High subagents to review and refine the plan. T3's live catalog selected provider `codex`, model `gpt-6.1-sol`, `reasoningEffort=high`, `serviceTier=default`. Returned task metadata confirmed those settings. Reviewers inspected sources and planning documents only; they did not modify RTL or run simulations.

Two independent initial reviews examined the current SoC boundary/reusable assets and the framework/coverage strategy. A separate final review examined the completed Markdown contract. Findings below are static review evidence, not DUT simulation failures or formal approval.

## 2. Findings and dispositions

| Finding | Disposition in this plan |
|---|---|
| No external AXI master port; legacy fetch controls do not stop the core | S firmware owns bus stimulus; F agents own ports of a separate structural harness; no internal-net forcing |
| Current IRQ path has 13 sources and distinct event/edge/level capture | Current source/class/capture table in 01; new width-checked adapter and independent IRQ model in 02 |
| Live CSR trap state differs from Rev B's hardware-shadow-stack assumptions | Software-managed save/restore/nesting policy in 04; no invented automatic stack or depth guarantee |
| Old MMIO path scoreboard is only a slot check | C07 requires ordered request/response/data/multiplicity join, checked cancellations and drain |
| Register predictor and stage sweeps are partial/mismatched | Complete descriptor inventory and semantic model in 03; no blanket promotion of existing source to qualified oracle |
| I2C output-enable polarity, SPI address/command behavior, UART RX and probe widths need qualification | First vertical slice and agent self-tests explicitly include these static integration hazards |
| Cold boot can wait before runtime watchdog starts | Time-zero guard plus independent boot/runtime/transaction/drain deadlines |
| BSP mailbox maps disagree and one points outside DSRAM | One linker-reserved reviewed mailbox definition, checked against all headers before testing |
| Pure SV does not literally satisfy a UVM-labelled checklist item | Selected OOP SV plus explicit acceptance disposition; optional thin UVM and CFG-I real-peripheral structural top |
| Raw IRQ events may coalesce while pending | Separate offered/captured/coalesced/serviced counts; no unjustified one-event/one-trap assertion |
| Error response need not mean register rollback | Track rejected-before-acceptance versus timeout and late downstream effects independently |
| Generic random traffic and large crosses would obscure useful coverage | Semantic workloads, independent pin peers, targeted crosses and declared legal bin denominator |
| Different source identities/configurations/tools cannot be merged blindly | Candidate identity checks, per-profile reports and primary-tool native merge |

## 3. Final draft review corrections

The final reviewer raised three material contract gaps. All were addressed before publication:

1. **High: instruction-to-effect association.** Added a dynamic memory-instruction token and independent kernel effect ledger in C07. It defines qualified stage advances, repeated-PC ordinals, permitted fragments, retirement/trap/squash outcomes and negative proofs for duplicate native requests and squashed effects. Ambiguous observation remains an explicit instrumentation blocker instead of an exactly-once claim.
2. **Medium: AXI timeout DUT scope.** Added F-AXI-TMO with the actual `axi_lite_timeout_monitor`, controlled upstream/downstream timing, exactly one early error, late response swallowing, drain/new-request behavior and recovery assumptions. APB abort/block behavior remains separately tested.
3. **Medium: reset epoch ownership.** TB now owns epochs from observed core reset. Firmware uses local sequence/hash records; a newly committed START after reset release opens the session. Old retained PASS cannot complete a new session, and reset-before-START leaves no session. Checkpoint replay follows that association.

A targeted confirmation review verified the corrections and reported: all three objections resolved at the planning level, with no remaining material contradiction across architecture, stimulus/coverage and execution/evidence documents. Implementation and qualification evidence remain future work.

## 4. Decisions ready for implementation

| Decision | Selected approach | Reopen only when |
|---|---|---|
| Framework | Small OOP SV classes + static interfaces/SVA | Literal UVM acceptance or qualified reusable VIP makes the thin shell worthwhile |
| Full-SoC stimulus | Prebuilt firmware operation tables + owned external pin peers | A demonstrated need justifies a separately qualified live command service |
| Bus stress | Separate F variants with unchanged scoped RTL | A future top actually exposes a safe bus-injection boundary |
| Register model | Reviewed schema plus explicit event/side-effect policies | Leaf behavior/specification changes or an approved RAL integration replaces the same model |
| Event transport | Immutable records, deterministic ordering, explicit broadcast/queues | Measured scale requires a different implementation preserving the same contracts |
| Coverage | Observed/checked bins, current viability, explicit holes and native primary-tool merge | An approved tool/target/profile decision changes the baseline |
| Development order | Identity/adapter → instrument proof → registers → software/pins → trap/mixed stress → fabric → coverage/candidate | A measured blocker changes dependencies; do not expand framework first |

## 5. Items still requiring an implementation-entry record

These are known project decisions, not hidden omissions or reasons to stop planning:

- External acceptance of simple SV for literal 6.1, or activation of the specified UVM/CFG-I path.
- Simulator/coverage version and working environment qualification; this document proposes VCS per Rev B, but no license/tool run was performed.
- Approved current architecture profile for trap/nesting, unsupported peripheral features and tied MSIP/MEIP/boot-strap expectations.
- Completed leaf-register inventory and legal bin count. This plan defines how to build/review it; it does not fabricate a current complete denominator.
- Exact register/byte-lane conformance expectations where current wrappers reject or ignore partial writes.
- Final toggle target and any explicit disposition of checklist-versus-Rev B coverage differences.

No new full-SoC verification closure, RTL correctness, tool availability or synthesis release approval is asserted by this package.
