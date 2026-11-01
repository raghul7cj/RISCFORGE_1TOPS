# Stage 1 Xcelium diagnostic rerun — 2026-10-18

Run ID: 20261018_stage1_xcelium_03
Status: prepared; diagnostic simulation pending.

This run inherits the Stage 1 source updates and runner correction from run 02. The testbench adds a timeout-only diagnostic line reporting external/synchronized resets, bootloader reset/state/warm flag, boot_done, core PC, and first two ISRAM words. It does not change checkers, verdict logic, or DUT behavior.

Snapshot SHA-256: $snap
Monitor overlay SHA-256: $mon

Run 02 attempts and evidence remain in the sibling folder 20261018_stage1_xcelium_02.
