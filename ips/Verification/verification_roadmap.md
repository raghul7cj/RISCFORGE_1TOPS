# Verification review and future test roadmap

Reviewed 2026-10-23. Baseline: retained runs 20261018_run01 and 20261019_run02, including the run02 follow-ups. This is a documentation review and proposed execution order; no simulations were rerun.

## Review decision

Proceed with the current structure as the evidence companion to the [Rev B master plan](../RISCFORGE_Verification_Plan_RevB.docx). Keep the master plan, component evidence records, matrix, and original run artifacts in their present roles. The records correctly distinguish direct peripheral checks, synthetic fabric responders, staged integration sources, and checker self-tests.

The structure is suitable; the evidence set is not yet complete for sign-off. The [matrix](verification_matrix.csv) has 15 evidence summaries: 12 PASS, 1 INCOMPLETE, 1 NO_RETAINED_RUN, and 1 NOT_INTEGRATED. These are results for stated boundaries, not percentages of requirements covered. Timer0 and the boot-path row share integration evidence; the two timers share a component bench. Do not add their counts as independent coverage.

## Existing test plans to inspect

All six integrated APB peripherals already have detailed plans in Rev B. Each subsection includes device identity, register model requirements, test scenarios, coverage points, and known issues. The scenario tables include stimulus, oracle, and measurable pass criteria. No duplicate peripheral plan was created.

| Peripheral | Existing Rev B plan location | Retained evidence record |
|---|---|---|
| GPIO | 15.2 **Per-device subsection - GPIO**, test scenarios 15.2.3 | [GPIO](components/apb/gpio.md): 312/312 direct wrapper checks |
| I2C | 15.3 **Per-device subsection - I2C master**, test scenarios 15.3.3 | [I2C](components/apb/i2c.md): 90/90 direct APB/pin-model checks |
| SPI | 15.4 **Per-device subsection - SPI master**, test scenarios 15.4.3 | [SPI](components/apb/spi.md): 26/26 component BFM checks |
| Timer0 | 15.5 **Per-device subsection - Timer 0**, test scenarios 15.5.3 | [Timer0](components/apb/timer0.md): shared 9/9 component checks and 52/52 staged integration checks |
| Timer1 | 15.6 **Per-device subsection - Timer 1**, test scenarios 15.6.3 | [Timer1](components/apb/timer1.md): shared 9/9 component checks |
| UART | 15.7 **Per-device subsection - UART**, test scenarios 15.7.3 | [UART](components/apb/uart.md): INCOMPLETE before first register read completes |

Use the full subsection title when navigating Word: Section 15 also has general subsections using the same numbers. The AON watchdog has a separate specified-but-not-integrated plan at **15.8 Per-device subsection - AON watchdog**; it is not a seventh integrated APB slot.

The [SoC infrastructure plan](soc_verification_plan.md) is an existing implementation plan for the verification infrastructure. Read it with Rev B; its planned capabilities are not execution evidence. Fabric, SRAM, boot, timeout, and checker records remain linked from the [evidence index](README.md).

## Documentation gaps to close

1. **Traceability:** the matrix has one row per evidence area, rather than one per requirement or behavior. Retain it as a summary. Add a requirement-to-test mapping as the next level, using exact Rev B IDs and retained bench check labels. Include configuration, stimulus, expected result, oracle source, observation point, observed result, evidence link, and remaining gap. A component pass cannot close a CFG-S obligation without the required SoC boundary.
2. **Record consistency:** the shared template has oracle and traceability fields, but existing records do not consistently fill them. Add these fields as the underlying bench/log mapping is reviewed. Mark unknowns explicitly; never reconstruct an expected result from the observed result alone.
3. **Historical evidence conflicts:** the run02 README and UART replay notes claim a fatal and peak-memory summary in `uart/debug/sim_adapter.log`; the retained file ends at `ADAPTER before PSEL 60000`. The precise fatal and memory report are uncorroborated by that file. The SPI follow-up manifest/log supersede the earlier caveat in the run02 top-level manifest. Preserve the original artifacts and explain precedence in current records.
4. **Master-plan review:** the UART scenario introduction says nine checks require a serial peer and then says those nine are self-sufficient without one. Review the actual scenario rows and clarify which need external pins versus internal loopback before designing their environment. Plan statements about defects are review inputs, not newly confirmed causes.
5. **Reproducibility:** preserve existing manifests and staged sources. For future runs, record exact commands, tool version, defines, plusargs, seed or none, filelists, source hashes, model identities, stage outcomes, termination reason, per-case results, and relevant waveforms. A missing historical field stays unknown until supported by retained evidence.

## Ordered work and completion gates

The IDs below identify roadmap work packages, not new Rev B check IDs. All are proposed work; no new PASS is assigned here. Work packages R1, R2, and R3 can be prepared independently after R0. Integrate their results in R4 before the broader firmware gates.

| Order / ID | Work | Completion evidence required |
|---|---|---|
| 0 / R0 | Map retained checks to Rev B, starting with SRAM, bridge, aperture, and timers, then GPIO/I2C/SPI and checker records. Review the documentation conflicts above. | A reviewed mapping with exact bench labels, expected outcomes, oracle basis, run links, scope, and explicit unmapped obligations. Preserve existing aggregate verdicts. |
| 1 / R1 | Investigate the UART simulation stall using the controlled adapter/UART benches and a second simulator. | Same identified sources and responder configuration compared across simulators; bounded wall-clock runs; complete stdout/stderr, exit/termination records, and a focused handshake trace. Classify the result only as far as the evidence supports. |
| 2 / R2 | Cover fabric gaps, starting with finding any qualifying crossbar evidence, then planning missing tests. | Dedicated evidence for the master-plan crossbar obligations, including competing masters, response routing, backpressure, and error paths as applicable. Distinguish target BFMs from real peripherals. |
| 3 / R3 | Extend direct peripheral tests only where the reviewed mapping shows gaps. | Source-identified per-case results against independent expectations. Keep existing I2C, GPIO, timer and SPI passes as the baseline. Complete UART register tests only after its simulation makes reliable progress. |
| 4 / R4 | Verify peripheral behavior through the actual SoC path. | Firmware-driven transactions through the real fabric and peripheral RTL, observed at bus, register, IRQ, and external pins where required. Add Timer1 SoC evidence; retain Timer0's staged-source qualification until a maintained runnable configuration replaces it. |
| 5 / R5 | Exercise real-path timeout/error handling and monitor accounting. | Inject an agreed fault through the actual SoC path; retain the expected timeout/error response, recovery, and matching LSU/AXI/APB records for eligible transactions. Separate this evidence from standalone timeout and checker self-tests. |
| 6 / R6 | Resolve boot and accounting failures, then execute Stage1/Stage3 gates. | Explain and verify the local boot/watchdog symptom and remote activity/count mismatch reported in run02. Retain independently checked firmware activity and transaction counts; do not lower thresholds simply to pass. |
| 7 / R7 | Run the milestone regression and publish the completion record. | A source-identified run with per-case outcomes, requirement mapping, unresolved failures and exclusions, and explicit residual risks. Claim only the Rev B criteria actually met. |

### R1 UART experiment sequence

The first experiment should reproduce and capture evidence, rather than change RTL. Inspect the retained debug bench/filelist and responder scheduling first. Before execution, the engineer should state a short hypothesis and the observation that would distinguish it from competing explanations.

1. Reproduce the adapter-only case and existing no-DUT/grant-low controls with bounded execution and retained termination records. Capture APB select/enable, OBI request/grant, and state around the PSEL transition. If no fatal appears, record a stall/termination rather than a fatal.
2. Run the identical source set and responder configuration in a second simulator. Record any necessary compatibility edits separately; do not silently compare different experiments.
3. Review the result before choosing a responder-timing experiment or a source change. A simulator difference narrows the investigation but does not alone prove a simulator defect. The controls do not yet distinguish adapter behavior, responder behavior, and simulator handling.
4. Once the cause is established and a correction is authorized, retain the original failing reproducer as a regression, then complete direct UART APB checks and the planned serial/IRQ tests at their required boundary.

### R3 and R4 peripheral priorities

These are targets for gap review, not claims that every behavior is currently absent. Rev B remains authoritative for exact expected values and required configuration.

| Area | Next evidence to establish |
|---|---|
| SRAM and boot | Map the seven SRAM checks; preserve cold/warm-reset and boot-source identity; expand only against uncovered memory/boot obligations. |
| Bridge and aperture | Map the 28 and 43 checks independently. Use real peripherals in R4; synthetic routing passes remain fabric evidence. |
| Timer0 / Timer1 | Pin the elaborated source before evaluating source-dependent expectations; Rev B Timer1 explicitly requires DEV-0326 first. Cover remaining timing, reset, IRQ, and independent-instance obligations at the required scope. |
| GPIO | Trace the wrapper checks to register behavior, partial-write/error policy, pin input/output and interrupt scenarios; add real SoC firmware/pad observations where required. |
| I2C | Preserve the slave-model identity and map ACK/NACK/read/write behavior; add full firmware/fabric/IRQ evidence and remaining protocol cases from Rev B. |
| SPI | Separate component-interface checks from serial-pin and boot-flash checks. Preserve EOT pulse observability; cover remaining mode/divider/CS/FIFO/IRQ obligations without treating one boot read as general SPI closure. |
| UART | Complete R1, then register/decode/error, baud, TX/RX, FIFO, and interrupt obligations with the appropriate loopback or external serial peer. |
| AON watchdog | Keep NOT_INTEGRATED for this configuration. Replan its interface/reset/IRQ tests only if integration becomes an approved task. |

## How to retain the next run

Use a new dated run folder beneath `artifacts/component_first/`; never overwrite the Oct 18-19 baseline. Link its command/configuration record, manifest, logs, source snapshots, and waveforms from the relevant component record. Keep the detailed requirement mapping separate from the summary matrix so the existing matrix remains readable.

At a meaningful failure, state expected versus observed behavior and retain the evidence. Return hypothesis and correction decisions to the engineer in tutor mode. Routine setup and agreed experiment execution can proceed without repeated permission; a new diagnosis or design/testbench correction requires the corresponding discussion unless execution mode is explicitly requested.

The next recommended working session is R0 traceability for the bridge or SRAM, followed by agreement on the first R1 UART capture experiment. This roadmap does not authorize new simulations, RTL fixes, or acceptance-criteria changes.
