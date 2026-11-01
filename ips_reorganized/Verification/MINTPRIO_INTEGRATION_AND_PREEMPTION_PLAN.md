# Software-managed interrupt nesting with class-based mintprio

> **Implementation update (2026-10-29):** The active RTL now routes 13
> sources using cause 7 and causes 16–27. Class 2 uses fixed timer order
> `7,22,24,26,20,21,23,25`; class 1 uses round robin `19,18,27`; class 0
> uses round robin `17,16`. SPI EOT (27) therefore no longer outranks the
> timers. The existing software-managed `mintprio` remains in place. The
> six-source tables, implementation status and test counts below are historical
> and must not be used as the current design specification. A focused RTL block
> test is `tb_irq_restructure.sv`; it is not an end-to-end SoC or firmware test.
> IRQ acceptance versus older CSR writes and the MUL/DIV interruption scenario
> remain unverified pipeline risks. Commit-time recheck/replay remains a backup,
> not implemented behavior. The existing verification infrastructure and
> firmware still require review for the new source map and priority classes.
> For the current unit-level coverage bins, see [IRQ_UNIT_COVERAGE_PLAN.md](IRQ_UNIT_COVERAGE_PLAN.md).

Date: 2026-10-27
Status: proposed integration and verification plan; no RTL, firmware, or checker changes implemented by this document.

## 1. Architecture decision

Restore the old core's division of responsibility: hardware provides live trap CSRs and atomic trap entry/MRET; software preserves nested contexts and the previous priority threshold in RAM. Retain the active core's gateway, class arbitration, round-robin selection, source IDs, and precise pipeline retirement.

Use the custom CSR `mintprio` at `0x7C0` as a **class threshold**. This restores the old CSR address and software-managed policy, but changes its meaning from a cause-ID threshold to the class-rank encoding below. Old firmware that writes interrupt IDs to mintprio must be ported; it is not binary compatible with these semantics.

The two hardware round-robin pointers remain. The CSR shadow arrays, hardware nesting counter, and automatic current-class push/pop are removed as a coordinated change after the tests below are ready. No hardware context stack is required for round-robin arbitration.

Tradeoff: software entry/exit adds instructions and RAM traffic, and interrupt preemption begins only after the protected save phase. This simplifies hardware context ownership but does not establish an area, timing or latency improvement without measurement. Measure the save-to-enable interval and total entry/exit cost against the eventual response-time requirement.

## 2. Proposed CSR contract

Use unsigned ranks to represent the idle state without a special active-handler bit:

| mintprio[1:0] | Eligible interrupt classes | Typical use |
|---|---|---|
| 0 | 0, 1, 2 | Main code; reset threshold |
| 1 | 1, 2 | Class 0 handler |
| 2 | 2 | Class 1 handler |
| 3 | None | Class 2 handler; block all maskable sources in this arbiter |

The candidate rank is `class + 1`, evaluated with enough width to represent rank 3. Eligibility is `pending && source_enable && MIE && (candidate_rank > mintprio[1:0])`. Cause ID remains the interrupt identity; it is not the quantity compared to mintprio.

- Reset: full CSR reads zero. `mstatus.MIE` also resets zero, so threshold zero does not independently enable interrupts.
- Bits [31:2]: read as zero; writes are ignored. Writes retain the low two bits, including out-of-range full-width operands such as 4 or 0xffffffff.
- Implement normal CSR read/write/set/clear forms, immediate forms, and the existing CSR validity path. Architectural CSR instruction suppression rules still apply.
- Interrupt and exception entry do not modify mintprio. MRET does not modify mintprio. Software owns its save/set/restore operations.
- Pending capture is independent of mintprio and mie. A threshold-blocked edge stays pending according to the gateway contract; a level source must remain asserted until serviced if software expects deferred delivery.
- Raising a threshold is a policy operation, not an acknowledgement. It must not clear pending state or advance a round-robin pointer.

Preserve the active source mapping:

| Source | Cause ID | Class | Selection within class |
|---|---|---|---|
| GPIO | 16 | 0 | Round robin with I2C |
| I2C | 17 | 0 | Round robin with GPIO |
| SPI TX/RX event | 18 | 1 | Round robin with UART |
| UART | 19 | 1 | Round robin with SPI TX/RX |
| Timer 0 channel 0 compare | 7 | 2 | Lower fixed priority than ID 27 |
| SPI end-of-transfer event | 27 | 2 | Higher fixed priority than ID 7 |

ID 27 is SPI end-of-transfer in the current SoC wiring. Old core comments call it a watchdog; do not use those comments to claim an integrated watchdog. Additional fast timer sources, MEIP/MSIP delivery, AON watchdog, and CLIC integration are outside this migration.

## 3. Hardware integration work

| File | Planned change |
|---|---|
| `riscv_core/rtl/csr_regfile.v` | Add mintprio storage, address decode, valid/read/write support and threshold sideband. Remove shadow arrays, nest_depth, cur_class, automatic CSR reloads on MRET, and the side effect that a software mepc write updates a shadow entry. Preserve live mepc/mcause/mtval capture and the existing supported CSR masks. |
| `riscv_core/rtl/irq_arbiter.v` | Replace cur_class/nest_depth inputs with mintprio threshold. Preserve source masks, class ordering, fixed selection in class 2 and round-robin selection in classes 0/1. |
| `riscv_core/rtl/top.v` | Connect CSR threshold to the arbiter; remove shadow sidebands. Remove class plumbing that becomes unused, including trap-class transport only where it is no longer needed. |
| `riscv_core/rtl/wb_trap_mret_commit_controller.v` | Preserve committed trap redirect and MRET redirect/atomic status update. Return through live mepc, restore MIE from MPIE and set MPIE according to the supported M-mode contract. No implicit mintprio restoration. |
| Pipeline/hazard logic | Audit ordering of CSR writes against IRQ acceptance, CSR reads, trap commit, and MRET. Add forwarding, serialization, or cancellation only where required by evidence. |

Do not replace the active core wholesale with legacy files: retain current pipeline fixes, gateway behavior, bus interfaces, source mapping and supported CSR behavior.

### Retirement ordering requirement

IRQ decisions currently start in Execute while CSR changes commit in Writeback. The new threshold must obey program order, just like MIE/mie:

1. An IRQ taken before a disabling/threshold-raising instruction retires is permitted; that instruction has not yet taken effect and must execute correctly after return.
2. Once the instruction retires, a younger IRQ trap cannot commit using a stale permissive threshold or enable state.
3. Enabling MIE after saving a frame and installing its threshold cannot expose an unfinished frame or stale threshold.
4. MRET must use the intended restored mepc and status, even when their CSR writes occur immediately before it.
5. One accepted interrupt produces one committed trap and one matching acknowledgement; flushed packets must not change architectural state or RR pointers.

These are integration requirements, not a claim that the present pipeline has already been proven to violate them. Architectural checks must distinguish acceptance from commit and use the correct state history.

## 4. Firmware contract and trap frame

Hardware clears MIE on every trap entry and captures one live mepc/mcause/mtval plus the supported mstatus trap fields. Firmware must preserve that entry state before allowing another interrupt.

Recommended common frame: **96 bytes**, preserving 16-byte stack alignment for the existing standard ILP32 calling convention. The present 72-byte frame is not a complete basis for the new contract.

| Frame offsets | Contents |
|---|---|
| 0..60 | Existing 16 caller-saved GPRs: ra, t0..t6, a0..a7 |
| 64 | Return mepc, writable by a recoverable-exception handler |
| 68 | This trap's mcause |
| 72 | This trap's mtval |
| 76 | mstatus captured after hardware trap entry |
| 80 | Previous mintprio |
| 84 | Previous mie, restored if handler policy changes source enables |
| 88..95 | Reserved/padding; available for a software marker if needed |

C callees preserve callee-saved registers under the ABI; assembly helpers must obey the same contract. Trap entry must preserve any GPR it uses, including temporaries used for CSR access. Keep gp/tp intact. A test must check interrupted GPR values, not infer preservation solely from a C variable.

### Interrupt entry sequence

1. Enter with MIE cleared by hardware. Allocate an aligned frame and save all required GPRs, entry CSRs, previous threshold and relevant mie state.
2. Decode the interrupt ID using the agreed source map; set mintprio to `class + 1`. Unhandled sources go to the defined failure handler.
3. Make the frame available to the dispatcher. Clear/service the peripheral according to its driver protocol; edge acknowledgement by the gateway does not replace clearing a peripheral's level condition.
4. Re-enable MIE only after frame creation and threshold installation are complete. This is the explicit opt-in to higher-class preemption. A handler may choose to keep MIE cleared.
5. Dispatch the ISR. Its own cause/mtval are read from its frame when needed after a nested trap.

### Exit sequence

1. Clear MIE before restoring any return state or lowering the threshold.
2. Restore the previous threshold, relevant mie state, and the frame's return mepc. Honour deliberate mepc changes made by a recoverable-exception handler.
3. Restore the saved post-entry mstatus with MIE kept zero until MRET. Its saved MPIE controls the returned MIE. Do not blindly set MIE to one in the epilogue.
4. Restore GPRs/sp and execute MRET. Hardware performs the atomic PC/status return using the live CSRs; there is no hardware array pop.

mcause and mtval describe the most recent trap; MRET does not automatically restore the parent's values. Each handler's frame preserves its own values. If the software API promises restored live parent mcause/mtval, implement that explicitly using linked frames rather than assuming a child frame contains the parent's cause.

### Synchronous exceptions and capacity

- A synchronous exception is not subject to mintprio. The exception path saves/restores the same return context, preserves the previous threshold, and keeps nesting disabled by default while it handles the fault.
- A recoverable exception inside an ISR returns to the intended handler instruction while preserving its threshold and frame. Fatal faults use the existing explicit failure policy.
- Entry/exit code and its stack accesses must be valid and nonfaulting until recoverable context is safely saved or restored. MIE=0 does not block synchronous exceptions. A second fault that overwrites an as-yet-unsaved live trap context cannot be assumed recoverable with one CSR bank; define an explicit fatal/double-fault policy rather than promising arbitrary recursive-fault recovery.
- Strict class ascent permits at most **three concurrently active IRQ handlers** (0 -> 1 -> 2), plus main. This is not a two-level limit. Sequential interrupt entries are unlimited subject to software progress.
- Size the RAM stack for those frames, C call depth and the chosen synchronous-exception policy. Guard against stack corruption/recursive faults; a single live CSR bank does not provide automatic context capacity.
- The existing stage-7 path does not visibly re-enable MIE inside the inspected trap wrapper/handlers. The new regression must prove actual nested entry before the outer exit, not treat eventual handling as preemption.

## 5. Verification strategy

### A. Component tests before firmware nesting

1. **CSR unit tests:** reset/readback, all four thresholds, upper-bit masking, CSR instruction variants, zero-operand suppression, trap/MRET priority, no implicit threshold change on interrupt/exception/MRET, normal mepc writes without shadow side effects.
2. **Arbiter reference test:** independently calculate eligible sources, select highest class, then fixed or RR winner. Sweep all 64 pending vectors x 64 source-enable vectors x 4 thresholds x 2 global-enable values x 4 reachable RR-pointer combinations = **131,072 input/state snapshots**. Establish pointer states through reset/committed service history. Check output-valid and ID only when valid.
3. **RR state tests:** request without commit, canceled/exception trap, other-class commit, and mask/threshold changes must not rotate the wrong pointer. Each pair alternates under sustained pair eligibility and repeated IRQ commits. All-zero and single-member masks are included.
4. **Gateway tests:** disabled/threshold-blocked edge capture; delayed unmask; continuously high level; level deassertion while blocked; a new edge coincident with clear; low/high separation between successive edges. Multiple events on one already-pending edge source may coalesce: do not promise an event counter or FIFO.

### B. Core-directed firmware tests

Use controllable core IRQ inputs for precise timing, labelled as core-path tests rather than peripheral-integration proof.

| ID | Required experiment and expected evidence |
|---|---|
| P01 | Every source separately at threshold 0: correct cause, entry PC, single acknowledgement, return and forward progress. |
| P02 | Hold each source pending while MIE=0, mie bit=0, or threshold blocks it; release each gate separately and check correct deferred behavior. |
| P03 | In each active class, offer same, lower and higher classes: same/lower never preempt under the standard handler policy; higher classes do. A blocked source may run after the handler returns and restores the prior threshold. |
| P04 | Exercise all 12 legal ordered source pairs across class combinations 0->1, 0->2 and 1->2. For each, prove inner entry precedes outer exit and check exact resumed PC/context. |
| P05 | Exercise all 8 source choices for 0->1->2, then return 2->1->0->main. Compare every frame and threshold transition; check sp and GPR canaries, final main signature and subsequent new interrupts. |
| P06 | Have every handler leave MIE disabled: no nesting despite higher-priority arrivals; deferred sources run after return as their remaining gate conditions allow. |
| P07 | Repeat/nest events while a frame is being saved, immediately before/after enabling MIE, during the body, while disabling MIE, restoring threshold/mepc/status, and immediately around MRET. Check pipeline ordering rules above without artificial NOP workarounds. |
| P08 | Both RR pairs continuously eligible: correct alternating service. Nest a class-2 handler inside a class-0/1 handler; validate committed service history determines subsequent RR order. |
| P09 | Both class-2 sources pending together: ID 27 wins. Once it is serviced/deasserted, ID 7 runs. Same-class preemption remains blocked during a class-2 ISR. |
| P10 | A recoverable synchronous exception in an ISR, including while MIE=0: preserve prior threshold, amend frame mepc where required, resume ISR and unwind correctly. Separately test an exception during entry/exit under a bounded, recoverable test setup. |
| P11 | GPR, memory and CSR hazards: adjacent mintprio/MIE/mie/mepc/status writes and reads, threshold raise/lower with pending IRQs, MRET immediately after restoration, long load/store stalls and MUL/DIV interruption. Retired effects match an uninterrupted reference. |
| P12 | Repeat nested sequences to detect stack leakage; stack guards survive. Reset during a nested handler restores reset CSRs/gateway/RR and discards prior contexts rather than attempting to unwind them. |

### C. SoC integration tests

- Generate each of the six supported interrupts through its actual peripheral path at least once; compare ID/class and end-to-end acknowledgement/deassertion.
- Use deterministic peripheral schedules for representative 0->1, 1->2 and 0->1->2 nesting. Record actual inner/outer entry and exit, not only interrupt counters.
- Preserve the existing boot, memory, peripheral and exception regression checks. Adapt obsolete shadow-stack expectations with the new architecture contract; do not remove detection of wrong return PCs, lost pending requests or corrupted context.
- Keep Timer 1/unconnected fast inputs and absent AON/CLIC outside the positive-delivery coverage denominator. Their integration is a separate task.

## 6. Assertions and independent checking

Update the existing `infrastructure/checkers/irq_predictor.sv` to predict real eligibility/winner selection using pending state, committed mie/MIE/mintprio and independent RR history. Its present two-entry shadow-stack model must not remain the expected architecture.

Add/adjust these checks:

- An arbiter request has an enabled pending source and `rank > threshold`; highest eligible class wins, then fixed/RR rules apply.
- No architectural state, gateway acknowledgement or RR rotation from a flushed/uncommitted interrupt packet. An ordinary exception cannot rotate an IRQ RR pointer based on a matching numeric cause alone.
- MIE or threshold blocking never clears pending state by itself. Gateway edge/clear coincidence follows its documented pulse-wins rule.
- Trap entry captures the correct interrupted PC/cause, clears MIE and records prior MIE in MPIE. mintprio changes only on reset or an authorized committed CSR operation.
- MRET uses the correct live mepc/status and leaves mintprio unchanged. A synchronous-exception return is valid and is not a hardware-stack underflow.
- A frame scoreboard uses an independent unbounded software model stack, not removed DUT shadow arrays. Record interrupted PC/GPR state at each trap and compare restoration/resumption, threshold snapshots, frame disjointness and sp balance. Support documented handler mepc edits.
- Frame save/restore instrumentation is cross-checked against retired instruction and memory events. A firmware `sw_nest_depth` counter is useful evidence but is not the sole oracle.
- Latency bounds apply only with eligible source, MIE/mie enabled, bounded stalls and no perpetual higher-class traffic. RR guarantees concern eligible commits within a class; they do not promise global starvation freedom.

Migrate monitor/transaction fields in `infrastructure/monitors/irq_monitor.sv`, `infrastructure/tb/tb_pkg.sv` and `infrastructure/tb/soc_tb_top.sv`: add actual mintprio/mie/MIE and acceptance/commit snapshots; replace hardware nest_depth with explicitly labelled model/software depth. Sample valid events at the right phase and attach the selected/committed ID from that event, not a later combinational winner.

## 7. Functional coverage and required bins

Functional bins measure exercised scenarios; assertions and scoreboards decide correctness. Sample attempted eligibility decisions separately from accepted/committed IRQs and returns. Avoid giant unrestricted crosses whose impossible combinations hide missing tests.

| Group | Required bins/crosses | Completion intent |
|---|---|---|
| CSR | threshold {0,1,2,3}; reset; register/immediate RW/RS/RC forms; zero-operand suppression; upper-bit patterns {zero, nonzero, all ones}; all 16 old->new threshold transitions | Every applicable bin; label operation suppression according to the instruction encoding. |
| Eligibility | source {7,16,17,18,19,27} x threshold {0..3} x source-enable {0,1} x global MIE {0,1} = 96 source/gate combinations | All combinations, sampled as attempts, including blocked cases; component snapshot sweep also covers source interactions. |
| Class relation | active class {0,1,2} x offered class {0,1,2}: three equal, three lower, three higher cases | All nine; lower/equal are observed deferrals, not expected grants. |
| Nested entry | each of 12 legal ordered source pairs; each of 8 0->1->2 source triples; concurrent IRQ depth {0,1,2,3} | All legal pairs/triples; main is depth 0. No blanket assertion forbidding extra synchronous-exception frames. |
| Unwind | 3->2->1->0, 2->1->0 and 1->0; each outer threshold restored; entry MPIE {0,1}; saved mie unchanged/modified-and-restored | Confirm ordered returns and exact resume checkpoints, not just counters. |
| RR | pair {GPIO/I2C, SPI/UART} x both pointer values x pending {none,first,second,both}; committed winners and both alternating transitions | Both pairs; threshold blocking, mask changes and nested high-class service included. |
| Fixed order | class-2 pending {timer only, EOT only, both}; both source-enable combinations and threshold {allowed,blocked} | All reachable decisions; ID 27 priority checked independently. |
| Entry/exit timing | IRQ arrival in {save-frame, set-threshold, enable-MIE boundary, body, disable-MIE boundary, restore-frame, MRET boundary}; source relation {higher,equal,lower} where reachable | Explicit legal-bin list per test; cover ordering outcomes rather than requiring unsafe preemption in protected phases. |
| Pipeline ordering | CSR target {mintprio,MIE,mie,mepc,status}; direction {tighten,relax,restore}; neighboring event {IRQ accept,IRQ commit,sync trap,MRET}; relevant stall {none,LSU,MUL,DIV} | Directed legal combinations, including same-cycle/adjacent-cycle boundaries; reviewed unreachable combinations excluded. |
| Gateway | edge/level; blocked/unblocked; edge with clear; reassert after clear; held level; deassert-before-unmask; coalesced pulses | All configured modes and precedence outcomes. |
| Exceptions | location {main,ISR body,entry/exit}; prior MIE {0,1}; prior threshold {0..3}; outcome {resume,explicit fatal policy} | Recoverable paths check frame edits and restoration. Fatal paths have their own expected termination. |
| Progress | deferred source delivered; repeated sequences; balanced sp; intact guards; ISR nesting observed; reset during nesting | Explicit pass gates, not optional informational counters. |

On changed reachable control logic, target complete block/branch coverage and toggle coverage of threshold bits and RR state. Review unreachable code/bins individually with reasons; do not set broad exclusions just to reach a percentage. Track each requirement to a named test, assertion and/or coverage bin.

## 8. Work order and acceptance

1. Review/freeze this CSR encoding and the software context/exception contract. User's proposed architecture supplies the direction; these details are the remaining design decisions.
2. Prepare the independent arbiter/CSR reference checks and firmware frame expectations.
3. Integrate CSR, arbiter, core wiring and trap/MRET behavior together. Update the filelist only as needed; unrelated UART source closure remains a separate known build prerequisite.
4. Run component tests, then simple nonnested IRQ/exception returns, two-level nesting, three-level nesting, CSR ordering stress and peripheral-driven SoC tests.
5. Migrate predictor/monitor coverage, execute targeted random timing after directed cases, inspect uncovered legal bins and preserve exact source/configuration/seed/tool/log evidence.
6. Record symptom, cause, decisive experiment, correction and regression for any substantive failure; in tutor mode, return diagnosis to the user before fixing a newly discovered design/testbench failure.

Accept only when the exact active SoC filelist elaborates, directed cases pass, all mandatory legal functional bins are hit, no unresolved assertion/scoreboard failures remain, return PCs/GPRs/stack/threshold are checked, and the existing relevant regression is green. Record code coverage exceptions and bounded-latency assumptions explicitly. Compilation or firmware PASS alone is insufficient.

## 9. Evidence inspected for this plan

- Legacy `rv32im_zicsr_5stage_exc_nointr_old/top.v`: actual mintprio gate compares selected cause ID to the CSR. Legacy CSR/MRET files contain live trap state without the active two-entry arrays.
- Active `riscv_core/rtl/{csr_regfile.v,irq_arbiter.v,irq_gateway.v,top.v,execute_cycle.v,hazard_unit.v,wb_trap_mret_commit_controller.v}` and `RTL_SOC/soc_subsystem.f`.
- Current `Verification/tests/bsp/{trap_handler.s,isr_dispatch.c}`, `tests/suites/stage7_nested_irq/main.c` and `MILESTONE5_FINDINGS.md`.
- Current IRQ predictor/monitor and TB bindings. Historical verification notes describe intended behavior; they are not evidence that these proposed tests have passed.

All paths above are relative to `ips/` unless explicitly legacy-rooted. This plan does not claim a simulation result or an implemented migration.
