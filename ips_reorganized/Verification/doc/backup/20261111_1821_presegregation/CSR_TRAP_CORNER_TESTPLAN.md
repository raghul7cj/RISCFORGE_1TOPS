# CSR, exception and interrupt corner-case test plan

Created: 2026-11-03. Architecture proposal added: 2026-11-04. Status updated 2026-11-11: the CSR unit bench is implemented and simulates in local XSim (552 checks, 0 failures, 56 spec-pending cases, observed-attempt bins only); the core bench remains a reset-held skeleton with no stimulus. No closure claim.

## 1. Bench decision and scope

Use **two new testbench tops**, with several selectable suites in the core harness. Keep the existing IRQ unit regression as a third evidence boundary.

| Bench | DUT boundary | Owns |
| --- | --- | --- |
| Existing `tb_irq_restructure` | Gateway, arbiter, independently driven CSR and commit-controller instances | Exhaustive unit arbitration, source eligibility, pending capture, RR feedback and existing IRQ-facing CSR checks. |
| Proposed `tb_csr_corner_unit` | `csr_regfile` | CSR port collisions, status transitions, counter rollover/write collisions, reset and preservation of unrelated CSR state. |
| Proposed `tb_core_csr_trap` | Actual `riscv_core/rtl/top.v` with instruction/data memory models and driven IRQ pins | Exception generation, trap/MRET commit and redirect, CSR dependencies, precise side effects, interrupt ordering and interruption of memory/M operations. |

Exceptions, interrupts and CSR hazards share the **same core harness** because their important failures involve interactions between those features. Select `exception`, `csr_hazard`, `irq_hazard`, `mret`, or `collision` tests through a test ID; do not make separate copies of the core/memory/monitor infrastructure.

Ordinary CSR instruction semantics are assigned to RISCOF by the engineer. These benches use ordinary accesses for setup and observation and exercise the CSR instructions where dependencies or collisions matter. The earlier inspection did not establish a current qualifying RISCOF result; that evidence dependency remains separate from implementation of this plan.

This plan supports G2.9 review and the relevant unit/core verification requirements. Passing it alone does not close G2, all of G4, or SoC peripheral-to-handler validation.

## 2. Existing assets and reuse boundary

- `Verification/tb_irq_restructure.sv` and `Verification/IRQ_UNIT_COVERAGE_PLAN.md`: reuse the established source map and retain its coverage results separately. Its CSR trap input is driven directly, and its controller instance has constant MRET/target inputs; it does not establish the complete controller-to-CSR or pipeline path.
- `Verification/tb1_interrupts.sv`, `tb1_interrupts.f`, and associated generated programs: reuse suitable program/setup ideas after interface review. Its seven-source priority assumptions and DIV interrupt expectation require reconciliation with the present architecture. The present core uses timer cause 7 and local causes 16 through 27. Do not copy the old bench's expectations as the oracle.
- `riscv_core/rtl/csr_regfile.v`, `wb_trap_mret_commit_controller.v`, `hazard_unit.v`, and the actual core top define implementation interfaces. The approved architectural contract defines expected results.
- `documentation/signoff/CSR_and_Trap_Model.md` and `Core_Microarchitecture.md` are static descriptions with open questions; they are not proof of correct behavior or substitute approval for those questions.

## 3. Harness and checking design

### CSR unit harness

Drive CSR read/write ports, trap metadata, MRET ports, retirement and pending inputs directly. Maintain a small independent CSR state model using approved masks and event rules. Snapshot unrelated state before collisions and check preservation afterward. Ordinary setup writes are not credited as corner-case coverage.

Distinguish legal connected-core traffic from deliberately simultaneous raw port inputs. Raw trap+normal-write or inconsistent MRET-port combinations test a leaf interface contract; they cannot establish that the core supplies correctly gated inputs.

### Core harness

Instantiate the current `top.v`, reuse its existing RTL dependencies, and use one consistent core-only address configuration. The existing core bench's `RESET_PC=0x80000000` and data base `0x80001000` are a possible harness configuration; record the chosen values in the manifest. This does not claim the SoC boot/address-map path is tested.

Use the actual instruction-memory timing contract. The current fetch interface has no external ready/error input, so do not invent instruction wait states or claim instruction-access-fault injection through that interface.

Use a data-memory responder that can schedule successful or error completion after 0, 1, or multiple wait cycles. It must record one transaction per protocol completion, retain the identity of an outstanding request, and check address/data/strobe stability while stalled. A held request is not a new store on every clock. Rejected accesses have no modeled memory effect. Track attempted, completed and side-effecting transactions separately.

Drive interrupts at the public IRQ pins. Use instruction symbols/PCs and observed pipeline phases to position stimuli; avoid fixed cycle delays that silently miss the intended overlap. Observe internal pipeline signals through a read-only probe where necessary. Program symbols and the independent event/state model supply expected PCs, causes and data; the observed DUT trap fields must not supply their own expected values.

A common scoreboard checks:

1. Expected exception/IRQ count, identity, PC, trap value, redirect and status transitions.
2. Older instruction effects and the absence of faulting/squashed instruction effects on GPRs, CSRs and memory.
3. Trap/MRET commit, redirect and IRQ acknowledgement consistency; pending capture/clear and RR feedback at their specified boundary.
4. Return/replay PC and exactly-once effects after MRET. Interrupt replay and synchronous exception recovery use different expected PCs; recovery policy is explicit in each program.
5. Forwarding/stall results for CSR dependencies and continued pipeline progress within the declared latency bound.

Do not infer precise memory behavior solely from WB signals: stores or MMIO-like writes can produce an external effect before WB. The memory responder's transaction ledger must catch a younger store escaping an older trap. A responding access-fault model cannot prove a real peripheral rolls back side effects; that is an interface/integration contract.

## 4. Scenario priorities

All entries below are planned, not passed. Each test must name its expected result, checker IDs and required coverage bins before execution.

| ID | Priority | Stimulus and distinguishing check |
| --- | --- | --- |
| CT01 | P0 | Exception triggers with distinctive PC/instruction/address values; compare `mepc`, `mcause`, `mtval`, redirect and status. Establish a checked reference case before hazard variants. |
| CT02 | P0 | ECALL/EBREAK/illegal instruction followed immediately by a store, CSR write or GPR write; older work completes and younger effects never escape. |
| CT03 | P0 | Exception and eligible IRQ overlap; synchronous exception wins at the defined instruction/order boundary and the IRQ is retained/serviced according to its source contract. |
| CT04 | P0 | Adjacent CSR producer/consumer and CSR-result-to-GPR consumer; check old/new values and dependent instruction results through actual E/M/W hazards. |
| CT05 | P0 | IRQ with an older `mstatus`, `mie` or `mintprio` write in M/W; the observed retirement boundary must honor instruction order and effective interrupt eligibility. |
| CT06 | P0 | Exception/redirect with older memory waiting and with memory completion; no lost exception, corrupted frozen packet, duplicate transaction or younger side effect. |
| CT07 | P0 | IRQ at M-operation issue, busy and completion; check trap count, valid result retirement, stale completion suppression and replay/defer behavior under the approved policy. |
| CT08 | P0 | `mepc` write immediately before MRET, and pending IRQ across MRET; check target, MPIE/MIE update and the first resumed instruction. |
| CT09 | P1 | Every active source traverses the core to the trap handler; release pending IRQs through global enable, source enable and class threshold changes. |
| CT10 | P1 | Illegal opcode/function/SYSTEM/CSR-access variants, misaligned control targets and memory accesses, and delayed load/store error responses. Check no trap on the matching legal guard cases. |
| CT11 | P1 | Trap versus branch/jump redirect; older versus younger exception candidates; exceptions/IRQs in invalid or flushed slots. Only the architecturally valid oldest event commits. |
| CT12 | P1 | `mtvec` write before a trap, back-to-back trap/return sequences, repeated level IRQ, rearmed edge IRQ and events arriving near acknowledgement. |
| CU01 | P0 | Unit CSR collision and status-transition tests; inspect every target's specified priority and preserved state. |
| CU02 | P1 | Counter carry/wrap and writes concurrent with increment, trap or MRET; reset during active control events. |

## 5. Functional coverage model

Use named covergroups with explicit bin sets. Every mandatory bin has an owner bench, test ID and checker. Report **attempted** stimulus separately from **checked** outcomes. Sample closure coverage only after the scenario has occurred and its complete expected result passes. No-event checks require a declared observation interval and subsequent progress, not an empty waveform.

The counts below describe individual crosses; do not sum them into a percentage of correctness. Overlapping coverpoints and crosses are intentionally reported separately.

### Unit-owned bins

| Group | Required bins/crosses | Check |
| --- | --- | --- |
| `u_status` | Trap entry: old MIE {0,1} x old MPIE {0,1}; MRET: old MIE {0,1} x old MPIE {0,1}; 4 cases each. | Correct status transition and preservation of unrelated bits/state. |
| `u_metadata` | Exception causes {0,2,3,4,5,6,7,11}; IRQ causes {7,16..27}; each with distinctive zero/nonzero PC/value setup as applicable. `trap_addr_valid` {0,1} is tested as a raw CSR interface contract. | Correct capture/clearing without deriving expected metadata from output. Core IRQ `mtval=0` is checked separately. |
| `u_collision` | Normal-write collisions {normal+trap, normal+MRET, all three} x targets {mstatus,mie,mtvec,mscratch,mepc,mcause,mtval,mintprio,mip,mcycle,mcycleh,minstret,minstreth}: 39 scenarios. Add one trap+MRET scenario without a normal write: 40 total. | Approved per-register write priority, counter behavior and preserved state. Raw-only cases remain labeled as such. MSIP collision expectations are pending a contract decision. |
| `u_counter` | Counter {mcycle,minstret} x boundary {low-half carry,64-bit wrap}: 4 cases. Counter x written half {low,high} x concurrent event {ordinary increment,trap,MRET}: 12 cases. Retirement {0,1} is observed where relevant. | Exact 64-bit result, enable and write/increment priority. Setup is through ports; avoid forcing state to conceal incorrect setup behavior. |
| `u_reset` | Reset with {normal write,trap,MRET,trap+normal write} active. | All specified reset state including MSIP/counters; no delayed update when reset releases. |

The collision model must not assume one global CSR priority. The current `csr_regfile` main process gives trap and MRET precedence over ordinary writes, while `msip_r` is written in a separate process. Counters also increment outside the main priority chain. Record the approved expected behavior for these separately.

### Core-owned bins

| Group | Required bins/crosses | Check |
| --- | --- | --- |
| `c_exception` | Causes {0,2,3,4,5,6,7,11}. Trigger subtype bins below; matching legal/no-trap guards remain separate. | Correct architectural trap bundle and faulting instruction effects. |
| `c_csr_dependency` | Adjacent producer x consumer CSR instruction forms {RW,RS,RC,RWI,RSI,RCI}: 36 pairs on a suitable writable scratch CSR. Producer family {write,set,clear} x consumer family {write,set,clear} x distance {1,2}: 18 additional bins using representative register forms. CSR-result GPR consumer {ALU,branch,store address,store data,CSR source} x separation {0,1,2}: 15 pairs. Seven named operand/destination-suppression bins are listed below. | Sequential expected value and dependent result; zero source/destination semantics remain correct through a hazard. |
| `c_irq_delivery` | Active cause {7,16..27} x release condition {already eligible,global unmask,source unmask,threshold unmask}: 52 bins. | No premature trap; matching source commits and handler sees expected metadata. Source eligibility unit coverage is retained separately. |
| `c_irq_order` | Older gating-CSR target {mstatus,mie,mintprio} x eligibility change {allow,block} x writer stage at IRQ arrival {M,W}: 12 bins. `mtvec` update before trap and `mepc` update before MRET each have producer separation {0,1,2}. | Architectural instruction order, correct target and no lost/redundant acknowledgement. Acceptance/cancellation machinery is observed, not prescribed by the checker. |
| `c_irq_phase` | Representatives {timer 7/event/class 2, GPIO 16/edge/class 0, UART 19/level/class 1} x arrival window {ordinary ALU,CSR in E,memory wait entry,memory wait middle,memory response,MRET before commit,MRET commit,MRET after commit}: 24 bins. | Correct source behavior, precise effects and eventual progress under the specified policy. |
| `c_m_interrupt` | M operation {MUL,MULH,MULHSU,MULHU,DIV,DIVU,REM,REMU} x IRQ arrival {issue,busy,completion}: 24 bins using one representative IRQ. Add DIV/DIVU/REM/REMU divide-by-zero paths and signed DIV/REM overflow paths with IRQ at early-result timing. | Exactly one lawful retirement/replay sequence, no stale destination write and correct final result. These check interruption paths rather than an arithmetic campaign. |
| `c_exception_overlap` | Explicit legal scenario bins listed below; no blanket cause x every stall/flush cross. | Event occurs in the intended window and the relevant precision checker passes. |
| `c_mret` | Initial MPIE {0,1} x pending IRQ {absent,present}: 4 bins; replayed instruction class {ALU,CSR,load,store,MUL,DIV}; consecutive handler entries; software context-save/restore if nesting is approved. | Correct state/PC, effects and trap counts. No hardware shadow-stack assumption. |

Separation/distance 0 means adjacent instructions, 1 means one independent intervening instruction, and 2 means two. Keep the actual producer/consumer overlap in E/M/W as a diagnostic coverpoint so an unintended stall cannot masquerade as the intended pipeline overlap.

The seven suppression bins are: CSR write with `rd=x0` followed by a same-CSR read; CSRRS with `rs1=x0`, CSRRC with `rs1=x0`, CSRRSI with zero immediate, and CSRRCI with zero immediate each followed by a trap; CSRRW with `rs1=x0` and CSRRWI with zero immediate each followed by a same-CSR read. Choose instruction timing and operand values that distinguish an omitted write, an unintended write and an incorrect returned value.

Exception trigger subtype bins:

- Cause 0: taken conditional branch, JAL and JALR with a genuinely misaligned effective target. Separately check an untaken branch with a misaligned encoded target and JALR raw target low bits {00,01,10,11}; distinguish required bit-0 normalization from an actual alignment exception.
- Cause 2: bad opcode, reserved funct3, reserved funct7/shift encoding, unsupported SYSTEM encoding, unimplemented CSR address and forbidden read-only CSR write. Scope/required behavior must follow the declared ISA; unsupported tests do not become ignored bins merely because RTL accepts them.
- Causes 4/6: LH/LHU/SH at byte offsets {1,3}; LW/SW at offsets {1,2,3}; 12 misaligned operation/offset cases. Include aligned half/word accesses and all byte offsets as no-trap guards around the same stall scenarios.
- Causes 5/7: load/store response errors with latency {0,1,multiple}; distinguish permitted faulting requests from forbidden misaligned/squashed requests.
- Causes 3/11: EBREAK and ECALL in the hazard sequences, using the specified `mtval` value rather than assuming the current implementation is authoritative.

Required `c_exception_overlap` scenario bins:

1. ID exceptions (illegal/ECALL/EBREAK) behind an older waiting data transaction.
2. EX control-target misalignment behind an older waiting transaction.
3. Misaligned load/store following a completed wait; stale wait state must not erase/block the exception.
4. Load/store error returned after a held request.
5. Older MEM exception versus younger EX exception or IRQ candidate.
6. Older trap versus younger store, CSR write and GPR write (three separate bins).
7. Trap redirect versus branch/jump redirect and versus frontend hold (separate bins).
8. Flushed or invalid exception candidate, invalid IRQ candidate, and M-operation issue while an older transaction waits (separate bins).

For each overlap row, enumerate applicable members as individual named bins in the coverage manifest. Do not credit an OR-reduced generic "hazard seen" bin as completion of all members.

### Observation and outcome bins

Keep diagnostic outcomes {committed,deferred,replayed,cancelled,unexpected/failed} separate from required stimulus coverage. Do not demand both abort and defer outcomes if the architecture selects one. A failure is recorded as a failure even if the arrival/window stimulus bin was hit. A masked source that never becomes eligible cannot count as a successful delivery.

A single bound observer supplies checked events to all core covergroups. Exact cycle relations are sampled at the clock phase specified by the interface, with CSR state checked after sequential updates. Coverage attributed to pipeline stage refers to the observed stage at IRQ arrival, not when the stimulus task intended to drive it.

## 6. Pending architectural expectations and coverage dispositions

These questions do not block building the common harness or unambiguous tests. They block final expected results/coverage closure for the affected scenarios.

| Decision | Coverage effect |
| --- | --- |
| IRQ during busy MUL/DIV: abort/replay or defer, and bounded service time | Set the oracle and deadline for CT07; retain all arrival-phase bins. The old bench's "no acceptance during stallMUL" expectation conflicts with current preemption comments and must not be copied. |
| Older gating-CSR update versus IRQ acceptance | Define the legal architectural retirement boundary for CT05. A trap cannot simply use a stale threshold/mask after an older committed write without a specified ordering model. |
| Invalid CSR/encoding traps, read-only access and `mtval` policies | Set the illegal trigger expectations and metadata values; do not adopt silent read-zero/write-ignore as expected just to pass. |
| Direct-only versus vectored `mtvec` | Current CSR writes mask MODE bits; vectored controller code is not software-reachable through that CSR. Report this code path as unresolved/unreachable pending an approved disposition; a forced internal mode is not core reachability evidence. A future controller-only fixture may test its raw input contract if needed. |
| Machine software/external IRQ delivery | Current arbiter handles cause 7 and 16..27; inputs 3/11 are not delivered by that path. Track their requirement disposition explicitly instead of silently excluding them. |
| Instruction-access-fault support | Current fetch port has no error input. Cause 1 is a documented interface/specification gap until resolved; it cannot be marked covered by manipulating internal exception signals. |
| Raw CSR-port priority, especially MSIP, and counter semantics during trap/MRET | Approve per-register unit expectations; legal core gating remains independently checked in the core bench. |

## 7. Closure and evidence rules

- Before implementation, assign every planned bin a stable ID, test owner, checker ID and status {planned,spec-pending,implemented,attempted,checked,failed,approved-exclusion}. Generated cross bins must have an explicit legal set and count.
- Target 100% of approved mandatory functional bins **per group and bench**, zero unexplained checker failures, and zero uncovered required scenarios. This is a proposed target for this suite, not an already approved project-wide coverage target. Never average unit and core percentages.
- Review code coverage for the current RTL separately. Report unhit statements/branches/toggles and source scope; agree code coverage targets and exclusions. Functional closure cannot waive untested control paths automatically.
- An exclusion needs a requirement-based reason and owner approval. Unknown/unimplemented requirements remain open. Reachability problems, tool limitations, failures and unsupported interface paths do not disappear from the denominator without a recorded disposition.
- A test passes only when all required observations occur, expected outcomes match, no assertion/scoreboard failure remains, no expected event is outstanding, and the declared progress deadline is met. A completion sentinel alone is insufficient.
- Demonstrate checker effectiveness with deliberate negative controls for wrong trap metadata and an unexpected/duplicate memory effect; ensure each fails the run. These are checker tests with separately labeled expected-failure results.
- Retain test ID, seed, source revision plus dirty/source hashes, filelist and program hashes, tool/version, exact command, architectural expectation version, waveform/logs, checker counts and coverage database/report. Choose accepted signoff tools separately from exploratory runs.
- Run each scenario from known reset/state. Merge databases only for the same DUT/expectation/coverage-model identity and compatible tool settings. Preserve failing tests and logs.

## 8. Implementation order after plan review

1. Implement the shared core memory/probe/scoreboard harness and CT01/CT02, including a negative checker control. Establish precise trap metadata and the younger-store check first.
2. Add CSR unit collision/status tests CU01 and core dependencies CT04. Include CSR-to-GPR hazards in E/M/W.
3. Add CT03/CT05/CT06: exception/IRQ/older-CSR/memory-wait collisions. Resolve each open expectation before asserting a pass.
4. Add CT07/CT08: M-operation arrival phases, stale completion and MRET ordering. Record any existing RTL failure without changing expected results.
5. Complete source delivery, remaining trigger guards, counter/reset corners and coverage-directed missing cases. Review code coverage and exclusions before proposing closure.

Proposed future layout: `infrastructure/tb/tb_csr_corner_unit.sv`, `infrastructure/tb/tb_core_csr_trap.sv`, shared observer/checkers/coverage under their existing infrastructure directories, and independent filelists under `filelists/tier1_unit/`. Core program assets should have one dedicated directory and generated symbol metadata. These paths describe a proposal; only this test-plan document is created now.

## 9. Testbench architecture proposal: module SV and lightweight OOP SV

### Decision

Verification level and testbench framework are separate choices. A unit testbench can use modules/tasks, plain SV classes or UVM. Functional covergroups and assertions are available with each approach; choosing UVM does not by itself establish suitable coverage or an independent oracle.

For this scope, propose **module-based SystemVerilog for `tb_csr_corner_unit` and lightweight class-based SystemVerilog for `tb_core_csr_trap`**. Both remain unit/core verification environments. Use the existing IRQ unit bench as its own regression target. This is an architecture proposal for engineer review, not authorization to change DUT behavior.

| Option | Fit for the current task | Decision |
| --- | --- | --- |
| Modules, tasks, functions, covergroups and SVA | Direct CSR ports, a small state model and deterministic simultaneous events are easy to observe and debug. A growing core scenario scheduler would become harder to share if all tests were embedded in the top module. | Use for the CSR unit top and static core BFMs/probes/assertions. |
| Plain SV classes with virtual interfaces | Shares stimulus scheduling, expected-event tracking, coverage and reporting across many program/IRQ/stall scenarios without duplicating harnesses. | Use for the core environment and selectable test suites. |
| UVM | Useful when an established UVM environment, reusable protocol agents, sequencer arbitration, standard component configuration or project methodology requires it. It would add component/phase/factory structure to this bounded directed campaign. | Do not introduce it for the proposed first implementation. Reconsider if an existing reusable core UVM environment is identified or the project mandates UVM at this boundary. |

The checklist's SoC UVM/VIP requirement is a separate obligation; choosing plain SV for these benches does not waive it. Keep protocol/observation contracts and checking logic reusable so a later UVM environment can call or wrap them. Do not promise a conversion without integration work.

### CSR unit top

Keep this bench small and explicit:

1. A static top instantiates only `csr_regfile`, generates the clock and owns reset.
2. A CSR interface defines input drive and output sample timing. Tasks drive read/write/trap/MRET port combinations from a scenario record. One driver owns each input.
3. A reference state structure and pure update/check functions model the approved per-register contracts. Model state is updated from driven inputs and prior expected state, never by copying the DUT's CSR outputs.
4. Directed tasks implement status, metadata, collisions, counters and reset suites. Shared setup/read/check tasks keep each case short.
5. A coverage collector owns `u_status`, `u_metadata`, `u_collision`, `u_counter` and `u_reset`. A small result recorder supplies case ID, checks attempted/passed, failures and outstanding obligations to finalization.

Classes are optional for storing configuration/coverage here; no environment/sequencer/agent hierarchy is needed for the proposed unit stimulus. Raw port collision tests retain their separate scope labels.

### Core static harness

The top module contains components that need direct signal connectivity or clocked behavior:

- The actual core DUT, clock generation and interfaces. A single reset/stimulus owner drives reset and IRQ pins through a clocking block.
- An instruction-memory model matching the current fixed response timing, with program loading completed before reset releases.
- A data-memory BFM with a configuration/request API for latency and error schedules. The BFM alone drives data response/stall/error signals and records attempted/completed memory effects.
- A read-only probe exposing coherent pipeline/trap/retirement observations through a typed observation interface. Inventory the actual available PC/instruction identity before implementation. If the existing RTL lacks enough information to identify a retirement event, record the instrumentation requirement; do not infer the expected retirement PC from the DUT's trap target.
- Bound or instantiated assertions for the chosen request stability, validity, redirect and side-effect contracts. Assertions depend on the approved interface contract and sample phase.

Internal DUT signals are observation points. The scheduler uses public IRQ/memory inputs to create legal core scenarios. Raw control-port robustness testing belongs to the CSR unit fixture.

### Core class environment

Use a short hierarchy with explicit constructor arguments and typed mailboxes/interfaces:

| Class/object | Responsibility and contract |
| --- | --- |
| `scenario_cfg` | Test ID, seed, program/symbol metadata, selected IRQ source, trigger window, memory response schedule, expected events, expectation-version ID and timeout bounds. Treat the resolved configuration as immutable during a test. |
| `corner_test` | Common `configure` and `run` contract. Derived exception, CSR-hazard, IRQ-hazard, MRET and collision suites select programs and scenario configurations; they share the environment. Select the test with a test ID, initially one scenario per simulator invocation. |
| `corner_env` | Constructs components, gives them virtual interfaces, starts/stops observation and schedules stimulus, then requests final checking. It owns test lifetime; no separate framework phases or factory are proposed. |
| `event_scheduler` | Waits for an observed PC/stage/transaction window and drives the configured event at the declared drive phase. Reports a missed window as a failure. IRQ and memory controls have one owner each; stimulus plans request actions from that owner. |
| `core_event` | Timestamped observation record for memory transaction, CSR/GPR effect, trap, MRET, redirect or pipeline phase. Copy records before placing them on queues so later signal changes cannot alter a queued event. |
| `trap_scoreboard` | Uses program expectations, architectural CSR state and observed events to check metadata, ordering, absence of forbidden effects, replay and progress. Maintains expected/outstanding events and the memory-effect ledger. It is a focused reference model, not a new full ISA simulator. |
| `corner_coverage` | Owns core covergroups. Receives attempted-window observations and separately receives checked scenario results from the scoreboard. Only completed passing results sample closure groups. |

Use composition for the environment components. Restrict inheritance to test specializations initially. A generic UVM-like agent, sequencer, factory, phase engine or new ISS is outside this proposed architecture.

### Data flow and timing

1. The selected test loads its program and expected metadata, configures memory behavior, then requests reset/release through the sole control driver.
2. The observer publishes sampled events. The scheduler identifies the required trigger window, and the responsible input driver applies the event using the declared clocking-block phase.
3. The scoreboard consumes observation records and compares them with the expected event/order contract. The memory ledger checks effects at the external interface in addition to architectural WB observations.
4. A passing scenario result carries its scenario/bin IDs to `corner_coverage`. An attempted window remains visible even when the checker fails; it cannot be reported as successful closure.
5. The environment ends the test only after required events and quiet/progress intervals are checked. Finalization requires nonzero expected activity, no failures, no outstanding expectation and no watchdog expiry; otherwise the simulator exits with a failing verdict.

Define drive, pre-edge packet sampling and post-update CSR-state observation phases explicitly. Trap/MRET packets and the resulting CSR state are different observations. This prevents a race from checking an old value or sampling the same commit twice. Test window metadata must state whether "at completion" means IRQ present before or after the completion sampling edge.

### Coverage ownership and planned files

Maintain the coverage ownership from section 5: unit groups live with the CSR unit fixture; core groups live in `corner_coverage`; IRQ unit groups stay in the existing bench. Share enum names, test IDs and result formatting, not mutable reference state across independent benches. Avoid a combined unit/core coverage percentage.

Proposed implementation files, relative to `ips/Verification/`:

- `infrastructure/tb/csr_trap/csr_trap_types_pkg.sv`: scenario IDs, enums, event/configuration types and result types.
- `infrastructure/tb/csr_trap/csr_corner_if.sv`: direct CSR fixture interface.
- `infrastructure/tb/csr_trap/core_corner_if.sv`: stimulus, memory configuration and observation interface contracts.
- `infrastructure/tb/csr_trap/csr_trap_env_pkg.sv`: core classes, with small included source files if needed for readability.
- `infrastructure/tb/csr_trap/core_corner_imem.sv` and `core_corner_dmem.sv`: memory models.
- `infrastructure/checkers/core_csr_trap_probe.sv` and `core_csr_trap_assertions.sv`: passive observation/assertions.
- `infrastructure/tb/tb_csr_corner_unit.sv` and `tb_core_csr_trap.sv`: the two independent tops.
- `filelists/tier1_unit/tb_csr_corner_unit.f` and `tb_core_csr_trap.f`: separate compilation roots and top selections.
- `tests/csr_trap/`: directed programs, expected event metadata and generated symbol maps, with source/generated identity recorded.

Compile shared types before interfaces, interfaces before packages referring to their virtual interface types, and packages/BFMs/probes before the relevant top. Select and confirm the intended simulator before coding simulator-specific reporting hooks. SV classes, covergroups, SVA and the required code-coverage instrumentation must all work in that selected flow.

### First implementation milestone

Implement one test from each architecture before expanding the class/test inventory: a unit trap-versus-normal-CSR-write collision, and a core ECALL followed by a younger store. Require independent expected metadata/state, a checked memory-effect ledger, mapped bins and a deliberate negative checker test. Use this milestone to review the interface/observer contract and class boundaries. Then add the remaining suites in section 8 using the same harness.

## 10. Authorized skeleton scope and engineer ownership

The engineer's 2026-11-04 instruction limits the next implementation to a readable, connected skeleton. This scope takes precedence over the functional first-milestone scenarios above for the current task.

- Build and connect the two tops, interfaces, passive probe, typed event/configuration plumbing, class environment, memory-model shells, checker/coverage hooks and separate filelists.
- Use consistent spacing, short names that describe purpose and minimal useful comments. Mark unfinished work with `TODO(USER_REF_MODEL)`, `TODO(USER_COVERAGE)` and `TODO(USER_STIMULUS)` at the intended extension points.
- The engineer owns reference-model design/signoff, coverage-bin definitions and later stimulus. Do not implement those behaviors, populate coverage bins, create executable scenario programs or encode unresolved architectural expectations now.
- Existing DUT RTL, existing IRQ tests and their expected results remain outside the implementation scope. Actual DUT ports must be connected explicitly, with one driver per driven signal and coherent compile ordering.
- Distinguish structural completeness from functional verification. Skeleton execution must identify itself as incomplete and cannot report a test PASS, coverage closure or a verified architectural result. Syntax/elaboration checks may be used if a suitable simulator is available.
- Delegated implementation receives a standalone brief, this plan and targeted DUT/filelist references; it does not need the surrounding conversation.

## 11. Implementation status — 2026-11-11

Section 10 records the 2026-11-04 skeleton scope. Under the later instruction to implement and run the unit bench, `tb_csr_corner_unit` now carries:

- `status_cases` (8), `metadata_cases` (168), `collision_cases` (40), `counter_cases` (16), `reset_cases` (4): 236 cases.
- Checked expectations for status, metadata and reset (552 comparisons, 0 failures); collision and counter cases stay `spec_pending` (56 observations, no assertion).
- Five observed-bin groups covering those 236 cases, sampled once per case, reported at 100% each.

`tb_core_csr_trap` remains at section 10 scope: it compiles (39 sources), elaborates and runs 30 ns reset-held with `checks=0`.

Results, evidence paths, integrity re-verification and the open specification decisions D1–D6 are recorded in [CSR_TRAP_VERIFICATION_STATUS.md](CSR_TRAP_VERIFICATION_STATUS.md). No closure or signoff credit follows from this status.
