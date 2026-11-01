# Stage 1 Xcelium checker corrected rerun — 2026-10-18

Run ID: `20261018_stage1_xcelium_05`
Verdict: **FAIL**. Compilation and elaboration passed; the simulation reached the firmware activity gate and failed there. No Stage 1 PASS or P0 closure is claimed.

## Run configuration

- Xcelium 24.09-s001; `stage1_hello`; WARM boot; seed 1; 1,000,000 cycle watchdog.
- Remote run directory: `/home/iiita/Documents/raghulcj/p0_runs/20261018_stage1_xcelium_05_exec01`.
- The WARM sequence boundedly waits for synchronized hard reset and `warm_boot_q=1` before loading SRAM and releasing soft reset.
- No checker was disabled.

## Final result

At 68,885 ns the testbench reported `FW_ASSERT_FAIL`, firmware error `0x1002` from the activity gate: verified MMIO reads were 4, below the declared minimum of 6. The mailbox reported `proof_mmio_writes=0x00010001`.

The monitor dump reports 7 AXI reads and 4 AXI writes, while the APB monitor reports only 5 transfers, all on I2C slot 0. The log also contains Timer 0 MMIO traffic. This counter and monitor discrepancy remains unresolved and is not treated as a pass.

The run’s earlier checker failures were addressed in verification infrastructure: the I2C prescaler predictor reset now matches the RTL’s zero reset value, and the APB path scoreboard recomputes its expected slot for each transfer. The next failure is independent of those two checker issues.

## Snapshot identity and evidence

- Source archive SHA-256: c90f8fe9f3ccc190fa8acd25fa9a948e6d58c51fb9cc6172deca028c6fdccff5
- Source files hashed: 435; per-file SHA-256 records are in `inputs/source_hashes.json` and names in `inputs/snapshot_files.txt`.
- Xcelium monitor overlay SHA-256: 4ca57be97dd59b1f6d21f12adedac140d8f1c220467f1c2f10a448c33d85eb67
- `results/` contains command arguments, manifests, complete compile/simulation logs, effective/original filelists, firmware ELF, generated memory images, counters, and preflight checks.
- Runs 01–04 remain in sibling artifact folders with their own evidence.
