# Core trap contract and staged boundary

Status: F0 contract is implemented and evidenced in RESULTS.md. Trap behavior below remains intended expectations for F1+, not an F0 claim; unresolved items are not waivers. Diagram: [validated F0 architecture](docs/diagrams/core_trap_architecture.md).

| Requirement | Independent expectation | Observation / status |
|---|---|---|
| Reset and known stream (F0) | RESET_PC `0x80000000`; local fixed instruction image and sequential PC | PC/instruction pairs, actual GPR write effects and one accepted signature store checked; passed once |
| ECALL entry | mcause=11; mepc=program label E; MIE=0, MPIE=pre-entry MIE | Checked in F1 minimal and relocated smoke; dense adjacent-store case remains failing |
| Direct redirect | mtvec & ~3 | Direct ECALL target and registered fetch PC checked with independent expected handler PC; handler execution checked by effects |
| Vectored redirect | Interrupt: (mtvec & ~3)+4*cause; synchronous fault: base | Not implemented; synchronous exception with MODE=1 remains required |
| Squash | No effect from faulting or younger killed dynamic instructions | RF-first smoke physical effects pass; immediately adjacent store violates squash (F1-EXC-01) |
| MRET | PC=software-written mepc; MIE=old MPIE; MPIE=1 | Checked in F1 smoke: exact target, restored status and resumed application effects |
| Faulting store | No successful memory mutation | Not implemented; check memory-stage request gating and actual responder acceptance |
| Interrupt PC | Next architectural instruction not completed, including abort/restart semantics | Not implemented; acceptance point remains to inspect |
| IRQ priority | Platform-defined class policy, masks, gateway retention, mintprio | Unresolved; handoff standard priority claim conflicts with custom core path |

Implementation evidence from current RTL: `top` routes timer and fast_irq_i[11:0] through the gateway/arbiter. `ext_irq_i` and `sw_irq_i` connect to CSR inputs but not that gateway vector. Reachability and intended service behavior need explicit review; do not claim standard MEIP/MSIP service.

Before F1 implementation, inspect fetch PC update and flush/stall priority, memory-stage side-effect gating, actual register-file write edge, CSR sequential priority, execute exception/IRQ arbitration, and arbiter priority table. Resolve remaining expectations with source citations and a distinguishing waveform; do not change DUT RTL as part of this F0 result.

The interpreter supports LUI, ADDI, SW and JAL. F0.2 adds memory waits and common hold/flush/redirect assertions; see F02_CONTRACT.md and open F02_FINDINGS.md. Loads, conditional branches, traps and error recovery remain outside the executed scope.

## F1 current evidence

The implemented minimal ECALL/MRET contract is in F1_CONTRACT.md. Exact saved PC,
direct redirect, status transitions, MRET target and unhalted completion pass in the
RF-first smoke. F1_FINDINGS.md records the failing immediately adjacent-store case.
Therefore the table above remains the broader intended contract, not universal
closure. IRQ, vector mode, other exception causes and nested return remain untested.

## F2 current evidence

F2_CONTRACT.md defines the four directed cases: illegal instruction (2), EBREAK (3),
misaligned LW (4) and SW (6), each with exact mepc, handler/mret flow and mtval.
They pass in F2_MATRIX.json. The faulting load/store emit no memory request and no
architectural effect. This supersedes the table's prior unimplemented status only
for these cases; bus faults, IRQs, vector mode and general squash closure are not
established. F1-EXC-01 remains open.
