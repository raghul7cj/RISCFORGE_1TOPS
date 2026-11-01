# Stage 1 Xcelium warm reset rerun — 2026-10-18

Run ID: 20261018_stage1_xcelium_04
Status: prepared; simulation pending.

This run adds a bounded WARM setup sequence: release hard reset, sample hard_rst_sync_n on negedges, then sample the bootloader's warm_boot_q until it proves the soft reset was observed. If either signal does not reach the expected state within its bound, the testbench fails with a clear $fatal. SRAM preload occurs only after warm reset observation and before soft reset release.

Timeout-only diagnostic reporting from run 03 remains. No DUT logic or checker behavior is changed.

Snapshot SHA-256: $snap
Monitor overlay SHA-256: $mon

Prior attempts and logs are retained in sibling run folders 01 through 03.
