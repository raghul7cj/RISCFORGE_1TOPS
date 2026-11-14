# F4 execution evidence

Status: the scoped F4 matrix is complete and passing: 40/40 Full cases,
9/9 regressions, and one expected negative-checker failure. The 49 positive
runs were merged successfully. Coverage closure and full SoC signoff remain open.

The [plan](F4_PLAN.md) defines the platform scope, independent expected values and
matrix. The [source-backed diagram](docs/diagrams/f4_vectored.md) describes the
fixture and check path. Source identities and per-run outcomes are retained in
the campaign ledgers; historical F3 records are not overwritten.

```mermaid
flowchart LR
  P["Fixture program image"]:::present
  T["Independent expected target"]:::present
  S["Trap packet and state assertions"]:::present
  P -->|"program construction"| T
  T -->|"expected target and mtvec"| S
  classDef present fill:#e8f1ff,stroke:#2b6cb0,color:#111
  classDef planned fill:#fff8e1,stroke:#b7791f,stroke-dasharray:5 3,color:#111
  classDef absent fill:#fdecea,stroke:#c53030,stroke-dasharray:2 2,color:#111
  classDef uninspected fill:#f2f2f2,stroke:#888,stroke-dasharray:2 4,color:#444
```

Source: `cd0660db866654e5a8bc687d2b8b9280e10b9ad2` plus inspected file hashes in the
[validated diagram spec](docs/diagrams/f4_vectored.spec.json). The diagram shows
the fixture/check path; simulation evidence is in the ledgers below.

## Smoke checkpoint

[Completed campaign](artifacts/f4_Smoke_20261114T080113Z_a298386d/campaign.json).
All four cases have passing Xcelium checks, reported IMC coverage, physical mtvec
readback and MODE witnesses. No source drift was detected.

| Case | Written MODE | Stored mtvec | Checked trap target |
| --- | ---: | --- | --- |
| Timer, Direct | 0 | 0x80000100 | 0x80000100 |
| Timer, Vectored | 1 | 0x80000101 | 0x8000011c |
| ECALL, Vectored | 1 | 0x80000101 | 0x80000100 |
| Timer, reserved MODE | 3 | 0x80000100 | 0x80000100 |

The original incomplete launch and retry directories remain preserved. The
collector recovered the retained upload and collected its result before resuming
the remaining cases. Transport failure was not reported as a functional failure.

## Preserved first Full attempt

[Initial Full campaign](artifacts/f4_Full_20261114T081534Z_2063d25c/campaign.json)
passed Direct timer/fast0, then failed `a_pending` for fast1 at 195 ns:
`mip=0`, expected pending mask `0x00020000`. Source hashes were stable.
Static inspection of `top.v` (edge_mode=0x0002, event_mode=0x1fe9) and
`irq_gateway.pend_o` established that fast1/I2C and fast3/UART pass through as
levels. The new F4 stimulus had incorrectly pulsed all fast inputs for one cycle.

The parent corrected only stimulus duration: those two levels now stay high
through entry and deassert off-edge. The pending/masking assertions and expected
results are unchanged. Original logs and failed ledger are retained. The changed
fixture requires a fresh Full/Regression campaign; the prior passing rows cannot
be merged as current-source evidence.

## Completed current-snapshot evidence

| Suite / artifact | Verdict |
| --- | --- |
| [Full ledger](artifacts/f4_Full_20261114T150027Z_1ae604e1/campaign.json) | 40/40 pass |
| [Regression ledger](artifacts/f4_Regression_20261114T151424Z_b0dbd2e9/campaign.json) | 9/9 pass |
| [Negative ledger](artifacts/f4_Negative_20261114T101839Z_54653384/campaign.json) | Expected named SVA target-mismatch failure; not a simulation pass |
| [Merge summary](artifacts/f4-merge_20261114T151734Z_27b4badf/merge-summary.json) | IMC exit 0; exactly 49 positive runs |
| [Merged UCM/UCD database](artifacts/f4-merge_20261114T151734Z_27b4badf/merged) | Model and test data retained locally |
| [Primary evidence review](F4_REVIEW.json) | No findings; all input hashes match the executed/merged snapshot |

Primary review checked every Full log against the configured source and MODE:
exactly one F4_PASS, physical readback=1, correct normalized mtvec, correct trap
packet cause/target, hardware MODE hit and MRET witness. All 13 active IRQ causes
were checked in both modes, including held I2C/UART levels. Five synchronous
exception causes target BASE in both modes. Reserved MODE 2/3 read back as Direct.
Timer-late was checked in both modes. The negative run changes only the expected
target by +4 and must fail the named SVA; its database is excluded from the merge.
No source drift or uploaded-input mismatches were recorded. Earlier incomplete
attempts and the original stimulus failure remain preserved.

## Coverage evidence and remaining bins

[Covergroup summary](artifacts/f4-merge_20261114T151734Z_27b4badf/covergroup_summary.txt)
records **60/66 bins (90.91%)**. The separately reported covergroup average is
71.88%. [Detailed functional report](artifacts/f4-merge_20261114T151734Z_27b4badf/functional_details.txt)
records **trap_commits 56/56 (100.00%)** and **trap_status 4/10 (40.00%)**. All 18
supported cause bins, both MODE bins and their 36 cause-by-MODE crosses are 100%
closed. MEIP and MSIP cause bins and their crosses were removed from the covergroup
as those interrupt inputs are tied low at the standalone SoC boundary (no PLIC/CLINT).
The 6 remaining uncovered bins are in `trap_status`: masked-entry, three MPIE-entry
transitions (`changes[0]`, `changes[2]`, `changes[3]`), restore-disabled, and
return-MPIE set-from-zero. No refinement files were applied.

[Merged DUT metrics](artifacts/f4-merge_20261114T101917Z_7290c8b3/metrics_summary.txt)
show top-instance toggle **1074/1892 (56.77%)**; its block/expression entries are
n/a and this row is not aggregate DUT statement coverage. Child instances retain
unhit code: for example the arbiter block score is 52/56 and Execute expression
score is 8/12. Monitor implementation code coverage is separate from functional
bins. [Full code details](artifacts/f4-merge_20261114T101917Z_7290c8b3/code_details.txt)
and [HTML report](artifacts/f4-merge_20261114T101917Z_7290c8b3/code_html/index.html)
are retained for closure work. The measured coverage is not closed.

## Signoff matrix

| Obligation | Evidence / disposition |
| --- | --- |
| Direct/Vectored destinations for causes 7 and 16–27 | Passed, all 26 source/MODE combinations |
| Synchronous exceptions to BASE in either mode | Passed, five causes × two modes |
| mtvec MODE/readback and reserved MODE fallback | Passed; physical CSR readback checked |
| Precise trap packet, saved CSRs, redirect edge and MRET | Passed within this bounded zero-wait fixture |
| Global masking/pending and level/event stimulus | Passed for the exercised source/MODE cases |
| Misaligned load/store request suppression | Passed in both modes; shared assertion retained |
| Existing F1/F2/F3 behavior after checker changes | Nine regressions passed |
| Wrong vector destination detected | Expected named negative failure observed |
| Full code/functional coverage closure | Open; unhit bins/code retained |
| Real SoC peripheral routing | Not exercised; core IRQ pins injected |
| Simultaneous class priority and round-robin fairness | Not exercised by this single-source F4 matrix |
| Memory/MDU stall robustness and universal latency | Not established by this zero-wait campaign |
| Unsupported-source CSR contract and negative MSIP-write tests | Separate obligation; not closed by F4 |
| Issue #30 ghost-store correction and regression | Open; no production RTL correction in this task |

## Full signoff limits

F4 execution and its retained evidence are complete within the matrix above.
Issue #30 remains a full-signoff blocker. No blanket architectural compliance,
real-peripheral integration, fairness, stall robustness or coverage closure claim
is made. Historical F3 external/software/standard-priority failures retain their
original verdicts and scope; they were not relabeled as passing.

## Transport history

Intermittent configured SSH/PSCP closures interrupted launch and collection.
Earlier [diagnostics](artifacts/f4_infra_diag_20261114/diagnostic.txt),
[retry transcript](artifacts/f4_infra_diag_20261114/retry.txt) and
[combined file-mode probe](artifacts/f4_infra_diag_20261114/connection_probe_run.log)
are retained. Matching host/boot identities and failed setup attempts did not
establish storage cleanup or a server restart. Subsequent recovery completed the
existing campaign; the earlier blocked checkpoints are superseded by the final
ledgers and primary review above.
