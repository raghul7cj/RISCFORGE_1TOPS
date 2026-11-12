# Hazard unit and pipeline verification gate

**Status:** open development campaign with one open core finding. Not sign-off.

**Baseline:** core RTL `raghul7cj/RISCFORGE_1TOPS verification_infra` at
`d1ec0de4712af37e5bb344697d8d2dd45e255e02`, verified byte-identical for the six cited
core files through the GitHub contents API on 11 November 2026. Bench and script files are
local to this workspace and not yet upstreamed.

**Review date:** 11 November 2026.

**What this document is.** A single entry point for the hazard-unit and pipeline benches:
what they check, the evidence a bounded campaign produced, and one core defect the campaign
found. Every design statement cites a file and line. Every evidence statement names the run
it came from. Contract, as-coded behavior, independent expectation and observed evidence stay
separate, and nothing here is promoted to a gate closure.

**What this document is not.** It is not a technical sign-off, a coverage closure, or a
claim that the interrupt/MDU policy is decided.

---

## 1. Executive summary

Two new benches drive the production core. The unit bench drives the combinational hazard unit
with generated vectors and compares every output against a reference model written from the
documented rules. The pipeline bench runs the production core with the real multiplier/divider,
an instruction-memory model and a data-memory model with configurable wait cycles, and checks
retirement order, retired values, CSR effects and memory effects against an independent
interpreter.

The campaign of 11 November 2026 ran 32 times. Fifteen runs passed, none failed unexpectedly,
and two runs are registered open findings of one defect.

| Item | Result |
|---|---|
| Campaign runs | 32 (3 unit seeds, 14 pipeline runs, 15 negative controls) |
| Unit vectors | 2 661 over 3 seeds, 0 checker errors |
| Unit candidate bins | 342 checked of 366, 24 characterized, 0 unattempted |
| Pipeline runs | 14 from 7 reference programs, 2 memory-wait variants where relevant |
| Negative controls | 15 of 15 rejected as expected |
| Open findings | HZ-F001, 2 runs, tracked upstream as issue #30 |
| Simulator | Verilator 5.054, development only |
| Sign-off | none; no VCS run, no code coverage database |

A run that reports no error still has to reach the completion checkpoint. A run whose log does
not carry the evidence signature of a registered finding is reported as an unexpected failure.
The campaign exits nonzero while a finding is open, and it never converts a finding into a pass.

---

## 2. The unit and the pipeline under test

The hazard unit is combinational. It produces two forwarding selects and the stall and flush
strobes for each pipeline register. Its flush outputs are where this gate found a defect: the
flush that should remove a trap-squashed instruction does not reach the two pipeline transfers
that carry that instruction forward.

| Signal | As implemented | Where it is consumed | State |
|---|---|---|---|
| `FlushD` | `PCSrcE \| exc_inflight_E \| exc_inflight_M \| wb_redirect \| flush_pipeline_onehot[0]` | `fetch_cycle.v:252`, clears `valid_D_reg` only | exists |
| `FlushE` | `(lwstall \| csr_gpr_stall \| csr_stall) & ~mem_stall_i \| PCSrcE \| exc_inflight_M \| wb_redirect \| onehot[1] \| stallMUL` | `decode_cycle.v:276`, clears the whole ID/EX register. `execute_cycle.v:101` declares the input and never references it | exists |
| `FlushM` | `wb_redirect \| flush_pipeline_onehot[2] \| (stallMUL & ~mem_stall_i)` | `execute_cycle.v:411`, clears the EX/MEM registers | exists |
| `FlushW` | `wb_redirect \| flush_pipeline_onehot[3]` | `memory_cycle.v:240`, clears the MEM/WB registers | exists |
| `instr_retired_W` | `valid_W & ~exc_valid_W & (mret_commit \| (~mem_stall_out & ~FlushW))` | `top.v:299`, feeds `minstret` and, since this work, the pipeline probe | exists |

Citations are relative to `ips/` (`riscv_core/rtl/...`, `Verification/hazard_tb/...`).

### Why the retirement token is read from the core

A memory wait holds the MEM/WB packet, so an expression derived from `valid_W` alone reports a
new retirement on every cycle of the wait. The pipeline probe therefore reads the core's own
retirement token, and the checker keeps an independent repeated-retirement guard. The
historical probe expression is retained as a negative control and must be rejected. This was a
testbench contract error: the old expression re-created the bug that upstream issue #16 fixed
in the RTL. No RTL was changed to obtain a pass.

---

## 3. The verification suite

![Check architecture of the two benches](figures/fig_5_2_bench_check_architecture.svg)

**Figure 5.2 — Check architecture.** The scenario drives the control interface of the core, the
boundary observer samples the interface before the rising edge and one picosecond after the
non-blocking updates, the interpreter produces the expectation from the program image, the
checker compares and the campaign classifies the outcome. The negative-control lane runs beside
the main flow: every injected fault must be rejected. The expectation is computed independently
of the RTL; it does not repeat the RTL equations. The figure does not show the interrupt and MDU
policy, which stays characterized rather than checked.

### Programs and what each one exercises

| Program | Runs | What it exercises | Outcome |
|---|---|---|---|
| `forward_load_store` | 6 waits: 0, 1, 2, 5, 17, 32 | load-use, store-to-load forwarding, a held WB packet | pass, 6 of 6 |
| `redirect_link` | 1 | branch and jump redirect, link value | pass |
| `csr_dependencies` | 1 | CSR read-after-write, CSR result to GPR | pass |
| `mdu_transport` | 1 | divide and multiply result transport | pass |
| `memory_mdu` | 2 waits: 0, 5 | memory access and MDU result in one program | pass, 2 of 2 |
| `trap_no_ghost_store` | 2 waits: 0, 5 | ECALL with a store immediately after it | **open finding HZ-F001** |
| `irq_characterize` | 1 | timer interrupt arriving while the MDU is busy | characterization only |

Each run checks the retirement order and payload against the reference, the operand values of
the executed instructions, the CSR write order and value, and the memory effects. The scenario
must also reach its completion checkpoint; the environment fails the run if a user hook does not
report completion, so a quiet log is not treated as a pass.

### Negative controls

A checker that cannot fail proves nothing. Fifteen runs inject a fault and must be rejected:
twelve mutate one output bit of the hazard unit, one restore the historical retirement probe, one
inject a checker observation and one corrupt a retired value. All fifteen were rejected as
expected. The unit controls are 15 of the 44 self-proof candidates; the rest are not built.

### Interrupt during a busy MDU: characterized, policy open

The interrupt case is characterization, not a checked requirement, because the expected policy is
not decided. Measured behavior: the MDU holds the pipeline for 34 cycles with the EX stage empty,
the interrupt request stays pending, and it is accepted in EX only after the MDU releases. The RTL
carries an abort path, `div_abort_internal = wb_redirect_i | (irq_accept_E & stallMUL)` at
`execute_cycle.v:299`, but `irq_accept_E` requires `valid_E` and a busy MDU leaves EX empty, so
that term is not reachable in this configuration. The run reports `irq_accepted_while_busy=0`
and `abort_while_busy=0` and stays open. Upstream issue #26 asks for the same defer-versus-abort
decision.

---

## 4. Open defect HZ-F001: a squashed store reaches memory

**Contract.** An instruction squashed by a trap must have no architectural side effect. Data
memory is architectural state.

**As coded.** A store younger than a taken ECALL is offered to the memory interface although the
instruction never retires. At a memory wait of zero, the write becomes visible in data memory.

![How a squashed store reaches the data memory](figures/fig_5_1_squashed_store_reaches_memory.svg)

**Figure 5.1 — The path of the squashed store.** Solid arrows are connections that exist in the
source. Dashed arrows and dashed boxes are the two gates that do not exist at this commit.
Rendered from the saved, validated spec
[`Verification/hazard_tb/docs/diagrams/hz_f001_ghost_store.spec.json`](../../../Verification/hazard_tb/docs/diagrams/hz_f001_ghost_store.spec.json)
with zero rejected elements. The figure does not show the data-memory model, the interrupt path,
or any other trap source.

### Mechanism

The ECALL exception is generated in decode (`decode_cycle.v:418`,
`new_exc_valid_D = valid_D && (illegal_instr || is_ecall || is_ebreak)`) and is carried through
EX and MEM; the trap commits in WB (`wb_trap_mret_commit_controller.v:64`,
`trap_commit = valid_W & exc_valid_W`). Two transfers are not gated by the flush that should
remove the younger instruction:

1. `FlushD` is applied in the fetch stage only. `decode_cycle.v` has no `FlushD` input and latches
   `valid_E_r <= valid_D;` at line 367 in its normal branch, so the store in D advances into EX.
2. `FlushE` clears the whole ID/EX register at `decode_cycle.v:276`, but `execute_cycle.v` latches
   `valid_M_r <= valid_E1;` at line 467 in its normal branch. The EX/MEM transfer is gated by
   `FlushM` and `StallM` only, so the store reaches MEM and issues its request.

The store is never retired: the reference retirement sequence contains no `0x8000_001c`, and the
trap's `FlushW` clears the MEM/WB packet. The trap itself is correct; retirement order, retired
values, trap cause and handler resume all match the reference for all 14 instructions.

### Cycle trace

| Cycle | Observation |
|---|---|
| 13 | ECALL in EX, `exc_valid_E` set, `FlushD` asserted, reaching only the fetch stage |
| 14 | the younger store is in EX, `FlushE` asserted, and the store is latched into MEM |
| 15 | the store is offered to the memory interface; the trap commits in WB in the same cycle |

### Reproducer and evidence

`python ips/Verification/hazard_tb/scripts/run_campaign.py <out> --verilator <path> --only pipeline`

At `MEM_WAIT=0` the write is visible:

```
[LSU_OFFER] id=0 addr=80001040 we=1 be=1111 wdata=0000004d wait=0
[LSU_EFFECT] id=0 store addr=80001040 be=1111 wdata=0000004d
[GHOST_STORE] pc=8000001c we=1 addr=80001040 value=0000004d cycle=15
[PIPELINE_MISMATCH] cycle=15 ghost store offer from a squashed instruction pc=8000001c
[PIPELINE_CHECKS] retire=14/14 operands=14 memory=2/1 effects=2 ghosts=1 errors=3
```

At `MEM_WAIT=5` the core still offers the store and the model withdraws it before the response:

```
[LSU_OFFER] id=0 addr=80001040 we=1 be=1111 wdata=0000004d wait=5
[GHOST_STORE] pc=8000001c we=1 addr=80001040 value=0000004d cycle=15
[LSU_CANCEL_DROP] id=0 addr=80001040 before response; no store effect
[PIPELINE_CHECKS] retire=14/14 operands=14 memory=1/1 effects=1 ghosts=1 errors=1
```

The check is made on the offer at the core boundary, not on the completed effect, so the finding
does not depend on the timing model.

### Scope, and what the fix must not break

- The vulnerable window is a store that is in MEM in the cycle the trap commits in WB. A store
  still in EX at that moment is already killed by `FlushM`.
- Traps detected inside `memory_cycle.v`, such as a misaligned access, are raised there and are
  not visible to the hazard unit's `exc_inflight_M`. They are not covered by the flushes above
  and need a separate gate. This path was read but not reproduced.
- Gating the EX/MEM transfer on `FlushE` is unsafe: `FlushE` is also asserted by the load-use and
  CSR stalls, by `PCSrcE` and by `stallMUL`, so clearing EX/MEM on it would drop the load of a
  load-use stall, the link write of a taken branch, CSR results and the MDU instruction.
- A trap-specific squash signal, plus a MEM-side gate on the request, is the direction the
  upstream issue records.

### Disposition

Open. Tracked upstream as
[issue #30](https://github.com/raghul7cj/RISCFORGE_1TOPS/issues/30) in
`raghul7cj/RISCFORGE_1TOPS`, label `bug`, with a correction comment recording an independent
review. The review confirmed the defect and corrected several statements in the first version of
the issue: the exception is generated in D rather than detected in EX; `FlushE` clears the whole
ID/EX register; the two detections are checks in one checker, not independent sources; the write
is suppressed by the memory model at a non-zero wait while the core still offers the request; and
raw `FlushE` is not a safe gate. The issue body and its addendum hold the corrected record. No
RTL was changed.

---

## 5. Coverage accounting

Coverage is reported per candidate group against the inventories in
[`artifacts/hazard_verification_plan_20261104/Hazard_Verification_Plan.md`](../../../../artifacts/hazard_verification_plan_20261104/Hazard_Verification_Plan.md).
That plan retires an earlier merged headline and forbids merging the groups into one number, so no
merged percentage is given. No code or structural coverage is collected anywhere; the unit number
is checked named functional-witness coverage.

| Group | Candidates | Closed | Result |
|---|---|---|---|
| Unit behavioural bins | 366 | 342 checked | 93.44 percent checked, 24 characterized and not closed, 0 unattempted |
| Pipeline candidate bins | 947 | 0 | no named-bin manifest exists yet, so no percentage is claimed |
| Named crosses | 61 | 0 | not implemented as bins |
| Self-proof controls | 44 | 15 executed | 34.09 percent, all 15 rejected as expected |

The 24 open unit bins are policy dependent: sixteen hazard-by-consumer crosses of load, CSR
address, CSR result and none against E-exception, M-exception, branch and none, and eight
reset-cause bins.

The pipeline side has no named-bin manifest, so its denominator cannot be reduced. What it does
measure is behavioural reach, which is not closure: 1 007 pre-edge samples over 14 runs, 24 distinct
hazard control states, 8 of 9 forwarding route pairs (the pair in which both operands come from WB
is never observed), 373 memory-wait edges, 149 MDU-busy edges, 6 redirect edges, 3 trap edges and
1 interrupt-accept edge. The trap, redirect and interrupt space is barely exercised, which is where
the one open defect sits.

---

## 6. Simulation flow, sign-off matrix and limits

The campaign builds both benches, generates the reference programs and vectors, runs every case,
and keeps the command, log, observation stream and classification of each run.

```sh
py -3.12 ips\Verification\hazard_tb\scripts\run_campaign.py artifacts\hazard_execution_20261111_08\oop \
  --verilator /home/raghul7cj/.local/share/riscforge-tools/verilator-5.054/bin/verilator --only all
```

The simulator is invoked through WSL on Windows. The campaign writes `results_all.json`,
`findings_open.json`, `coverage_accounting.json` and a SHA-256 manifest of every bench and core
source file, and it exits nonzero while an open finding remains. The evidence is copied into
[`Verification/hazard_tb/evidence/`](../../../Verification/hazard_tb/evidence/).

| Claim | State | Boundary of the claim |
|---|---|---|
| Hazard-unit forwarding and stall decisions match the documented rules | exists | 342 of 366 named bins on 3 seeds; 24 bins depend on an undecided policy |
| The core retires each instruction once and in order | exists | 14 bounded runs; the probe reads the core retirement token |
| Memory effects match the reference program | exists | only where the run completes; the trap case fails and is registered |
| A store squashed by a trap has no side effect | open | reproduced failure, issue #30; no RTL change made |
| Interrupt policy while the MDU is busy | specified | characterized as deferral; not a check, policy undecided |
| Pipeline candidate-bin closure | open | no named-bin manifest, 0 of 947 closed |
| Sign-off qualification | open | development simulator, no VCS run, no coverage database |

### Limits

The campaign runs on a development simulator. It does not claim sign-off, does not close the
proposed pipeline candidate matrix, and does not close the interrupt and MDU policy item. The
pipeline bench observes the core through a hierarchy probe; it does not prove the behaviour of a
specific bus protocol or of a memory that commits on write-enable. The defect was found by this
bench and not fixed; the RTL at the cited source identity is unchanged. The bench files are local
to this workspace and are not part of the upstream repository, so the reproducer is not yet
runnable from a fresh clone.

### Next actions

1. Decide and record the interrupt/MDU policy (deferral versus abort/restart), then promote
   `irq_characterize` from characterization to a checked requirement. Owner: core architecture.
2. Reproduce the MEM-detected trap path (misaligned or access fault) to test whether it also
   bypasses the flush, which decides whether the issue #30 fix direction is complete.
3. Fix HZ-F001 with a trap-specific squash signal and a MEM-side request gate, then rerun the
   campaign to close the finding without weakening any check.
4. Define the named pipeline bin manifest so the 947-candidate inventory becomes a closable
   denominator.
5. Extend the pipeline programs into the trap, redirect and interrupt space, which is where the
   observed control-state coverage is thinnest.

### Learning checkpoint

Before the fix, predict what the checker reports at `MEM_WAIT=5` if the EX/MEM transfer is gated
on a trap-specific signal. The offer should disappear, `ghosts` should fall to zero, and
`effects` should fall from 2 to 1, because the checkpoint write at `0x8000_13fc` is the only
remaining memory effect. If the offer still appears, the D-to-E transfer is also carrying the
store, and the second gate is needed as well. That distinction is exactly what separates a
complete fix from a partial one.