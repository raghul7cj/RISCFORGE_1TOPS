# F02-WB-01: repeated GPR write-enable during memory wait

Status: OPEN. No RTL changes or checker relaxation. This prevents claiming a clean
F0.2 pass. Diagram: [core verification path](docs/diagrams/core_trap_architecture.md).

## Expected and observed behavior

The existing scoreboard expects one physical nonzero-GPR effect per semantically
executed write. The ordinary F0 sequence is LUI x1; ADDI x2,x0,90; SW x2,0(x1);
ADDI x3,x0,1; ADDI x3,x3,1; terminal JAL. With three wait edges on SW:

| Sample | WB PC | valid | retired | RF enable | Destination/data | LSU req/stall |
|---|---|---|---|---|---|---|
| cycle 5 (95 ns) | 80000000 | 1 | 1 | 1 | x1 / 80001000 | 0 / 0 |
| cycle 6 (105 ns) | 80000004 | 1 | 0 | 1 | x2 / 0000005a | 1 / 1 |
| cycle 7 (115 ns) | 80000004 | 1 | 0 | 1 | x2 / 0000005a | 1 / 1 |

The second observed x2 write attempt fails the scoreboard at 115 ns. The payload is
identical, so this trace does NOT demonstrate wrong final GPR data, an extra retired
instruction, a ghost store, or an architectural ISA violation. It demonstrates the
physical-write exactly-once contract is not satisfied. Simulation terminates via
$fatal on the second observed attempt; no claim is made about its subsequent NBA.

## Reproduction and retained evidence

Run core-trap-f02-wb-wait.json through Invoke-VlsiRun with -Final -NoThrow, or
`pwsh -NoProfile -File Verification/tb_core_trap_lean/run_f02.ps1 -Case wb-wait -Final`.

[Full trace and failure](../artifacts/vlsi_auto/core-trap-f02-wb-wait_20261113T082726Z_3fdac335/results/simulation.log),
[waveform directory](../artifacts/vlsi_auto/core-trap-f02-wb-wait_20261113T082726Z_3fdac335/results/waves.shm/).
Source hashes and exact command are retained in that run's job/plan files and F02_MATRIX.json.

## Source evidence and hypothesis

In riscv_core/rtl/top.v, instr_retired_W excludes a held MEM/WB packet via
mem_stall_out. RegWriteW_gated excludes invalid/exception/MRET but does not exclude
that memory hold. memory_cycle preserves the WB packet during core_stall_gated.
decode_cycle forwards RegWriteW to Register_File.WE3, which is sampled at posedge.
These inspected assignments explain consecutive RF write-enable assertions while
retirement remains zero. CSR gating has a similar structural expression, but CSR
repetition has not been stimulated or established by this experiment.

## Next engineering decision

Decide whether physical RF writes must be commit-qualified, or idempotent replay
is an explicitly approved implementation contract. This is not a coverage waiver.
A candidate change should be reviewed for forwarding, stalled WB, flush and trap
priority; do not apply a blanket mask without that analysis. Preserve this failing
scenario and rerun it unchanged against any candidate. F1 must retain a separate
architectural retirement and physical-effects view, including CSR and accepted stores.
