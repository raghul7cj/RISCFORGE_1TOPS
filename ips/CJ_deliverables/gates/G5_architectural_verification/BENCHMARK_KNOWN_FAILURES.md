# Preserved runtime findings

Date: 2026-11-04. These findings come from actual XSim execution of the current full SoC and the pinned benchmark ports. They are not signoff results. The infrastructure task did not change RTL or expected arithmetic/CRC answers.

## Arithmetic smoke: three failed checks

Final run: `smoke_20261104T065353Z_7108f0a2`.

- Firmware reached terminal FAIL after 1,841 observed post-boot cycles.
- `validation_errors = 3`; first error `0x00001001`.
- Expected accumulation: 2980. Observed accumulation: 1016.
- The multiply and divide/remainder checks also reported failure. Counter liveness/monotonic checks were set; this does not qualify counter accuracy.
- No trap was observed. The host rejected the result and did not emit a benchmark estimate.

The reference constants follow ordinary 32-bit arithmetic: `0x6789 * 0x12345 = 1976345325`; `0x12345678 / 0x1357 = 61688`, remainder 2608. The accumulation's expected value is computed from the source loop and is preserved unchanged.

The existing MDU completion-validity and stall concerns are relevant hypotheses. This run does not by itself prove which RTL path caused the wrong values. A distinguishing experiment should trace one multiply/divide result from completion through EX/MEM validity, WB validity and the dependent register read, then repeat with a preceding memory wait. Fixing that logic requires a separate design task.

## CoreMark: misaligned store during initialization

Final run: `coremark_20261104T065419Z_d28e58b8`.

- One iteration requested; validation seeds `0x3415, 0x3415, 0x66`.
- Trap cause 6 (store address misaligned), PC `0x00010fa4`, trap value `0x0002092d`.
- The disassembly identifies `sw zero,0(a1)` in `core_list_init`. A `divu` occurs two instructions earlier.
- The timing phase was still zero. No timed benchmark result or CRC validation was established.

The unaligned pointer must be traced back to its producer and call/MDU dependencies. The trap is preserved; neither pointer alignment nor CRC expectations were changed to obtain a pass.

Even after a future functional correction, the one-iteration image preserves upstream's minimum-duration error. It cannot yield a compliant published CoreMark score. The build-local result hook and its source changes are disclosed in the build metadata and firmware guide.

## Dhrystone: access fault during numeric output

Final run: `dhrystone_20261104T065432Z_8cffc712`.

- Ten iterations requested.
- Trap cause 5 (load access fault), PC `0x00010088`, trap value `0x00040231`.
- The disassembly identifies `lbu a3,0(a3)` in the freestanding `emit_unsigned` formatter. That address is outside the SoC DSRAM range.
- The timing phase was still zero. The benchmark loop and final-state validation were not established.

The formatter uses integer divide/remainder to select digits. Incorrect arithmetic or a register dependency is a hypothesis, not a completed diagnosis. The formatter's inputs and arithmetic results need a trace before deciding whether a port or core correction is appropriate.

## Counter diagnostic: PASS with a limited meaning

Final run: `counter_probe_20261104T065406Z_9f3abc11`.

- The program reached terminal PASS with zero validation errors and no trap.
- Raw snapshot delta: 38 core cycles and 24 `minstret` increments.
- The body contains eight explicit instructions; the window includes counter-reader and wrapper overhead.
- The TB recorded 68 WB-valid/memory-stall overlap cycles across the entire run. That broad observation window is not the same interval as the eight-instruction body.

This result establishes transport, successful execution of this diagnostic, and live monotonic reads. It does not establish exact unique retirement accounting, a measured CPI, or general core correctness.

## Infrastructure issues corrected during integration

Initial failures are retained in `docs/evidence/` and earlier `runs/` records. Corrections included metadata-list traversal, sparse-image bounds/duplicate addresses, binding ELF identity to actual preload bytes, staging the consumed firmware/ROM, XSim batch-launch argument handling, observed RUNNING before terminal status, waiting for complete firmware failure details, publishing the probe's raw samples, and rejecting impossible counter deltas or a mismatched clock declaration.

The first watchdog negative fixture supplied only one NOP. The TB deliberately zero-fills the rest of instruction SRAM, so execution correctly trapped on the next zero word. The fixture was corrected to a full NOP image, and the actual watchdog then rejected the hang. Both attempts are retained; no design behavior or expected watchdog result was changed.

## Next engineering work

Use the retained ELF, disassembly and raw trap fields to form and test a bounded RTL/runtime hypothesis. Keep these runs as failing baselines. Re-run the same workload and source identity after an approved correction; add the correction's directed check before widening the campaign. Counter accuracy and any published-score campaign remain separate qualification tasks.
