# F3 requested-policy findings

Status: OPEN. The user explicitly chose retaining MEIP > MTIP > MSIP as an F3
requirement. These are real failing requirements, not expected checker-negative
cases or waived unsupported bins. Current custom behavior is reported separately.
Diagram: [verification path](docs/diagrams/core_trap_architecture.md).

## F3-IRQ-01: enabled MEIP/MSIP visible in mip but never serviced

External-only stimulus is held high. At 195 ns, mip=mie=0x800 with global MIE=0;
the masked window passes. Software commits MIE=1 at 265 ns. The bounded-service
assertion then fails: mip remains 0x800, mie remains 0x800, mstatus=8, traps=0 and
mepc=0. The source was not lost and was enabled, but no interrupt committed.

The software-source case has the same result with mip=mie=8. It passes pending
visibility/masking, then fails service with global MIE=1 and no trap. Level sources
remain asserted; these tests do not incorrectly require a deasserted external
pulse to remain pending. Timer/fast pulse-latch behavior is tested separately.

[External log](../artifacts/vlsi_auto/core-trap-f3-external_20261113T174123Z_eb6637d7/results/simulation.log),
[software log](../artifacts/vlsi_auto/core-trap-f3-software_20261113T174139Z_504548de/results/simulation.log).

Source explanation: top.v constructs irq_raw solely from fast_irq_i[11:0] and
timer_irq_i. ext_irq_i/sw_irq_i feed csr_regfile's mip visibility but are absent
from gateway/arbiter inputs. irq_arbiter only considers mie[27:16] and mie[7].
This static route gap explains the runtime observations. It is not fixed by
relaxing the timeout or by accepting the custom policy as the requested contract.

## F3-ARB-01: simultaneous MEIP/MTIP/MSIP selects MTIP instead of MEIP

All three sources are driven together; at 195 ns mip=mie=0x888 and MIE=0. After
the enable write at 265 ns, the core commits at 295 ns with mcause=0x80000007.
The independent requested cause is 0x8000000b. a_trap_packet fails on that mismatch.
The final snapshot shows mip=0x808: timer was acknowledged, external/software still
pending. mepc=0x80000050 agrees with the independent PC frontier; a correct PC does
not compensate for selecting the wrong source.

[Full priority log](../artifacts/vlsi_auto/core-trap-f3-priority_20261113T174316Z_bd3f6ebe/results/simulation.log)
and [SHM waveform](../artifacts/vlsi_auto/core-trap-f3-priority_20261113T174316Z_bd3f6ebe/results/waves.shm/).

The active arbiter has a custom class policy placing timer first among its routed
sources, and never receives MEIP/MSIP. This failure is a consequence of the route/
policy mismatch, not evidence of a separate random timing bug. No full MEIP > MTIP
> MSIP ordering or nested interrupt preemption can be signed off from these runs.

## What does pass, and what remains

Timer, late timer, fast0 (cause 16) and fast6 (cause 22) complete one IRQ/handler/MRET
session and the dependent application stream. Early cases verify eight masked
pending samples. The model saves the first independently expected unretired PC
(0x80000050 early, 0x80000060 late) and replays it without adding four. MIE entry and
return transitions have real hardware coverage witnesses. These passes do not
substitute for the three failed requested-policy cases.

No RTL, source routing, priority table, responder masking, or GitHub issue state was
changed. F1-EXC-01 and F02-WB-01 remain open. A separately authorized architecture
change must resolve MEIP/MSIP routing and the requested source order before F3 can
close. Preserve these exact failing cases against any candidate implementation.

Replay all requirements with `run_f3.ps1 -Case all -NoThrow`; individual cases are
external, software and priority. -NoThrow preserves failed verdicts while allowing
the complete matrix to finish. Only negative-mepc is an intentional checker self-test.
