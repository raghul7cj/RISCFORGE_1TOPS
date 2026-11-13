# Staged test plan

Status: F0 implemented and passing the recorded reset/known-stream campaign. F1 minimal smoke is implemented and passes, with a real adjacent-store squash failure; F2 directed synchronous cases pass; F3 has four passing IRQ cases and three real requested-policy failures; vector/nesting remain open. Diagram: [current architecture](docs/diagrams/core_trap_architecture.md).

| Stage | Stimulus | Current status / required verdict |
|---|---|---|
| F0.1 | Semantic predictor, reset offset, distinct dependent program with two stores, checker-negative | Complete for bounded scope; see exact run IDs in RESULTS.md |
| F0.2 | Directed holds, flushes, bounded DMEM waits and protocol SVA | Implemented; positive isolation fixtures pass; clean acceptance OPEN on F02-WB-01 |
| F1 | ECALL, direct handler, mepc+=4, mret | Minimal and relocated smoke PASS; exact PC/status assertions and signatures checked |
| F1 squash | Younger GPR/store effects around ECALL and MRET | RF-first smoke passes; immediately adjacent store FAILS on F1-EXC-01 |
| F2 | Illegal instruction, EBREAK, misaligned word LW/SW | Four cases PASS with cause/mtval, software skip/MRET and functional coverage; LSU bus faults remain unbuilt |
| F3 | Timer, late timer, fast0, fast6; masking, pending, frontier PC, MRET | Four directed cases PASS; one IRQ/session before application stores |
| F3 policy | MEIP/MSIP service; simultaneous MEIP > MTIP > MSIP | Three real FAIL cases; approved expectation retained; F3-IRQ-01 / F3-ARB-01 |
| F3 boundary | All fast sources, threshold/fairness, nested preemption and multi-source drain | Not closed; upper fast [15:12] unrouted; ext/sw failures preserved above |
| F4 | Direct/vectored IRQ, MODE=1 synchronous exception, return | Not built |
| F5 | DMEM waits, trap/branch overlap, multi-cycle abort, nested handlers | Not built |

F0's evidence is an executable independent stream/effect checker and retained positive Xcelium runs. The checker is intentionally limited to the encoded F0 subset. F0.1 originally had one concurrent alignment assertion and two covers; F0.2 now uses common pipeline/stage SVA. See F02_CONTRACT.md for activation limits. The pass marker additionally requires nonzero fetch and accepted-store cover counters, all semantically predicted retirement/GPR/store events and the final reference-memory state. A reviewed revision adds an expected-failure GPR expectation corruption and a nonzero reset-offset positive test; see RESULTS.md.

The run enables code coverage across the complete instantiated core. Coverage is evidence of exercised RTL only, not closure. It reports low whole-core coverage because F0 is a short straight-line program. Xcelium expression coverage scores logical operators in conditional expressions by default; report warnings also identify unsupported toggle objects. No exclusions were applied. In the historical F0 campaign, functional cover properties were included but no separate functional coverage report was generated. F2/F3 now instantiate the dedicated hardware-qualified monitor.

F1 timing and independent trap/effect prediction are implemented for the minimal smoke. Preserve F1-EXC-01 and F02-WB-01; further trap cases must not adjust expectations to obtain a pass.




F0.2 evidence is tracked independently in F02_MATRIX.json. Required reset/hold
witnesses at all four stages and D/E flush, request wait/release and branch redirect
are enforced for the wait-isolation fixture. The unmodified ordinary F0 stream under
waits remains a real failing regression. M/W flush, WB redirect and all trap/IRQ
behavior previously needed F1 stimulus. Minimal F1 now activates M/W flush and WB redirect; F3 now exercises IRQ entry/return; vector and additional fault paths remain pending.

F2 uses run_f2.ps1 and F2_MATRIX.json. Required per-case witnesses include actual
trap cause/direct mode and, for misaligned accesses, no faulting memory request.
Hardware observations across the same-source positive F1/F2 runs hit causes
2/3/4/6/11; this is not a merged IMC percentage. Vectored mode and its crosses
remain unhit. No claim is made for bus faults, halfword misalignment or all illegal
encodings. The mtval oracle negative verifies that a wrong expected fault value fails.

## F3 acceptance and remaining obligations

The user explicitly retained MEIP > MTIP > MSIP as the requirement. Custom timer-first
routing is observed implementation, not an approved replacement expectation.
External/software each pass masked mip visibility, then fail enabled service. The
simultaneous case fails cause selection. These are not checker-negative tests.

Passing early cases require eight masked witnesses, a trap within the six-sample
service bound after the fixture's enable/source-ready event, exact image-derived
next-unretired mepc, handler/state assertions, one MRET and complete ordered effects.
Late timer requires a distinct frontier. Final signatures 24/25 detect skipped or
repeated application increments. The independent mepc mutation must fail separately.

[F3_MATRIX.json](F3_MATRIX.json) identifies 13 same-input runs including five passing
F1/F2 regressions and the intentional negative. Current bins include synchronous
causes, timer/external/software, fast 16..27, direct/vectored modes and MIE/MPIE
transitions. Per-run metrics are not a merged closure claim. Unhit bins remain visible.

F3 closure requires fixing the requested routing/order contract under an approved
RTL change, replaying these failures and regressions, and additional ordering/drain
checks before claiming the full three-source arbitration policy. Nested ISR
preemption, wait/multicycle overlap and SoC event loops remain later work. Preserve
F1-EXC-01 and F02-WB-01 independently of IRQ successes.
