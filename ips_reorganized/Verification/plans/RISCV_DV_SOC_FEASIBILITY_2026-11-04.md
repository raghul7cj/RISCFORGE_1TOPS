# RISCFORGE SoC randomized verification integration plan

Assessment date: 4 November 2026. Planning basis: six team members, four committed weeks for verification closure, and approximately two further weeks of flexibility. PDK access is currently blocked. This document proposes work; it does not claim that any new flow has compiled, simulated, or passed.

## Recommendation

Integrate riscv-dv as a software stimulus producer into the existing full-SoC verification environment. Keep the real core, memories, fabric, timers, and peripherals in the DUT. Extend the external pin models into deterministic, constrained-random event agents. Make independent interrupt, transaction, and peripheral checkers responsible for the verdict.

Commit to Level 2 below and a bounded Level 3 architectural comparison campaign during the four weeks. Prototype live Spike co-simulation early, but make its expansion conditional on a working proof of concept. Do not make an unfinished co-simulator the dependency that prevents the rest of the SoC from being verified. Any required Rev B obligation still missing at closure is explicitly OPEN or subject to a mentor-approved scope change; completing a feasibility level does not itself satisfy Rev B.

Agentic AI can accelerate implementation, test generation, documentation, and reproducible failure reduction. It does not establish architectural intent, model independence, or signoff. Each checker has a named human owner, a peer reviewer, and a negative test demonstrating what it can detect.

## What the inspection established

The review read `RISCFORGE_Verification_Plan_RevB.docx`, the local SoC hierarchy and relevant verification files, and the remote `/home/iiita/riscv-dv` checkout through `Invoke-CadenceCommand`. Existing failing regression logs were outside scope. No RTL, expectations, or remote files were modified; no new simulations were run.

| Area | Observed infrastructure | Consequence |
|---|---|---|
| Remote generator | riscv-dv upstream base `b7a0b4b`, with local tracked changes and untracked targets/scripts | Pin both the upstream commit and the complete extension/patch identity, not just the commit |
| Remote execution | Makefile compiles core RTL into `RTL_5STAGE_UPDATED/tb_riscv_dv.sv`, with behavioral instruction/data memories and `TEST_BASE=0x80000000` | It is not yet a full-SoC execution flow |
| Full-SoC shell | `Verification/infrastructure/tb/soc_tb_top.sv` instantiates `riscforge_soc_subsystem`, external models, monitors, checkers, warm/cold boot, and completion checks | Reuse the shell, after checking its bindings against the selected RTL |
| Memory and boot | Core reset PC is zero; application ISRAM starts at `0x00010000`; DSRAM starts at `0x00020000`; each SRAM is 32 KiB | Relink generated programs; retain BootROM entry; split ELF output into IMEM and DMEM images |
| Interrupt hardware | Local `top.v` connects a 13-bit gateway: cause 7 and causes 16 through 27. Arbiter uses three classes and software-managed `mintprio` at `0x7C0` | Rev B's six-source and hardware-shadow-stack assumptions no longer describe this local core |
| Trap vector | Commit controller computes direct and vectored targets, but CSR writes retain the old `mtvec[1:0]`; reset initializes MODE to zero | Direct dispatch is reachable; hardware vectored mode needs an explicit architecture/RTL decision |
| Existing BSP | Direct trap entry saves caller-saved registers, calls C, and returns; synchronous exception path records a signature and halts | It is a starting point, not yet a general random-program/nested-trap runtime |
| IRQ predictor | Models an older hardware stack, treats SPI cause 27 as class 2, and is wired to post-gateway `fast_intr_core` | Requalify or replace it from the current interrupt contract before grading results |
| MMIO scoreboard | Current body checks completed APB address-to-slot decode; LSU inputs are not correlated into an expected transaction queue | End-to-end lost/duplicate/modified access checking is additional work |
| Pin models | UART supports loopback and TX logging; GPIO exposes drive/release tasks; I2C and flash models are instantiated | Reuse interfaces, but random stimulus, response policies, scoreboards, and coverage are not established by a VIP filename |
| Retire monitor | Captures instruction/trap information into a 64-entry diagnostic ring; instruction word is presently supplied through a shadow lookup fallback; MRET input is `is_mret_W` | Add a qualified lossless trace stream, real instruction correlation, and commit-qualified MRET events for architectural comparison |

Local and remote RTL anchor files have different raw hashes, and the remote core interface/features inspected differ from the local architecture. Hash differences alone can include line endings; select the canonical release tree and review the functional differences before copying or counting evidence. The remote riscv-dv directory must not silently select a second, older DUT.

## The integration architecture

The environment has two independent stimulus producers. The offline software generator emits legal bounded instruction blocks plus explicit peripheral operations. A simulator-side event sequencer drives off-chip inputs and peripheral responders while the CPU executes those blocks. It records actual events and the state of the environment. Neither producer decides that the DUT passed.

Use a thin Python regression layer around Xcelium, ELF/image generation, and result collection. Keep existing lightweight SystemVerilog BFMs initially. A shared scenario description supplies legal parameters to firmware generation and event generation, with separate program and environment seeds. UVM may organize these components later, but a new full UVM framework is not a prerequisite for this integration.

The same SoC DUT runs in three useful campaigns:

1. **Warm full-SoC execution:** preload both SRAM images with the existing synchronized warm-reset sequence. This is the high-throughput path for random programs and peripheral interaction.
2. **Cold full-SoC boot:** load a matching flash image, release the real bootloader, verify memory image delivery and handoff, then run selected programs. This is separate evidence about boot, not replaced by warm execution.
3. **Fabric and unit environments:** retain core CSR/trap tests, gateway/arbiter tests, peripheral block tests, and fabric BFMs for properties difficult or unreachable in the integrated SoC. Label their configuration explicitly; fabric contention evidence is not generated by pretending the bootloader and CPU always execute simultaneously.

The physical SRAM capacity and bootloader load length are different quantities. The SoC shell currently selects 64 instruction words and zero data words for cold loading; warm preloading can use the SRAM capacity. Cold random-program testing requires a matching boot image and agreed bootloader parameters/image format. Do not claim a large warm program was tested through a 64-word cold image.

## Feasibility levels

Effort estimates below are cumulative focused engineering person-weeks, not promises of elapsed time. They include harness/checker work but exclude repairing substantive DUT defects, license outages, and substantial architecture changes. Six students over four weeks provide at most 24 person-weeks before coursework, review, integration, and learning overhead. Measure actual capacity in week 1.

| Level | Capability | Approximate cumulative effort | Expected position in this project |
|---|---|---|---|
| 1 | Random riscv-dv programs execute on the actual SoC, with direct trap runtime, bounded SRAM accesses, strict completion, and directed peripheral/IRQ cases | 2–4 person-weeks | Required early foundation; feasible in week 1 with focused integration |
| 2 | Concurrent constrained-random pin events, programmed peripheral activity, independent IRQ/device/path scoreboards, meaningful functional coverage and negative checker tests | 6–10 person-weeks | Main committed SoC integration target |
| 3 | Architectural trace checking against a pinned ISS for a declared subset, followed by single-source IRQ replay and selected MMIO response synchronization | 12–20 person-weeks | Ambitious four-week target with six members; stage the claim and restrict it to proven capabilities |
| 4 | Live DPI Spike co-simulation, broader asynchronous synchronization and custom interrupt support, automated reduction, wide coverage-driven stress | 24–40+ person-weeks | Prototype early; complete in extra time only if the foundation and closure data justify it |

These levels describe added infrastructure, not alternate tapeout standards. Compliance, reset/CDC/RDC, selected formal properties, boot, and the independent peripheral/interrupt evidence remain necessary at every level. A lower level cannot be relabelled full Rev B closure.

### Level 1 acceptance

Create a `riscforge_soc` custom target and extension. Override program setup, data placement, trap handling, and completion where needed. Avoid multiplying edits to upstream generator classes. riscv-dv documents custom targets, user extensions, and UVM type overrides as its intended customization mechanism [S1].

Keep the first random programs small, for example 256–1024 body instructions, subject to actual link-map size. Reserve ISRAM for executable code; DSRAM for generated data, constant tables, runtime state, signature/mailbox, and stack. Linker assertions protect each region and enforce explicit stack space. The count is a starting distribution, not a coverage target.

Use bounded branch/subprogram generation and constrain ordinary data accesses to a scratch DSRAM arena. The generator cannot overwrite the mailbox, runtime state, ISR stack, or its own control data. Peripheral MMIO comes from directed semantic streams, not arbitrary random stores to the full MMIO aperture. Negative access-fault tests explicitly opt into forbidden regions.

Random code must respect its integration boundary. Either generate a standalone assembly program with a complete context-saving trap wrapper, or make each generated assembly block obey the C ABI at its boundary. Reserve `sp`, and protect `gp`/`tp` if the compiled runtime depends on them. Do not call an arbitrary random assembly body as though it were a C function.

Acceptance: one command builds and executes the exact full SoC; BootROM handoff is observed; every seed has separate immutable outputs; the TB checks an explicit completion protocol and required activity; one GPIO and one timer interrupt enter a handler and return with register canaries preserved. No claim of independent full instruction correctness is made until Level 3.

### Level 2 acceptance

Extend agents for UART RX/TX, GPIO, I2C responders, SPI responders, and reset. Timers are real DUT devices configured by firmware, with independent timing predictions. Use peripheral pin activity to produce SoC interrupts in the integration campaign. Direct forcing at an internal IRQ boundary is useful for isolated unit tests and qualified diagnostic scenarios, but does not prove the peripheral-to-core route.

Randomize meaningful variables: legal payloads, bounded inter-byte gaps, GPIO pulse widths/phase, timer compares, simultaneous sources, bounded I2C stretching/NACK policy, and reset phase. Keep legal stress and intentional protocol/fault injection in distinct named scenario classes.

Build three independent checks for a transaction-bearing peripheral: software/ISS or predeclared scenario intent; bus/register prediction; external pin/device behavior. UART TX FIFO writes must correspond to the expected output bytes; RX delivery must correspond to what the external agent actually sent. I2C/SPI byte order and transfer counts are checked externally. Model pop-on-read, clear-on-read, W1C, FIFO limits, and IRQ clears explicitly.

The path scoreboard joins expected access, observed LSU request/completion, AXI request/response, APB access/completion, and countable pin effect. Account for protocol stalls without creating duplicate operations. At completion all pending operations must drain or belong to a documented reset/error outcome.

Acceptance: concurrent random program and event seeds are reproducible; every enabled source has observed delivery and clear; priority/masking/threshold and context checks are independent; exactly-once effects are checked across interrupts; each bound critical checker detects a targeted negative case; scenario-specific activity counters prevent empty passes.

### Level 3 acceptance

Start with full-SoC deterministic instruction execution and DSRAM accesses, interrupts disabled, comparing PC, actual instruction, register writes, architectural CSR operations, trap entry/return, and memory intent in architectural order. Do not equate a GPR-change-only comparator with a full retirement checker.

Define an event schema separating successful instruction retirement, synchronous trap, asynchronous trap entry, MRET, and reset. Link events to dynamic instruction identity and memory transactions; a raw request held over several stall cycles is one transaction. A squashed instruction is not a successful retirement. Capture the actual pipeline instruction and commit qualification rather than inventing the executed instruction from an address lookup alone.

Use a pinned Spike build with the real reset/BootROM/SRAM platform. A stock command-line Spike invocation is not a demonstrated complete model of this SoC. Prove low-memory ELF loading, reset entry, access faults, and host termination with a short test before building the wider comparator.

Next add single-pending interrupt replay at the observed architectural acceptance boundary, with `mepc` and cause matched. Preserve original pin stimulus separately. Replay of the DUT's accepted IRQ stream aligns CPU execution but cannot discover a wrong winner or missing request; the independent IRQ model owns those checks. Never assign the ISS the DUT's computed expected register values to make comparison pass.

MMIO needs an explicit model. First compare independently predictable cases. For nondeterministic input data, a checked transaction service may supply the observed read response to the ISS only after verifying address, size, ordering, protocol outcome, and device semantics against the external stimulus/model. This establishes a narrower CPU/path claim; it is not an independent proof of that read data. Keep RAM contents independently maintained. An alternative full peripheral model is more independent but more costly.

Custom causes 16–27, `mintprio`, and the three-class arbiter are not automatically covered by stock Spike. Keep arbitration/threshold checks in the independent platform model; any ISS extension has a pinned patch and its own tests. Expand IRQ differential scope only after proving the adapter supports these custom causes and CSR semantics.

Cycle-sensitive CSRs require an agreed model: `mcycle` cannot generally equal an untimed ISS counter, and live pending state must be sampled at the agreed boundary. Constrain their reads out of the initial differential subset or use explicit event/counter adapters with separate assertions. Record the excluded behavior; do not silently mask comparison fields.

Acceptance: fail on the first real divergence; no prefix-only pass, tail truncation, or resynchronization that skips mismatches; both sides reach the agreed terminal architectural event with identical compared event populations. Include negative tests for wrong PC, missing/extra commit, wrong CSR, duplicated store, and an interrupt boundary shifted by one event. Publish a comparison capability manifest so partial differential coverage is visible.

### Level 4 acceptance

Drive a DPI/C++ ISS interface from qualified architectural events; notify it of interrupts and memory outcomes in defined order. Add live MMIO transaction handling, support for the approved platform-specific CSR/IRQ semantics, and automated replay/minimization. A working interface in another CPU project is a reference design, not a drop-in RISCFORGE adapter.

Ibex's published co-simulation system demonstrates the overall pattern: a specially selected Spike fork, architectural trace interface, ordered memory notifications, and IRQ-state synchronization. It also documents complications when interrupt events occur between retirements and when instruction fetches are speculative [S3]. Plan explicit interface tests before relying on it.

## Trap ISR and vector table strategy

**Direct dispatch is the immediate implementation path.** Point `mtvec` at an assembly entry, save asynchronous architectural context, decode `mcause`, and dispatch to a software ISR table. Place a table of C function pointers in DSRAM so normal data accesses can read it. Cause IDs are sparse; provide guarded entries for cause 7 and causes 16–27 and a deterministic unexpected-cause handler.

The local hardware has no automatic trap shadow stack. Before permitting nesting, software must preserve the required trap CSRs and threshold state as well as registers. Define how `mepc`, `mcause`, `mtval`, `mstatus`/MPIE, `mintprio`, and scratch/stack state are saved and restored. Raise the threshold for the active class, then enable MIE only after the frame is safe. Mask interrupts again before restoring the outer frame. Test the class-0 → class-1 → class-2 chain if it is adopted, with an explicit software depth/stack bound; do not inherit Rev B's old two-deep hardware contract.

The existing caller-saved frame is not automatically sufficient for unconstrained asynchronous random assembly. Choose full integer-context preservation for the first implementation, excluding x0 and handling sp carefully. Optimization comes after canary and nested-context evidence. Synchronous exceptions use a separate policy: expected trap with a known recovery PC, or terminal failure. Advancing every `mepc` by four is not a general ISR or exception solution.

**Hardware vectored mode is a separate architecture decision.** The RISC-V rule is that synchronous exceptions enter BASE and interrupts enter BASE plus four times the cause [S2]. A vector table contains fixed-size instructions, usually jumps, not an array of handler pointers. For the present highest routed cause 27, reserve entries 0–27, including unused holes, with exact four-byte spacing; 32 entries is a convenient optional allocation. Verify linker placement, supported BASE alignment, and absence of compressed/relaxed slot expansion.

Today normal writes cannot select MODE=1. Mentor and core owner should decide by day 2 whether to retain direct mode for this release or implement and verify selectable vectored mode. A direct-only implementation may be a valid architectural choice; the target, requirements, and WARL tests must say that. If vectored mode is chosen, its writable-mode behavior, invalid-mode WARL policy, readback, exception fallback, and every source's vector entry become required checks. The inspected remote rv32im setting uses a vector count of 16; the new SoC target must cover at least entries 0–27 if it uses the upstream vector-table generator. Forcing internal MODE bits in a TB is diagnostic evidence only, not software-selectable vector support.

Do not integrate CLIC as a prerequisite. The deployed interrupt design is the core gateway/arbiter; adding a new controller, register map, and firmware contract during closure would create a separate architecture project.

## Concrete scenario portfolio

| Scenario | CPU and firmware activity | Concurrent environment activity | Required observations |
|---|---|---|---|
| Timer during divide | Random RV32IM blocks, timer ISR | Timer expiry near long-operation phases | Precise `mepc`, approved finish/abort/retry behavior, correct final result, one committed effect |
| UART plus GPIO | RX/TX queue handling and random compute | Independently seeded UART input and GPIO edges | Payload/order, FIFO/overflow policy, no lost pending event, restored context |
| SPI and timer | SPI transaction with ISR service | SPI responder and timer expiry | Expected FIFO effects and pin transfer count exactly once; SPI cause 27 classified as stream in current RTL |
| I2C stretch and NACK | Bounded transfer and recovery | Legal bounded stretch, selected NACK | Protocol timing, correct status/clear, no false timeout under the agreed bound |
| Mask and threshold sweep | Writes `mie`, MIE, and `mintprio` | Pending level source and GPIO edge | Correct gating before/after CSR commit, retained/cleared pending behavior, expected winner |
| Nested context | Background ISR permits higher class | Stream source then timer | CSR/GPR frame preservation and threshold restoration at every return |
| MMIO side effect | FIFO write/pop or interrupt clear | IRQ around request, response, and return | One semantic effect, no duplicated bus transfer, no dropped operation |
| Reset during transfer | Live peripheral/MMIO traffic | Warm/hard reset at named phases | Reset-domain contract, defined abort/drain behavior, no stale replay after restart |
| Cold boot | Matching linked random/directed image | Flash responder | Bootloader image transfer, reset release order, BootROM handoff, final checked execution |

The old Rev B 3-class by 9-pipeline-state cross is a useful starting intent, not a table of current truth. Re-derive conditions from the current pipeline. Target pending arrival, acceptance, trap commit, handler entry, and return separately. Speculative wrong-path instruction fetch is legal; it must not be compared one-for-one to ISS retirements. Instruction-side checks instead establish address/response legality and committed instruction identity.

## Six-person execution plan

These are human ownership lanes; they are not instructions to launch autonomous agents. Pair across interfaces and use AI-generated work only after an owner can explain and review it.

| Owner lane | Main work | Critical interface |
|---|---|---|
| 1 Integration and regression | Canonical RTL/filelists, Xcelium runner, seed/artifact identity, warm/cold setup, immutable manifests | All lanes deliver through one runner |
| 2 Software and generator | Custom riscv-dv target, linker/images, direct ISR/BSP, context/nesting, semantic MMIO streams | Lane 3 trace contract and lanes 4/5 device scenarios |
| 3 Architectural checking | Lossless event stream, pinned ISS platform proof, staged differential comparison and replay | Lane 2 trap semantics and lane 6 comparison tests |
| 4 Timer UART GPIO and IRQ | Agent behavior, payload/timing models, independent pending/priority/threshold model | Lane 2 firmware and lane 6 coverage |
| 5 SPI I2C boot and fabric | External responders, device semantics, end-to-end transaction scoreboard, cold boot cases | Lane 1 loading/reset and lane 3 MMIO adapter |
| 6 Assertions coverage and closure | Coverage/check registry, checker negative tests, prioritized formal, compliance identity, candidate evidence/waivers | Every lane supplies reviewed requirement/check/result links |

### Week 1 establish one trustworthy vertical slice

Days 1–2: freeze a working canonical baseline for evidence collection, reconcile Rev B's architectural deltas, select direct/vectored scope, define the event/IRQ/stack contract, and pin tools. This is a working baseline; substantive DUT fixes can still land with fresh identities and reruns.

By day 5: one generated program runs on the full SoC; GPIO and timer enter/return; a deliberate context or transaction error is detected; artifact replay works; the trace lane compares a short deterministic program at the real reset/map. Each peripheral owner brings one externally checked transaction through the shared runner. Establish actual compile and simulation throughput, license capacity, and defect load.

Decision: if low-address ISS loading or event extraction is blocked, keep Level 2 moving while the architectural lane resolves it. This is a visible gap against section 16, not a reason to label Level 2 as differential signoff.

### Week 2 build independent checks and controlled concurrency

Complete all six APB device-instance smoke paths, raw-to-trap IRQ checks, transaction correlation, and negative checker cases for critical mechanisms. Add pairs of concurrent devices and all three interrupt classes. Bring up deterministic and single-source interrupt differential tests. Time-box the live DPI proof of concept to two focused days; continue it only if real reset, one instruction stream, and one trap case align with preserved diagnostics.

### Week 3 stress defined corners and close coverage holes

Exercise planned class/pipeline crosses, nested software context, reset phase sweeps, clear/reassert races, error-to-trap paths, exactly-once device effects, and representative cold images. Expand ISS scope only with proven support. Use small targeted streams to fill holes; long random campaigns alone are not closure. Review coverage exclusions against current RTL, especially sources that Rev B previously called unreachable.

### Week 4 qualify the candidate and deliver evidence

Reduce new feature work. Reproduce substantive failures, retain negative results, close or explicitly escalate defects, and rerun affected tests on a candidate manifest. Produce per-run G0/G1/G3, candidate G2/G4/G6, and release-input G5 reports at the right scope. Reserve integration/review capacity rather than assigning every person a new feature in the final week.

Extra weeks 5–6, if available: complete justified Level 4 extensions, expand convergence campaigns, and qualify later netlist/macro/physical handoffs when supplied. Do not defer a basic ISR or device checker to these optional weeks.

## Evidence and Rev B alignment

| Rev B obligation | Work in this proposal | Evidence required |
|---|---|---|
| Sections 5–6 environment and anti-vacuity | One canonical DUT, identity manifests, scenario activity, immutable outputs, queue drain | Build/source hashes, event counts, machine-readable verdict, drain record |
| Sections 7–9 stimulus and models | Random SW plus independent event agents and transaction/device models | Original intent, observed transactions/pins, checker results, fault-injection cases |
| Section 10 coverage | Requirement-driven functional bins plus structural and assertion coverage | Declared/hit/excluded/waived bins, current checker viability, reviewed exclusions |
| Sections 11–12 reset and boot | Warm throughput, separate real cold path, reset-in-flight tests | Image identity, transfer/hand-off observations, reset assertions; CDC/RDC results separately |
| Section 13 interrupts | Current 13-source map, actual sensitivity/class/threshold rules, software nesting | Source → pending → winner → accepted trap → ISR clear → return lifecycle evidence |
| Section 14 fabric | End-to-end path scoreboard and isolated contention/timeout tests | Transaction matching, protocol checks, response/fault attribution |
| Section 15 peripherals | Semantic MMIO streams plus pin and register models | Device-specific data/order/timing/clear behavior, all real instances covered |
| Section 16 ISS | Staged full architectural trace plus declared IRQ/MMIO capability | First-divergence reports, exact terminal alignment, replay/patch hashes |
| Sections 17–18 compliance/formal | Same canonical core, applicable suite, focused property closure | Updated applicability denominator, results on candidate identity, proofs/assumptions/waivers |
| Sections 19–21 traceability and release | Owners, check IDs, regressions, frozen manifest and mentor review | Requirement → check → test → result chain and explicit residual risk |

Rev B requires reconciliation, not blind implementation. Its hardware stack, missing timer routes, absence of `mintprio`, tool availability, and current retire infrastructure no longer match the inspected tree. It also contains tensions about simulator of record, ISS configuration validity, speculative fetch checking, and exact CSR tolerance. Propose a dated architecture/verification addendum; the mentor approves changed requirements and exclusions. Do not silently weaken a check to make the plan executable.

For coverage of record, propose Xcelium/IMC because that is the established remote riscv-dv path inspected here; Rev B names VCS. Treat adoption as an explicit decision. Pin one tool's database format for closure, keep other simulator evidence separately attributed, and never merge incompatible databases as though they were one measured population.

Rev B's G1 currently requires positive instruction, AXI, APB, and attestation counts. A pure DSRAM/ISA development test cannot satisfy that predicate merely by retiring instructions. Keep such tests explicitly developmental, add a separately checked completion/activity phase where appropriate, or obtain an approved partition-specific amendment. Do not silently drop the AXI/APB operands for convenience.

Use Rev B's seed-convergence intent rather than an impressive fixed total: start with its proposed nightly floor of 20 seeds where affordable, then measure unique-bin growth and repeated hits across partitions. The H=2, K=3 assumptions remain proposed plan parameters subject to review. Preserve a stable regression seed corpus across RTL revisions plus fresh exploration seeds. Coverage convergence is supporting evidence; it does not replace required directed cases or a missing checker.

The run identity should include RTL/filelist and tool identities, generator revision plus patch/extension hashes, firmware sources/linker/toolchain, ELF and memory/flash image hashes, program seed, environment seed, realized event schedule, plusargs, scenario ID, ISS build/patch hash, replay hash, and result/artifact locator. Store a complete trace separately from bounded debug history. Expected diagnostic ring wrap and loss of a required evidence event are different policies; define and test both rather than claiming a bounded history is a lossless archive.

## Decisions for the first mentor review

1. Which exact RTL tree is the candidate, and which verification/compliance copies must be retired or regenerated from it?
2. Is this release direct-only or software-selectable hardware vectored? Is the software-managed nesting and `mintprio` contract approved?
3. Which privileged ISA version and custom CSR/IRQ semantics define the oracle, and which cycle-dependent fields need adapters or separate checks?
4. Will Xcelium/IMC replace the Rev B VCS tool-of-record statement for this campaign?
5. Is Level 2 plus the declared Level 3 subset the four-week commitment, with remaining section 16 requirements explicitly tracked?
6. What are the release-blocking severity rules, and who can approve residual risk, exclusions, and requirement changes?

The first implementation deliverable should be a reviewed vertical slice: one bounded generated program, real SoC execution, one pin-originated interrupt, safe direct ISR return, one independently checked peripheral effect, a qualified event trace, and reproducible artifacts. Once this works, the six lanes can expand without building six incompatible environments.

## Scope of a verification closure claim

Software can exercise and reveal hardware behavior; it does not independently validate itself. A firmware PASS requests completion, while independent checkers and evidence gates decide the run. Known DUT failures may be outside this planning inspection, as requested, but unresolved release-blocking failures cannot be ignored when signing a candidate.

This campaign can establish functional verification closure against an agreed specification. It cannot establish physical tapeout readiness while PDK/library access and implementation evidence are missing. Later handoffs still need the project's agreed synthesis/equivalence, STA and constraints, CDC/RDC, DFT/test, SRAM macro-model qualification, relevant GLS/reset/X behavior, physical verification, and foundry/mentor signoff. The current PDK block is useful time for functional closure and interface preparation; it does not make those later requirements disappear.

## Primary external references

- [S1 riscv-dv customization documentation](https://github.com/chipsalliance/riscv-dv/blob/master/docs/build/singlehtml/index.html) — custom target, user extension, and type override mechanisms. Resolve exact hooks against the pinned local checkout; the inspected `riscv_asm_program_gen.sv` contains virtual program, data, trap, interrupt, and vector-table generation functions.
- [S2 RISC-V machine-level specification](https://docs.riscv.org/reference/isa/priv/machine.html) — standard direct/vectored trap behavior. The release must pin its adopted version rather than silently following the latest web edition.
- [S3 Ibex co-simulation documentation](https://ibex-core.readthedocs.io/en/stable/03_reference/cosim.html) — architectural trace, IRQ synchronization, DPI, and memory-error integration precedent. Used as an engineering reference; it is not evidence of RISCFORGE support.

## Inspection anchors

- `ips/RISCFORGE_Verification_Plan_RevB.docx`: sections 5–10, 11–18, 19–21.
- `ips/RTL_SOC/riscforge_soc_subsystem.sv`: core reset/interrupt wiring near lines 1239–1290; cold image parameters near 240–243.
- `ips/riscv_core/rtl/top.v`: gateway near 207–220, threshold arbiter near 231–242, pending CSR mapping near 548–585.
- `ips/riscv_core/rtl/irq_arbiter.v`: class/priority map and software threshold gating.
- `ips/riscv_core/rtl/csr_regfile.v`: `mintprio` software contract near 80; trap and MRET handling near 157–190; MTVEC write mask near 188.
- `ips/riscv_core/rtl/wb_trap_mret_commit_controller.v`: commit qualification and vector target resolution.
- `ips/Verification/infrastructure/tb/soc_tb_top.sv`: monitor binding near 207–230, predictor near 435, synchronized warm/cold loading near 595–650.
- `ips/Verification/infrastructure/monitors/retire_monitor.sv`: bounded event history and retirement/trap qualification.
- `ips/Verification/infrastructure/checkers/irq_predictor.sv`: old class/stack model.
- `ips/Verification/infrastructure/checkers/mmio_path_scoreboard.sv`: implemented slot-decoding check.
- `ips/Verification/firmware/bsp/trap_entry.S` and `link.ld`: existing runtime and split-memory linker.
- Remote `/home/iiita/riscv-dv/Makefile`, `src/riscv_asm_program_gen.sv`, `target/rv32im`, and `soc_verification/ips`: inspected through `Invoke-CadenceCommand`.
