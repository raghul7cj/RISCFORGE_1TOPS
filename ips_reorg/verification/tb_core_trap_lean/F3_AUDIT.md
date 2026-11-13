# F3 retained evidence audit

Matrix: F3 NOT SIGNED OFF: four service cases pass; external/software service and requested priority fail.

## Source identity

- f3_scenario.svh SHA256: 597742da6a44b853f96705d5dfe3315dca9b4cf8701a6753b6148bcb27c5843e — match.
- core_trap_programs.svh SHA256: 0473d6812e4bc03fd17fc284c6ae915a33aa439b0cfb1dc6734108cc2df1332a — match.
- Both included SVH hashes match F3_MATRIX.json. Primary review additionally recomputed every common_input_hashes entry: all current tested HDL/header hashes match (see JSON).

## Verdicts and IRQ witnesses

| Case | Verdict | IRQ_COV / observed result |
|---|---|---|
| timer | pass | F3_PASS case=timer cause=80000007 mepc=80000050 mask_samples=8 instructions=55 gpr=37 stores=5<br>F3_FINAL case=timer mip=00000000 mie=00000080 mstatus=00001888 masked_samples=8 traps=1 returns=1 expected_pc=80000050 actual_mepc=80000050<br>IRQ_COV timer=1 external=0 software=0 fast0=0 fast6=0 mie_entry_clear=1 mie_return_restore=1 |
| timer-late | pass | F3_PASS case=timer-late cause=80000007 mepc=80000060 mask_samples=0 instructions=55 gpr=37 stores=5<br>F3_FINAL case=timer-late mip=00000000 mie=00000080 mstatus=00001888 masked_samples=0 traps=1 returns=1 expected_pc=80000060 actual_mepc=80000060<br>IRQ_COV timer=1 external=0 software=0 fast0=0 fast6=0 mie_entry_clear=1 mie_return_restore=1 |
| fast0 | pass | F3_PASS case=fast0 cause=80000010 mepc=80000050 mask_samples=8 instructions=55 gpr=37 stores=5<br>F3_FINAL case=fast0 mip=00000000 mie=00010000 mstatus=00001888 masked_samples=8 traps=1 returns=1 expected_pc=80000050 actual_mepc=80000050<br>IRQ_COV timer=0 external=0 software=0 fast0=1 fast6=0 mie_entry_clear=1 mie_return_restore=1 |
| fast6 | pass | F3_PASS case=fast6 cause=80000016 mepc=80000050 mask_samples=8 instructions=55 gpr=37 stores=5<br>F3_FINAL case=fast6 mip=00000000 mie=00400000 mstatus=00001888 masked_samples=8 traps=1 returns=1 expected_pc=80000050 actual_mepc=80000050<br>IRQ_COV timer=0 external=0 software=0 fast0=0 fast6=1 mie_entry_clear=1 mie_return_restore=1 |
| external | requirement_failure | F3_FINAL case=external mip=00000800 mie=00000800 mstatus=00000008 masked_samples=8 traps=0 returns=0 expected_pc=80000064 actual_mepc=00000000<br>IRQ_COV timer=0 external=0 software=0 fast0=0 fast6=0 mie_entry_clear=0 mie_return_restore=0 |
| software | requirement_failure | F3_FINAL case=software mip=00000008 mie=00000008 mstatus=00000008 masked_samples=8 traps=0 returns=0 expected_pc=80000064 actual_mepc=00000000<br>IRQ_COV timer=0 external=0 software=0 fast0=0 fast6=0 mie_entry_clear=0 mie_return_restore=0 |
| priority | requirement_failure | F3_FINAL case=priority mip=00000808 mie=00000888 mstatus=00001880 masked_samples=8 traps=1 returns=0 expected_pc=80000050 actual_mepc=80000050<br>IRQ_COV timer=1 external=0 software=0 fast0=0 fast6=0 mie_entry_clear=0 mie_return_restore=0 |
| negative mepc oracle | expected_checker_failure | F3_FINAL case=timer mip=00000000 mie=00000080 mstatus=00001880 masked_samples=8 traps=1 returns=0 expected_pc=80000050 actual_mepc=80000050<br>IRQ_COV timer=1 external=0 software=0 fast0=0 fast6=0 mie_entry_clear=0 mie_return_restore=0 |
| F1 regression | pass | IRQ_COV timer=0 external=0 software=0 fast0=0 fast6=0 mie_entry_clear=0 mie_return_restore=1 |
| F2 illegal regression | pass | IRQ_COV timer=0 external=0 software=0 fast0=0 fast6=0 mie_entry_clear=0 mie_return_restore=1 |
| F2 ebreak regression | pass | IRQ_COV timer=0 external=0 software=0 fast0=0 fast6=0 mie_entry_clear=0 mie_return_restore=1 |
| F2 load regression | pass | IRQ_COV timer=0 external=0 software=0 fast0=0 fast6=0 mie_entry_clear=0 mie_return_restore=1 |
| F2 store regression | pass | IRQ_COV timer=0 external=0 software=0 fast0=0 fast6=0 mie_entry_clear=0 mie_return_restore=1 |

Four positive cases (timer, timer-late, fast0, fast6) pass; external and software fail enabled service; priority fails cause selection (MTIP observed instead of required MEIP). The negative mepc run is an intentional checker failure. F1 and four F2 retained regressions pass. Required MEIP > MTIP > MSIP policy remains failing.

## Coverage and artifacts

Timer and timer-late full reports: functional covergroup 7/72 (9.72%); monitor implementation code coverage 42/84 (50.00%), distinct from functional bins; DUT toggle 562/1892 (29.70%) timer and 566/1892 (29.92%) late. Timer irq_mask_checks 1/35 (2.86%); timer-late 0/35. The metrics report confirms those DUT toggle counts; DUT top-level block/expression are n/a (inspect child instances for those metrics). Do not substitute testbench or monitor code coverage for DUT/functional coverage.
External/software/priority report status and detailed report figures are recorded per run in F3_AUDIT.json and retained files. Iteration runs lack detailed HTML/code_details where expected by mode; summary reports are available. Negative mepc has no coverage reports by design.

No reportable run is missing functional_summary.txt, code_summary.txt or metrics_summary.txt. Summaries are complete. Positive simulations exit zero; requirement and intentional-negative simulations exit nonzero. IMC reporting succeeds for reportable runs; successful report generation does not change a failed functional verdict. Per-command exits are recorded in JSON; no infrastructure errors were reported. No remote collection was needed.


## Primary review and traceability

Primary review checked the full timer metric headers and priority summary, corrected
the distinctions above, and recomputed all current source hashes. Retained records
are unchanged. [Source-backed verification diagram](docs/diagrams/core_trap_architecture.md)
([validated spec](docs/diagrams/core_trap_architecture.spec.json)) identifies the path.
Baseline and modified input hashes are recorded in [F3_MATRIX.json](F3_MATRIX.json).
No fresh simulation or SSH transfer was required.
