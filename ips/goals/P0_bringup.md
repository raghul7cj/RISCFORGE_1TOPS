# P0 Bring-up Goals

## Objective

Produce one reproducible end-to-end SoC run and record its identity. P0 establishes that the harness can build the intended design, deliver stimulus to the DUT, and retain the run evidence. It does not claim broader functional verification or sign-off.

## Entry criteria

- No predecessor phase is required.
- Record the RTL tree identity before running, using the identity recipe in `RISCFORGE_Verification_Plan_RevB.docx`, section 21, Table 21.10.

## Goals and acceptance criteria

### P0-G1 — Harness integrity (G0)

Pass only when all of the following are true:

- `unresolved_modules == 0` against the canonical module set.
- `extra_modules == 0` against the canonical module set.
- The simulator/tool version is pinned and recorded.
- The artifact write test passes.
- Build and elaboration logs, plus the filelist diff report, are retained.

### P0-G2 — DUT activity (G1)

In the P0 boot partition, record and require:

- `instructions_retired > 0`
- `axi_transfers > 0`
- `apb_transfers > 0` 
- `attestation_words_written > 0`

Retain the counter block with the verdict record. A run with no activity is a failure, not a pass.

### P0-G3 — Reproducible run identity

Archive enough information to rerun the same test, including the RTL SHA-256, filelist SHA-256, random seed, plusargs, pinned tool version, exact run command, and the resulting logs and verdict. The first four fields form the plan's reproduction subset.

## Exit criteria

P0 is complete when one end-to-end boot run passes G0 and G1, the run identity is recorded, and its logs, filelist diff, counters, and verdict are retained together. No further design correctness claim is made at P0 exit.

## Source

`RISCFORGE_Verification_Plan_RevB.docx`: sections 6 and 21; Tables 6.1, 21.10, and 21.3.
