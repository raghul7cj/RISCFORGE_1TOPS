# Human-readable interrupt TB skeleton: file and ownership plan

Status: proposed architecture for review. No TB source files, firmware, stimuli or coverage bins have been implemented by this planning update.

Parent plan: [PLAN.md](PLAN.md), ID `IRQ-SOC-20261104`, proposed v2.

## 1. What the skeleton should give you

Open one top file to understand the environment. Open one adapter when DUT hierarchy changes. Open one peripheral TODO file to add an event sequence. Open one coverage file to define your bins. Trace records show observed signals without silently turning them into expected behavior.

Start with ordinary SystemVerilog modules, interfaces, structs and tasks. Use explicit ports and descriptive names. Avoid a new UVM environment, factory, class hierarchy, generic plugin framework, DPI dependency or JSON parser inside SV for this skeleton. This does not waive checklist 6.1; UVM/coreless acceptance is tracked separately in the parent plan.

Use a proposed isolated directory `ips/Verification/irq_tb/` so the new skeleton can be reviewed without changing the existing regression. It shares production RTL through the selected manifest and reuses compatible existing helpers by reference. This is a small new TB entry point, not a copied SoC or a third BSP. Existing incompatible monitors/checkers remain preserved and are not silently patched.

## 2. Ownership boundary

| Area | Skeleton implementation agents | Engineer |
| --- | --- | --- |
| DUT instantiation and adapters | Explicit wiring, documented parameters, read-only normalized signals | Review source identity, boot/reset and compiled scope |
| Clock/reset/loading | Clock, agreed baseline reset and bounded image loading; document assumptions | Select images; write reset-stress sequences and any case-specific timing |
| Monitoring | Sample actual bus/IRQ/commit state, preserve unknowns, emit records | Decide case-specific observations and investigate failures |
| Checking | Entry points, readiness state and structural plumbing only; no fabricated reference model | Define/approve functional expectations and implement or authorize oracle/checker bodies |
| Stimulus | Empty named task hooks and safe idle pin ownership | All raw-MMIO/driver C programs, event triggers, BFM transactions/responses, schedules, fault injection and randomization |
| Constraints | Document fields/extension points and refer to PLAN.md | Scenario constraints, timing bounds, legal distributions and reachable combinations |
| Coverage | Empty sampling hook, sample arguments and readiness status | Covergroups, bins, crosses, exclusions, sampling criteria and closure |
| Reporting | Observed activity counts, files, watchdog/configuration failures, status distinctions | Interpret evidence, set expected counts and approve final results |

The parent agent reviews integration and comments. It does not fill the engineer-owned TODOs during a skeleton merge.

## 3. Proposed files

All paths below are relative to `ips/Verification/irq_tb/`. Every file has one reason to change.

```text
irq_tb/
  README.md                     # how to read/build/extend; current limitations
  tb/
    irq_tb_pkg.sv               # shared records, status and configuration types
    irq_pin_if.sv               # external pin wires and explicit drive ownership
    irq_observe_if.sv           # normalized read-only DUT snapshot
    irq_dut_adapter.sv          # the only internal DUT hierarchy references
    irq_soc_tb.sv               # clock/reset, DUT wiring and visible execution order
    irq_monitor.sv              # cycle sampling and observed activity/trace records
    irq_scoreboard.sv           # checker extension points; unimplemented by default
    irq_report.sv               # one report owner; verdict and trace serialization
  user/
    irq_user_stimulus.sv        # case selection and calls to the empty peripheral hooks
    timer_cases.svh             # engineer TODOs: PLAN.md §5.1 / §6 / §7
    gpio_cases.svh              # engineer TODOs: PLAN.md §5.2 / §8
    i2c_cases.svh               # engineer TODOs: PLAN.md §5.3
    spi_cases.svh               # engineer TODOs: PLAN.md §5.4 / §8
    uart_cases.svh              # engineer TODOs: PLAN.md §5.5 / §8
    irq_user_coverage.sv        # empty sample hook; no covergroup or bins
    CASE_NOTES.md              # selected cases, constraints, firmware and decisions
  filelists/
    irq_tb.f                   # ordered TB sources + reference to pinned DUT manifest
  scripts/
    run_irq_tb.sh              # simple VCS build/run wrapper, no hidden campaign
```

These are proposed future files, not files delivered in this planning turn. A filelist, README and shell wrapper are infrastructure deliverables; the five `.svh` files contain comments and unimplemented task stubs only. They are included by `irq_user_stimulus.sv`, never compiled separately. Keep functions/tasks short; split by responsibility only when readability justifies it.

### 3.1 What each file contains

| File | Contents / public contract | Must not contain |
| --- | --- | --- |
| `irq_tb_pkg.sv` | `irq_sample_t`, `apb_sample_t`, `check_result_t`, run-status enum and a small config struct. Named widths, source count, documented field meaning | Automatic source-to-class oracle, stimulus parameters pretending to be approved constraints, coverage bins |
| `irq_pin_if.sv` | GPIO input/output/enable, UART RX/TX, SPI observed outputs/response input, I2C open-drain nets. Driver versus observer modports | Clocked traffic generator, UART echo, SPI/I2C responder behavior, two owners for one input |
| `irq_observe_if.sv` | Flat snapshot of actual peripheral IRQs, controller/CSR state, acceptance, WB trap, return and bus observations | Hierarchical paths, expected values, signal forcing |
| `irq_dut_adapter.sv` | Explicit read-only `dut...` taps feeding observe fields. Comment each architectural meaning and sampling phase | Source remapping to hide a mismatch, references scattered through checker/user files, writes to DUT internals |
| `irq_soc_tb.sv` | Clock/reset baseline, DUT and module instances, image arguments, safe pin defaults and execution sequence. Calls named tasks visibly | Hidden case logic in long initial blocks, nested factory/config mechanisms, copied DUT RTL |
| `irq_monitor.sv` | Defined cycle sample, raw activity counters, simultaneous-event preservation, bounded recent history | Expected event counts, acceptance inferred from winner, fake ISR counters |
| `irq_scoreboard.sv` | `check_sample(current, previous, result)` entry point, `checker_ready=0` initially, TODOs for event/priority/commit expectations | Completed priority/CSR/reference model, weakened checks or default success |
| `irq_report.sv` | One owner for trace and summary files; fail reason, image/config identity, readiness flags and observed counts | PASS based on simulation completion or firmware signature alone |
| `irq_user_stimulus.sv` | `run_selected_case(case_id, implemented, completed)` dispatch to documented empty tasks | Peripheral programming, generated C, case-specific delay values or random traffic |
| `*_cases.svh` | One obvious stub per peripheral with case-family references and notes on needed observations | Implemented test algorithms, DUT force/deposit, opaque macros that generate cases |
| `irq_user_coverage.sv` | `sample_checked_observation(sample, checks)` task, `coverage_ready=0`, TODO links | Any `covergroup`, `coverpoint`, bins, cross, SVA cover or invented coverage percentage |
| `CASE_NOTES.md` | Fillable table: case ID, plan reference, owner, firmware image, pin schedule, masks, deadlines, expected behavior and blockers | Invented distributions, preapproved constraints or claimed results |
| `irq_tb.f` | Compile order; one selected production manifest; only necessary TB helpers | Wildcards over old/backup files, duplicate module definitions, silent alternate UART/timer selection |
| `run_irq_tb.sh` | Explicit build-only and run modes, checked tool status, output directory and retained commands | Automatic stimulus campaign, hidden retries, missing-image fallback or simulator substitution |

## 4. Small interfaces to freeze before parallel work

Names below describe the proposed public API; K0 freezes exact declarations before later agents write callers. If compiling requires a change, update the contract and all callers together. Do not let three agents invent similar but incompatible records.

### 4.1 Observed sample

- Identity: cycle index, reset epoch and active reset states; simulation timestamp as needed.
- Peripheral outputs: GPIO aggregate and per-pin status observable at ports, I2C IRQ, UART IRQ, SPI `[1:0]`, timer0/1 `[3:0]`.
- Controller: 13-bit raw/pending/clear vectors, `mie`, global MIE, `mintprio`, winner-valid/cause/class; class-1 RR pointer is **two bits**, class-0 pointer one bit.
- Pipeline: actual EX IRQ acceptance, valid/exception tags required to interpret WB, committed interrupt/cause/PC, redirect/target, MRET commit. Keep winner, acceptance and commit as separate fields.
- CSRs: observed mstatus, mtvec, mepc, mcause and mtval; no interpretation masquerading as a source tap.
- Bus: completed APB access, selected slot, address, direction, write/read data, strobes if actually available and error. Document widths and completion condition. Do not invent unavailable strobes at an interface.
- Firmware/mailbox: observed signature/phase only if its actual format and storage are audited; otherwise mark this adapter field unavailable until that work is done.

Use four-state `logic` for observed RTL values. Missing required taps cause an explicit infrastructure error; optional unavailable taps carry an availability flag and cannot count as checked coverage. Do not tie unknown observations to zero and imply the signal was measured.

### 4.2 Calling sequence

```text
top: parse configuration and report requested case
top: initialize ownership/readiness flags and safe external idle values
top: check image, manifest, tap availability and baseline boot prerequisites
top: baseline load/reset/startup; monitor begins observing as defined
top: user_stimulus.run_selected_case(case_id, implemented, completed)
monitor: sample actual signals and expose current + previous record
scoreboard: check_sample(current, previous, result)
coverage: sample_checked_observation(current, result)  [engineer hook]
report: record observations/check status; finalize verdict on explicit completion
```

Top owns process order and completion. One sampling process owns each sampled record and counter; one report module owns file I/O. No mailbox/queue fanout framework is needed for this first skeleton. Watchdogs stay active if a user task blocks. Every hook documents who calls it, when, and whether it can block.

Use an explicitly documented pre-edge sample (`clocking` input `#1step`, or an equivalent reviewed scheme). The record at edge N describes the pre-edge request/commit; resulting CSR state is checked in the subsequent appropriate sample. Do not compare a pre-edge commit with a CSR value sampled in an unrelated scheduling region. Capture simultaneous sources as a vector or separate records; do not lose all but one through repeated nonblocking writes to one trace slot.

The empty checker returns `checked=0`; it does not return a dummy pass. Coverage samples only when the engineer has chosen appropriate checks and sampling criteria. Raw activity counts are diagnostic counts, never a functional coverage percentage.

### 4.3 Completion and honest status

Keep `infrastructure_complete`, `stimulus_implemented`, `case_completed`, `checker_ready` and `coverage_ready` independent and initialized before any process can finish. A missing stimulus cannot be bypassed by setting a global boolean from a plusarg.

| Situation | Required report |
| --- | --- |
| No image when execution requires an image, missing required tap, compile failure or malformed configuration | `INFRA_ERROR` with reason and failing stage |
| Empty user task / no selected implemented case | `NOT_IMPLEMENTED`; no functional PASS |
| Wrapper or checker detects a problem | `FAIL` with first-failure evidence |
| Shell compiled/elaborated or deliberately exercised without functional tests | `HARNESS_ONLY`; explicitly not verification |
| User case completed and required checks passed, coverage not implemented | At most `CHECKS_PASS_COVERAGE_OPEN`, with readiness/status recorded; no coverage closure claim |
| All required checks and user-defined completion criteria met | Eligible for test `PASS`; never automatic gate approval |

Give the run wrapper documented distinct nonzero statuses for unsupported/unimplemented/error outcomes. Preserve simulator exit status separately from TB verdict. Exact exit-code numbers are an implementation detail to freeze in README; no unchecked simulator exit becomes PASS.

## 5. TODO and comment standard

Each file header states purpose, ownership, relevant plan sections and public ports/tasks. Comments explain units, timing, why a signal is tapped, known limitations and who fills a TODO. Avoid decorative change logs, repeated obvious assignments, giant generated banners and promises such as "comprehensive" or "fully verified".

Example engineer-owned hook comment, **not an implemented test**:

```systemverilog
// TODO(USER-STIM-TMR): Engineer supplies timer programming and event timing.
// Plan: ../../../documentation/signoff/irq_event_commit_plan_20261104/PLAN.md
// Section 5.1, EV-TMR-01..10; Section 7, CP-01..03.
// First suggested case: T0C0 compare -> cause 7.
// Observe: completed setup writes, peripheral IRQ, pending, eligibility,
//          accepted packet, WB cause/PC, matching clear and MRET/resume.
// Constraints/deadlines: record the chosen values in user/CASE_NOTES.md.
// Return implemented=0 until your sequence exists; never report dummy success.
```

From `irq_tb/user/` the relative Markdown link above reaches the parent plan. In README use a clickable relative link and text IDs; source comments use the path plus section and IDs so they survive Markdown anchor changes. Do not create a placeholder for every Cartesian-product bin; one understandable hook per peripheral is enough to start.

Required TODO IDs: `USER-STIM-TMR`, `USER-STIM-GPIO`, `USER-STIM-I2C`, `USER-STIM-SPI`, `USER-STIM-UART`, `USER-STIM-COMMIT`, `USER-FW-6_12`, `USER-CONSTRAINTS`, `USER-COV-EVENT`, `USER-COV-MASK`, `USER-COV-PRIORITY`, `USER-COV-COMMIT`, `USER-COV-DRIVER`, `USER-CHECK-EVENT`, `USER-CHECK-COMMIT`. Put commit/firmware references in the dispatcher/notes; no empty firmware files are needed in this delivery.

## 6. Maintainability and source reuse rules

1. The only DUT-internal paths live in `irq_dut_adapter.sv`. Top connects public ports normally. If image loading needs hierarchy, expose the narrowly named loader task through this adapter and document it as the initialization-only exception to read-only operation; never use it to manufacture a test event.
2. Reference active production sources; never copy them into this skeleton. Audit exact timer/UART compiled files and helper dependencies before publishing a build command.
3. The old `irq_monitor.sv` uses six-bit pending fields, a one-bit class-1 pointer and shadow-stack taps. The new 13-source record must not inherit those widths or fictitious nesting signals. The old predictor is not the expected-value model.
4. Keep raw observations distinct from expected source/class policy. A source-label helper for reports must not double as the scoreboard's functional oracle. Source identity/class expectation needs engineer review against DEC-02.
5. Keep protocol responders and firmware bodies user-owned. Safe idle values are defined by actual port contracts; I2C pullups/open-drain ownership must be audited, not copied from an unverified assignment.
6. No copied driver implementation or BSP in this skeleton. Future engineer C tests reference the qualified driver under its IP folder and a reviewed platform adapter.
7. Preserve existing failures and old regressions. No global monitor edits, RTL fixes, checker weakening, simulator substitution or automatic SW/EXT source integration.
8. No scenario `.sv` constraints or random traffic. Suggested legal values/deadlines remain in PLAN.md and CASE_NOTES until the engineer chooses them.

## 7. Skeleton milestones and delegation boundaries

| Milestone | Work | Owner/files | Exit condition |
| --- | --- | --- | --- |
| `K0` | Freeze package/interfaces/API declarations and document known taps | Luna contract agent: package, both interfaces, initial README | Parent reviews API and actual source availability before parallel callers are written |
| `K1` | Wire shell, baseline loading/reset and read-only adapter | Luna shell agent: top + adapter | Clear execution order; no scenario logic or hidden stimulus |
| `K2` | Passive sampling, checker hooks and honest reporting | Luna observation agent: monitor + scoreboard + report | Correct widths/timing, no pretend expected model, no default PASS |
| `K3` | Engineer workspace and TODO references | Luna extension agent: user files and CASE_NOTES | All five peripherals easy to find; no stimulus, constraints, covergroups/bins |
| `K4` | Integrate filelist/build wrapper/docs and review readability | Parent | No missing ports/types, explicit build commands, source scope/limitations and all ownership boundaries documented |

K1/K2/K3 can run in parallel only after K0 freezes interfaces. The shared checkout is acceptable with these non-overlapping file owners; agents must not edit another agent's files or start nested delegation. One parent plus three working agents fits the available slots. No agent is launched during planning.

Validation scope for the later skeleton delivery: source/API/link review and compilation/elaboration on the authorized available simulator; keep logs and command identity. No peripheral event campaign, functional coverage collection or checker proof is implied. A requested harness smoke can demonstrate infrastructure only and must be labeled `HARNESS_ONLY`; do not insert a Timer0 test to obtain a pass. If compilation exposes a substantive RTL or manifest defect, report it and preserve evidence rather than fixing the design.

The engineer's next step after K4 is to select `EV-TMR-01` with `CP-01` as the first written path, fill `USER-STIM-TMR`, define expected checks and add the corresponding coverage. The original S0–S5 verification campaign follows that first understandable test.

## 8. Deliverables at the skeleton handoff

- The files in section 3, with comments and API ownership visible from the top.
- README reading order: top → interfaces/package → adapter → monitor → checker/report → user hooks.
- A TODO index linking each engineer-owned entry to the exact parent test/coverage plan IDs.
- Pinned manifest and adapter limitations; build/elaboration logs if authorized and performed, otherwise explicit `NOT_RUN`.
- Example report **schema** with no fabricated simulation results and no mandatory golden PASS transcript.
- Remaining implementation tasks separated into user stimuli, user coverage, reviewed functional checkers and infrastructure defects.

See [DELEGATION_BRIEFS.md](DELEGATION_BRIEFS.md) for model configuration and task prompts. The briefs are ready for a later implementation instruction; preparing them does not start those tasks.
