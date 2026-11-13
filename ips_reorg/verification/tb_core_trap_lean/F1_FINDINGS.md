# F1-EXC-01: younger store changes memory on ECALL commitment

Status: OPEN, reproduced. No RTL change, skipped assertion or expectation relaxation.
This is a functional precise-exception squash failure, distinct from F02-WB-01's
idempotent repeated RF write-enable. Diagram: [verification path](docs/diagrams/core_trap_architecture.md).

## Distinguishing program

The dense case contains ECALL at 0x8000001c immediately followed by SW x10,0(x1)
at 0x80000020. x1=0x80001000, x10=0x5a. That store is younger than the exception
and must not affect memory until AFTER the handler updates mepc and MRET resumes it.
No data memory writes precede ECALL in this program.

At 165 ns the log records simultaneously:

- trap valid, cause 11, trap PC 0x8000001c, handler target 0x80000100;
- memory write request at 0x80001000, data 0x5a, stall=0, error=0.

The unchanged common a_wb_kills_memory assertion fails on that edge. The final
post-edge snapshot shows app0=0x5a, saved handler signatures still all zero and
observed MRET count zero. Thus actual SRAM mutation occurred before the handler
ran; this is stronger evidence than a request-only failure. mepc/cause/status did
capture ECALL state (0x8000001c / 11 / 0x1880), but that does not undo the store.

[Full failing log](../artifacts/vlsi_auto/core-trap-f1-adjacent-store_20261113T141531Z_73e27421/results/simulation.log)
and [SHM waves](../artifacts/vlsi_auto/core-trap-f1-adjacent-store_20261113T141531Z_73e27421/results/waves.shm/)
are retained with source hashes, detailed IMC and HTML reports. The source set is
identical to the passing complementary smoke (see F1_MATRIX.json).

## Source-backed explanation and remaining uncertainty

memory_cycle gates lsu_mem_req with valid_M and absence of propagated/alignment
exceptions, but not WB redirect. Its current MEM packet can be a younger, untagged
store while the older exception commits at WB. hazard_unit asserts FlushM on WB
redirect; clearing EX/MEM on the commit edge is too late to prevent the pre-edge
request from being accepted by a zero-wait memory model. This boundary explains
the observed event. The upstream exception-flush chain also needs review before
choosing a correction. Do not assume that request gating alone resolves every
RF/CSR/interrupt ordering case.

The companion RF-first smoke runs the full handler/MRET path successfully and
keeps handler fall-through poison memory zero. It isolates those behaviors; its
pass does not waive the dense-case failure.

## Reproduction and next engineering step

`pwsh -NoProfile -File Verification/tb_core_trap_lean/run_f1.ps1 -Case adjacent-store -Final -NoThrow`

Review the precise commit/kill contract, then implement a separately authorized RTL
correction and rerun this exact regression unchanged. Preserve ordering of older
legal effects while preventing younger RF/CSR/memory effects. The current verification
work neither edits RTL nor silently suppresses writes in the memory responder.
