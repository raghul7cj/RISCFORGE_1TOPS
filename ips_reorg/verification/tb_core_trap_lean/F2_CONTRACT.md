# F2 synchronous exception contract

Scope: directed illegal instruction, EBREAK, misaligned LW and misaligned SW,
followed by software handler recovery through MRET. No RTL change or resolution of
F1-EXC-01 is implied. Diagram: [current architecture](docs/diagrams/core_trap_architecture.md).

## Independent expectations and program

| Case | Faulting instruction | Expected mcause | Expected mtval |
|---|---|---|---|
| illegal | 0xffffffff, unsupported opcode | 2 | The faulting instruction bits, 0xffffffff |
| ebreak | 0x00100073 | 3 | Fault PC, per this core's breakpoint contract |
| load | LW x15,2(x1), x1=DBASE | 4 | DBASE+2, default 0x80001002 |
| store | SW x10,2(x1), x1=DBASE | 6 | DBASE+2, default 0x80001002 |

Each case starts at RESET_PC. Fault PC is RESET_PC+0x1c; direct handler entry is
RESET_PC+0x100; software advances mepc by 4 and returns to RESET_PC+0x20. Expected
PC, cause, address and status come from independent execution of the instruction
image, not DUT fault signals. The memory effective address uses modeled GPR state
and independently decoded instruction immediates. MISALIGN_OFFSET is a fixture
parameter; the current matrix exercises offset 2 only.

The one shared handler reads mepc, mcause, mstatus and (for F2) mtval. It writes
evidence to DMEM offsets 8,12,16,24, increments mepc by four, writes it through a CSR
instruction and executes MRET. The application then writes offsets 0/4 and completes
the predicted instruction stream. Handler fall-through poison at offset 20 must
remain zero. In the illegal case this explicitly proves the illegal instruction
is skipped rather than repeatedly trapped. Other cases also use skip-and-resume.

No faulting instruction retires or emits a GPR/store effect in the independent
expected stream. Misaligned LW has no aligned-load reference semantics hidden in
the model: only its fault path is supported. Unknown/unsupported encodings fail
rather than being silently treated as illegal. Only the explicit illegal marker
is modeled; exhaustive illegal-encoding and halfword-access verification are not
claimed. EBREAK mtval=PC is the project's current policy, not a universal claim for
all implementations.

## Library versus fixture ownership

| File | Ownership and purpose |
|---|---|
| Verification/lib/core/rv32/rv32_reference_pkg.sv | Common instruction encoders and base semantics |
| Verification/lib/core/rv32/rv32_machine_reference_pkg.sv | Common supported fault classification and one trap-entry state transition, mtval CSR state |
| Verification/lib/core/sva/core_sync_trap_sva.sv | Common synchronous packet/state/return assertions using expected cause, mtval and PCs |
| Verification/lib/core/core_pipeline_if.sv | Read-only memory-stage PC, trap tval and CSR mtval observations |
| Verification/lib/core/trap_functional_cov.sv | Dedicated reusable actual-trap functional coverage |
| core_trap_observe.sv | DUT hierarchy taps only |
| tb_core_trap_lean.sv | Case selection, image/handler, independent run-ahead, completion and signature checks |
| core-trap-f2-*.json, run_f2.ps1 | Case configurations, file ordering, execution and evidence retrieval |

core_sync_trap_sva generalizes the former core_ecall_mret_sva; its rules were not
copied into separate per-case assertion files. The same monitor is used by F1 and
F2. Historical F1 artifacts retain the original source snapshot.

## Decisive checks

- Actual trap packet must match predicted fault PC, cause, tval, synchronous type
  and direct target, with no ordinary retirement or RF/CSR effect on the trap edge.
- At the next sampling edge, mepc/mcause/mtval/mstatus and registered fetch PC must
  match independent entry expectations. This is |=> preponed sampling of the
  commit edge's NBA updates, not an arbitrary elapsed-time wait.
- A valid MEM-stage fault packet at the predicted misaligned instruction PC must
  emit no physical memory request. An explicit successful cover witness is required
  for load/store cases; a vacuous assertion cannot satisfy completion.
- All physical nonzero-GPR and accepted-store events remain ordered against the
  common scoreboard. Unexpected reads, missing/extra effects and poison writes fail.
- Handler CSR reads are independently predicted GPR results and stored signatures.
  Thus mtval is checked at entry, by software reads and in final DMEM evidence.
- MRET must target software-updated mepc, restore MIE/MPIE and resume a drained,
  checked application stream. Exactly one trap and one return plus entry/return,
  WB redirect and M/W flush witnesses are required; a watchdog catches noncompletion.

The fixture remains RF-first after each synchronous exception. The preserved dense
adjacent-store test is a separate failing regression (F1-EXC-01), not weakened,
skipped within these checks, or declared resolved by these passes. No memory-model
flush mask or physical-effect de-duplication is used.

## Dedicated functional coverage

trap_functional_cov samples physical {interrupt,cause} and mtvec.MODE on actual
trap commitments. Its covergroup has five cause bins (2,3,4,6,11), two mode bins
(direct/vectored), and ten cause-by-mode cross bins. Hardware counters independently
report observed samples and case/mode hits. The completion check requires the
actual expected cause bin and direct bin to be sampled once, not a synthetic index.

The current mtvec CSR preserves MODE=0; its Part 1 contract lists mask 0xfffffffc.
No force or backdoor is used to manufacture vectored hits. Vectored and its crosses
remain visibly unhit. Per-run IMC metrics must not be mistaken for a merged suite
percentage; the ledger reports observed cause union separately from raw IMC reports.

Each single-cause run normally covers 3/17 total bins (cause + direct + cross), with
26.67% point/cross average. Those figures do not indicate missing execution of that
case and are not full coverage closure. Interrupts, vector mode, nested faults,
aligned loads, byte/halfword misalignment, bus faults and trap/wait overlap remain
outside this F2 matrix.

## Reproduction

`pwsh -NoProfile -File Verification/tb_core_trap_lean/run_f2.ps1 -Case all -Final`

Omit -Final for lightweight iteration. Select illegal, ebreak, load or store for a
single case. The all runner collects each case and raises an aggregate failure
only after preserving results; -NoThrow returns the individual verdicts instead.
Case negative-mtval intentionally corrupts only the expected tval supplied to SVA;
it must fail and is not a positive regression. F1 remains runnable via run_f1.ps1.
