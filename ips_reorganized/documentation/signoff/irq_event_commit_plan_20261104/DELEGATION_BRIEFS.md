# Delegation briefs: human-readable IRQ TB skeleton

Status: ready-to-send proposed tasks. **No tasks have been launched.** Scope is skeleton implementation only after the engineer authorizes it. Test stimuli, scenario constraints, functional coverage bins and firmware test bodies remain engineer-owned.

Read [TB_FILE_PLAN.md](TB_FILE_PLAN.md) and [PLAN.md](PLAN.md) before using a brief. Both planning files may be uncommitted; a delegated worktree starts from a commit and does not inherit uncommitted files. Use the shared checkout with the ownership rules below, or explicitly arrange the reviewed plan baseline before selecting worktree isolation.

## 1. Requested model and transport

Live catalog inspected while preparing this plan:

```json
{
  "providerInstanceId": "codex",
  "model": "gpt-6-luna",
  "options": {
    "reasoningEffort": "xhigh",
    "serviceTier": "default"
  }
}
```

The catalog advertises `xhigh` for this exact model. Use T3 `delegate_task` so model options are applied, rather than relying on a prompt or native model defaults. Recheck capabilities before launch and verify the returned provider/model/options. Report a mismatch; do not substitute another model or downgrade effort silently. No priority-tier request was made.

Use `mode: "async"`, `isolation: "shared"`, and role `implementation` for K0–K3. Keep runtime/interaction modes inherited; do not broaden modes. The parent retains each returned taskId, reads results and integrates. Do not use top-level thread creation for these child tasks. Do not poll in a loop; inspect task status only when needed and let completion notifications arrive.

## 2. Shared brief, included verbatim in every implementation task

```text
You implement only your assigned files for a human-readable RISCFORGE IRQ
testbench skeleton. The user is the primary engineer and owns all stimuli,
peripheral event schedules, scenario constraints, firmware test bodies and
functional coverage bins/crosses. Do not implement those, including a demo
Timer0 test, covergroup, random constraint, automatic serial responder or a
driver-based stimulus. Do not add a fabricated reference model.

Workspace: C:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl
Read these full planning documents:
ips/documentation/signoff/irq_event_commit_plan_20261104/PLAN.md
ips/documentation/signoff/irq_event_commit_plan_20261104/TB_FILE_PLAN.md

Preserve all existing files outside your assigned list. Do not modify RTL,
drivers, existing monitors/checkers, regressions, test expectations or gate
statuses. Do not spawn subagents. Do not commit/push/open a PR or contact others.
Other agents share this checkout; do not overwrite their work.

Use small ordinary SV modules/interfaces/structs/tasks with clear snake_case
names and comments explaining timing, units and ownership. One public contract
per responsibility; no factory/class framework, generic registry or unnecessary
abstraction. Only the assigned adapter may contain internal DUT hierarchy paths.
No force/deposit for events, invented nesting/shadow-stack ports, or silent
zero tie-offs for unavailable observations. Preserve observed four-state values.

Engineer TODOs must name their stable USER-* ID, exact PLAN.md section/case IDs,
and observations to check. Empty stimulus/checker/coverage hooks remain visibly
unimplemented and cannot generate functional PASS. Observe the status contract
in TB_FILE_PLAN.md. Infrastructure readiness is separate from test completion
and coverage readiness.

Use the package and interface API frozen by K0. If a needed change is outside
your file ownership or would change the contract, report the precise proposal
to the parent instead of making it unilaterally. Do not fix substantive design
or manifest defects just to make the skeleton compile.

Perform a static consistency review of your assigned sources. Do not run
functional simulations, coverage collection or new test campaigns. The parent
will coordinate authorized compilation/elaboration after integration. Do not
claim compilation, simulation or verification you did not perform.

Return: changed file paths, public API used, a short explanation of the reading
flow, USER TODO IDs and references, unavailable observations/blockers, exact
checks actually performed and any unresolved integration issues. Preserve
negative findings. No functional verification result is expected from this task.
```

## 3. K0 — contracts first, one serial child

Title: `IRQ skeleton: freeze readable interfaces`.

Stable request ID example: `irq-skeleton-k0-contract-v1`. Use it only for retries of this exact round; a later review round gets a new ID.

Assigned files under `ips/Verification/irq_tb/`:

- `tb/irq_tb_pkg.sv`
- `tb/irq_pin_if.sv`
- `tb/irq_observe_if.sv`
- Initial `README.md`

Append to the shared brief:

```text
Implement K0 only. Inspect the selected DUT ports/hierarchy and existing
infrastructure to design the minimal shared records/interfaces described in
TB_FILE_PLAN.md. Define the exact types, named fields, modports, readiness/status
types and method signatures later files must use. Give widths and sampling
semantics explicitly. Document the 13-bit pending vectors, two-bit class-1
pointer and one-bit class-0 pointer; do not copy stale six-bit/shadow-stack
interfaces. Keep source-policy expectations out of observation types.

Do not add DUT taps to the interfaces: the later adapter owns those. Define
required versus optional availability explicitly. Initialize no user tests or
coverage. Publish a concise API/port table in README including the agreed top,
monitor, scoreboard, report and user-hook call signatures so the parent can
freeze it before K1/K2/K3 start. These are contracts; do not create their bodies
or edit their future files. Leave source/manifest uncertainty visible.
```

Parent acceptance: inspect API simplicity, port ownership, sample timing and actual available taps. Amend/review this result before launching callers. Do not start K1/K2/K3 while the public API is unsettled.

## 4. K1 — shell and hierarchy adapter

Title: `IRQ skeleton: SoC shell and read-only adapter`.

Stable request ID example: `irq-skeleton-k1-shell-v1`.

Assigned files:

- `tb/irq_soc_tb.sv`
- `tb/irq_dut_adapter.sv`

Append to the shared brief, including K0's exact frozen API in the task prompt:

```text
Implement K1 using the frozen K0 API. Make irq_soc_tb.sv the human reading entry:
configuration, safe pin ownership, clock, documented baseline reset/load,
DUT/module instantiation and explicit run/finalization order. Reference active
production RTL; do not copy DUT or existing giant TB blocks into this shell.

Put all internal DUT reads in irq_dut_adapter.sv. Comment architectural meaning,
widths and observation availability. If SRAM preload needs hierarchy, confine
it to a documented initialization-only adapter task with bounded image checks;
do not treat this as permission for test event backdoors. No traffic generators
or active protocol peers. External input idle ownership must be explicit and
I2C open-drain polarity must be checked against the real port contract.

No case-specific firmware, resets, delays, event schedules, hardcoded driver
programming or default Timer0 stimulus. Empty user hooks stay NOT_IMPLEMENTED.
Clock and baseline reset are environment operations. Missing images/taps or
unsupported baseline source configuration must produce a clear infrastructure
error/limitation, not a dummy pass. Ensure watchdog/finalization plumbing does
not block behind a user task that hangs.
```

## 5. K2 — passive monitor, checker hooks and report

Title: `IRQ skeleton: observation and honest reporting`.

Stable request ID example: `irq-skeleton-k2-observation-v1`.

Assigned files:

- `tb/irq_monitor.sv`
- `tb/irq_scoreboard.sv`
- `tb/irq_report.sv`

Append to the shared brief, including K0's exact frozen API:

```text
Implement K2: passive sampling/history, checker extension points and one report
owner. Follow the frozen cycle/sample contract and preserve simultaneous events
and unknown values. Use bounded history and simple typed records. Distinguish
raw assertion, pending, winner, EX acceptance and actual WB commit. Activity
counts are observed diagnostics, not coverage or expected event totals.

The scoreboard is a documented check_sample extension shell with checked=0
and checker_ready=0 until functional checks are supplied/approved. Do not write
a complete priority/event/CSR oracle or embed intended expected results. Add
USER-CHECK-EVENT/COMMIT TODOs with plan references. Avoid an empty function
returning success. Reporting must distinguish INFRA_ERROR, NOT_IMPLEMENTED,
FAIL, HARNESS_ONLY, CHECKS_PASS_COVERAGE_OPEN and eligible PASS as specified.
An unimplemented coverage hook is never treated as coverage closure.

Only this report module owns output serialization. Capture configuration,
requested test, readiness, reason, observed counts and raw trace; keep simulator
exit separate from verdict. Do not write fake sample run results. Supply the
schema in comments or your handback. Never derive expected IRQ identity from
the observed winner.
```

## 6. K3 — engineer-owned extension workspace

Title: `IRQ skeleton: readable user TODO hooks`.

Stable request ID example: `irq-skeleton-k3-user-hooks-v1`.

Assigned files:

- `user/irq_user_stimulus.sv`
- `user/timer_cases.svh`, `gpio_cases.svh`, `i2c_cases.svh`, `spi_cases.svh`, `uart_cases.svh`
- `user/irq_user_coverage.sv`
- `user/CASE_NOTES.md`

Append to the shared brief, including K0's frozen API:

```text
Implement K3 as explicit empty extension points. One task stub per peripheral
with implemented=0/completed=0 and readable TODO comments linking to its
PLAN.md §5 family; dispatcher/notes also point to §6 masks/priority, §7 commit,
§8 C/memory/loopbacks and §9 coverage. Do not expand the test catalog into
hundreds of empty generated cases. Keep scripts/user code easy to edit manually.

Coverage module has only the empty sampling hook, arguments, ownership comments
and coverage_ready=0. No covergroup/coverpoint/bin/cross/cover property or
coverage percentage. No random fields or SV constraints. CASE_NOTES provides
fillable fields for engineer-chosen values, legality, deadlines, firmware
identity, peer actions, oracle and blockers. Use parent test IDs, not invented
stimulus defaults. Do not write C/ASM programs, a driver adapter, a UART echo,
an I2C slave, an SPI response sequence or a timer setup example that executes.

List all required USER-* TODO IDs from TB_FILE_PLAN.md where they are most
useful. Notes explain the next engineer-written Timer0 path without implementing
it. A stub invocation must remain visibly unimplemented and cannot pass.
```

## 7. Parent integration and review

The parent owns K4: `filelists/irq_tb.f`, `scripts/run_irq_tb.sh`, final README and integration fixes within the agreed contracts. It reviews every child handback and records unavailable checks rather than inventing them. Maximum three K1–K3 children run alongside the parent; no nested delegation is needed.

Before completion, review file ownership, interface consistency, comments/TODO links, absence of user-owned functional bodies, no RTL/driver edits, no dummy PASS, correct current widths and one adapter for hierarchy. A text search for coverage/constraint constructs is useful but not a substitute for reading the code. Compile/elaborate only under the implementation task's authorized validation scope; retain exact commands/logs. Report lack of simulator or manifest defects candidly. No automatic test case or bins should be added to make an empty skeleton appear verified.

If a delegated review round is later requested, launch a new `delegate_task` with its own request ID and include the original scope, findings, responses and unresolved concerns. Do not resume a review by messaging a child backing thread as a new task.

Final skeleton handoff: source paths, reading order, engineer TODO index, build/elaboration evidence or NOT_RUN, open infrastructure issues and explicit confirmation that stimuli/bins/constraints are still engineer-owned.
