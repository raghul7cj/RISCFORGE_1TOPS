# Stage 1 Xcelium rerun — 2026-10-18

Run ID: 20261018_stage1_xcelium_02
Status: prepared; remote Xcelium run pending.

This run starts from a new frozen source archive derived from the previous run's source tree, with only these source changes applied before archiving:
- iscv_core/rtl/top.v: moved the existing 	rap_commit_cause wire declaration above its first use; no logic or connectivity change.
- Verification/infrastructure/tb/soc_tb_top.sv: WARM reset sequence now releases hard reset, holds soft reset asserted for four clocks, preloads SRAM, then releases soft reset.

At run reconstruction, f_monitors_xcelium.sv is applied as the same Xcelium-only class declaration-order overlay used in the prior run. No checker is disabled.

Snapshot SHA-256: $snap
Monitor overlay SHA-256: $monitor

The prior run 20261018_stage1_xcelium_01 remains intact. un_stage1.py, REPRODUCE.sh, inputs, logs, command records, and results are retained in this folder after execution.
