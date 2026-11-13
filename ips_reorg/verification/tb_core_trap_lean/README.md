# Core trap lean verification

F3 status: four directed IRQ cases pass; external/software service and requested
MEIP > MTIP > MSIP arbitration fail. F3 is not signed off. See [F3 findings](F3_FINDINGS.md)
and [source-identified matrix](F3_MATRIX.json). No RTL changes or requirement waivers.


| Location | Common or local | Ownership |
|---|---|---|
| Verification/lib/memory/ | Common | Canonical SRAM responders |
| Verification/lib/core/core_events_pkg.sv | Common | Typed architectural effects |
| Verification/lib/core/core_scoreboard_pkg.sv | Common | Event queues, comparisons, accounting and completion validation |
| Verification/lib/core/rv32/rv32_reference_pkg.sv | Common to RV32 benches | Semantic instruction step, encoders and reference memory |
| Verification/lib/core/rv32/rv32_machine_reference_pkg.sv | Common scoped M-mode library | Scoped CSR, synchronous trap and IRQ/MRET prediction |
| Verification/lib/core/sva/core_sync_trap_sva.sv | Common smoke checks | Shared cause/mtval/PC/state and MRET edge assertions |
| Verification/lib/core/trap_functional_cov.sv | Common | Actual trap cause/mode and MIE/MPIE transition coverage |
| Verification/lib/core/sva/core_irq_mask_sva.sv | Common | Masking, pending visibility, enabled acceptance and bounded service |
| f3_scenario.svh, programs/core_trap_programs.svh | Local | IRQ phases, independent frontier snapshots and shared handler/image construction |
| tb_core_trap_lean.sv | Local | Programs, independent run-ahead orchestration, clock/reset, memory instances, sampling and completion policy |
| core_trap_observe.sv | Local to this DUT integration | All read-only hierarchy taps |
| .f, core-trap-f0*.json, run_f0.ps1 | Local | Compilation, variants and remote execution |
| CONTRACT/ARCHITECTURE/TESTPLAN/RESULTS.md, docs/diagrams/ | Local evidence | Contract, scope, validated diagram and retained results |

Expected results come from instruction semantics executed using an independent
PC and architectural state. They are not per-PC data lookup tables and are not
computed from observed DUT operands/results. Run-ahead ends at the configured
program's terminal self-loop or fails a step bound. Programs must initialize
registers they read, except x0.

The common scoreboard initially seals predictions before reset release. F3 uses a
checked reference-prefix revision at IRQ commitment, described below. Retirement PCs,
physical GPR write attempts and accepted stores are compared independently. Decode
checks PC/instruction image consistency and allows speculative wrong-path decode;
it is not treated as retirement. Final SRAM comparison checks every configured word
against reference memory, including legal overwrites and untouched zeros.

Use run_f0.ps1 for the default VLSI Xcelium/IMC run. Offset, second and JAL variants
use the corresponding manifest. Negative manifests are deliberate failing checker
self-tests, not passing regressions: BAD_GPR corrupts the expected copy, BAD_STORE
corrupts a sampled event copy, MISSING_STORE skips one delivered event and EXTRA_STORE
delivers one event twice. No hook changes DUT state or SRAM behavior.

See RESULTS.md for exact runs and source identities. F1 minimal ECALL/MRET smoke passes; general squash acceptance is open on F1-EXC-01. F0.2 now connects common stage and pipeline SVA; F02_CONTRACT.md lists active and
unactivated obligations. Clean F0.2 acceptance is open on F02-WB-01.

## F0.2 use-case runners

Use `pwsh -NoProfile -File Verification/tb_core_trap_lean/run_f02.ps1 -Case wait`
for lightweight iteration. Add -Final for waveforms and detailed IMC/HTML artifacts.
Cases zero, wait-one and wait cover zero/one/three wait edges. Case wb-wait is the
preserved ordinary-program failure; negative-hold and negative-flush are intentional
monitor-only assertion self-tests. -NoThrow returns a failed result without hiding it.

See F02_CONTRACT.md for reusable versus local ownership, F02_MATRIX.json for tested
source hashes, and F02_FINDINGS.md for the open physical-write contract decision.

## F1 use-case runner

`pwsh -NoProfile -File Verification/tb_core_trap_lean/run_f1.ps1 -Final`
executes the minimal software ECALL/handler/MRET smoke and retrieves full artifacts.
Omit -Final for iteration. Case offset relocates reset and handler; adjacent-store
is the preserved real exception-squash failure. Negative-mepc and negative-return
are intentionally failing oracle self-tests. Add -NoThrow to collect a failed result
without an exception; its verdict remains failed. See F1_CONTRACT.md, F1_FINDINGS.md
and F1_MATRIX.json for the exact supported scope and evidence.

## F2 synchronous exception runner

`pwsh -NoProfile -File Verification/tb_core_trap_lean/run_f2.ps1 -Case all -Final`
runs illegal, ebreak, load and store in separate self-contained runs. All four pass
in F2_MATRIX.json. Omit -Final for iteration; use -Case to select one scenario.
The shared handler records mtval at data offset +24, advances mepc by four and
returns via MRET. The negative-mtval oracle self-test intentionally fails.

The former ECALL-only assertion component was generalized and renamed to
core_sync_trap_sva.sv; there are no per-case copies of its assertions. Coverage is
in Verification/lib/core/trap_functional_cov.sv, instantiated through the common
read-only interface. Reports are per-run; direct mode is hit, vectored is unhit.
See F2_CONTRACT.md and F2_MATRIX.json. F1-EXC-01 remains open and is not waived by
these RF-first directed fixtures. No issue or RTL change is part of this milestone.

## F3 asynchronous interrupt runner and ownership

```powershell
& ./Verification/tb_core_trap_lean/run_f3.ps1 -Case all -NoThrow
& ./Verification/tb_core_trap_lean/run_f3.ps1 -Case timer -Final
```

`all` executes timer, timer-late, fast0, fast6, external, software and priority.
The first four pass; the last three retain real requested-policy failures.
`negative-mepc` is a separate intentional oracle self-test and is excluded from all.
`-NoThrow` continues collection without changing failed verdicts. Use compact
iteration by default and `-Final` for selected detailed coverage/waveform evidence.

The common scoreboard compares each ordinary retirement against the image-derived
expected PC. Its next expected PC supplies asynchronous mepc. Local snapshots retain
independently predicted GPR/CSR state and expected effect counts. At trap commitment,
`revise_unconsumed` first validates the already observed prefix and replaces only
future expectations with the handler and replayed application. No DUT execution PC
or trap packet supplies the oracle; no observed store/GPR effect is discarded.
IRQ handlers preserve mepc for MRET; synchronous handlers increment it by four.

The current fixture supports one IRQ before application stores, with early masked
and late enabled timer variants. It does not establish nesting, multiple-source
ordered draining, wait overlap, CDC behavior or SoC ISR integration. Vectored mode
remains unhit under the current direct-only CSR contract. See [F3 contract](F3_CONTRACT.md),
[F3 matrix](F3_MATRIX.json), [test plan](TESTPLAN.md) and [architecture](ARCHITECTURE.md).

Primary agent owns code and decisions. A reusable GPT-6 Luna execution delegate
handles authorized SSH runs, collection and concise diagnostics; it does not change
DUT behavior, verification expectations or failure classifications.
