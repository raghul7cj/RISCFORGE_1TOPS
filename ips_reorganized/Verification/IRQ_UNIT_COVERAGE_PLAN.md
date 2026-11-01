# Interrupt unit coverage plan

Scope: `irq_gateway`, `irq_arbiter`, the IRQ-facing parts of `csr_regfile`, and
IRQ acknowledgement decoding in `wb_trap_mret_commit_controller`. This is not
pipeline, peripheral, firmware, exception-unit or complete CSR verification.
`tb_irq_restructure.sv` samples each functional bin only after checking its
expected result. The independently calculated arbiter oracle uses fixed source
lists and RR history established by committed IDs.

| Coverage group | Required bins | Check |
| --- | ---: | --- |
| Eligibility | 13 sources × 4 thresholds × 2 `mie` × 2 MIE = 208 | Valid, cause and class for each singleton request. |
| Stream selection | 3 pointer states × 8 request subsets = 24 | Cyclic selection including skipped members. |
| Background selection | 2 pointer states × 4 request subsets = 8 | Correct selected source. |
| Fixed priority | 28 pairs of eight timer sources | Earlier source in the agreed ordering wins. |
| RR feedback | 5 winners × matching commit / no commit / other-class commit = 15 | Rotation on matching committed ID only. |
| Event gateway | 10 event sources × single / separated / adjacent / held with ack = 40 | Pending capture and event-wins-ack. Events can coalesce. |
| GPIO gateway | rise / held-high ack / rise with ack / rearm = 4 | Rising-edge behavior and event-wins-ack. |
| Level gateway | 2 sources × asserted / held with ack / deasserted = 6 | Level pass-through independent of ack. |
| `mintprio` | 16 old-to-new transitions; zero / mixed / ones upper bits | Readback and masking; reset, trap and MRET leave threshold as specified. |
| `mie` | 19 implemented bit positions | One-hot write/readback and reserved-bit mask. |
| Interrupt CSR control | trap with MIE 0/1; MRET with MPIE 0/1; software/input MSIP; MEIP | Status, cause and PC checks; pending visibility. |
| Commit | 13 source IDs; invalid WB / invalid exception / synchronous exception / unsupported IRQ | One-hot clear only for a valid supported committed IRQ. |

Separately, the arbiter checks all 8,192 pending vectors at all four thresholds
and all six RR pointer combinations with all source enables and MIE set:
196,608 snapshots. Source/gate cross coverage does not imply an exhaustive
cross of all possible enable masks with all pending vectors. GPIO uses a rising
edge contract; I2C/UART use levels; timers and both SPI outputs use per-cycle
event capture. These are the configured core-input contracts, not proof that
each peripheral meets them.

Functional coverage measures only the declared bins; it is not proof of full
RTL correctness. Code coverage should be generated and uncovered RTL paths
reviewed separately. No unreachable bins are excluded to raise percentages.
The existing SoC predictor still models the old architecture and is not used as
the unit-test oracle. Pipeline ordering and MUL/DIV interruption remain outside
this unit scope.

Run `run_irq_unit_coverage.ps1` from any directory with Vivado 2022.2 installed;
the script creates a timestamped artifacts directory and retains tool logs and
functional/code coverage data. An incomplete code report is a failure of report
generation, not evidence of complete code coverage.
