# Evidence ledger

## F0 â€” 2026-11-13

- **DUT/build:** `top` in `riscv_core/rtl/top.v`; minimal dependency manifest `core-trap-f0.json`; Xcelium 24.09-s001 and IMC 24.09 on configured `ssh vlsi` transport.
- **Exact command:** `. "$env:USERPROFILE\.t3\tools\vlsi\Vlsi.ps1"; . "..\scripts\vlsi\VlsiRun.ps1"; Invoke-VlsiRun -Manifest "Verification/tb_core_trap_lean/core-trap-f0.json" -NoThrow`
- **Run:** `core-trap-f0_20261113T055957Z_6bcec9b0`; functional PASS; coverage REPORT generated; output hash validation passed. Completion marker: `F0_PASS commits=4 stores=1`. Simulation log reports 3/3 assertion constructs and no assertion failure.
- **Scope:** RESET_PC `0x80000000`; LUI/ADDI/SW/ADDI/ADDI. Checks PC/instruction stream, four GPR write effects, exactly one accepted word store at `0x80001000`, full byte enable, and `0x0000005a` signature.
- **Code coverage:** DUT aggregate toggle: 13.16% (249/1892). The `dut` wrapper has no scored block or expression items; use nested instance rows in `metrics_summary.txt` for those metrics. The testbench aggregate is block 82.46% (47/57), expression 65.96% (31/47), toggle 19.96% (99/496). At the core subinstances: IRQ gateway block 3/3, arbiter 24/56, fetch 7/7, decode 6/7; full per-instance/per-metric detail is in `metrics_summary.txt` and `code_details.txt`. This short F0 result is not coverage closure.
- **Artifacts:** [run directory](../artifacts/vlsi_auto/core-trap-f0_20261113T055957Z_6bcec9b0/), including source manifest/hashes, Xcelium log, SHM waveform, UCM/UCD database, IMC summary/detail and HTML report.
- **Known limits:** no ECALL/traps/CSR expectations, no load, injected waits/errors, mutation campaign, or whole-core signoff. Functional bins are not separately reported. A previous failed compile attempt remains in the artifact directory and was not overwritten. The final results archive was collected with `Invoke-VlsiRun -Collect -RunDirectory` after transfer completion; source hashes and archive validation passed.

## Next

F1 is the next planned test stage, not part of this F0 result: implement and validate precise ECALL entry, handler, mepc advance, MRET, poison-effect suppression and resumed signature checks before making trap signoff claims.



## Reviewed F0 revision — 2026-11-13

Parent review tightened the checker: ordered PC/destination/value tuples for every
nonzero GPR effect, duplicate-store rejection, unknown-control/data rejection,
terminal WB required for completion, parameter-derived LUI and reset-PC preload
placement, time-zero preload race removed, all DUT taps centralized. IMEM now
checks configuration, honors nonzero reset offset, and fails out-of-range requests.
No RTL changed. Historical runs above remain evidence for their original snapshots.

| Run | Result | Decisive evidence |
|---|---|---|
| [default](../artifacts/vlsi_auto/core-trap-f0_20261113T060540Z_720befa5/results/simulation.log) | PASS | F0_PASS commits=4 stores=1, completion at 145 ns |
| [reset offset](../artifacts/vlsi_auto/core-trap-f0-offset_20261113T060540Z_c234a2ba/results/simulation.log) | PASS | Same checks with RESET_PC=0x80000040 within IMEM |
| [intentional checker fault](../artifacts/vlsi_auto/core-trap-f0-negative_20261113T060540Z_4390377d/results/simulation.log) | Expected FAIL | Corrupted expected x2; ordered GPR mismatch index=1 at 105 ns, simulator exit 2, runner failed |

All three archives retrieved with zero input/output hash mismatches. Positive
runs generated IMC reports; coverage is not closure. Latest default DUT aggregate
toggle is 13.27% (251/1892); fetch block 7/7, instruction controller block 3/3 and
expression 6/6. Full per-instance detail remains in metrics_summary.txt/code_details.txt.
There are one assert property and two cover properties; three elaborated assertion
constructs does not mean three independent assertions. Hardware fetch/store counters
are mandatory for completion. No separate functional-covergroup report is claimed.

Run default with `pwsh -NoProfile -File Verification/tb_core_trap_lean/run_f0.ps1`.
Offset and negative manifests use the same Invoke-VlsiRun command with their respective
JSON filenames. The negative manifest is deliberately expected to return failure;
never include it among ordinary passing regressions without an expected-failure harness.
The injected fault changes only the checker expectation, not stimulus or DUT state.

Limits: this is a bounded F0 stream, not a general ISA reference model. DMEM byte
lanes, load/wait/error behavior, reset mid-flight, traps, squash and IRQs require
later tests. No formal proof or whole-core signoff follows from this simulation.

## F0.1 semantic predictor â€” 2026-11-13

- **Initial integration run:** `core-trap-f0_20261113T063048Z_53e336f5` failed because the model incorrectly treated LUI immediate bits as funct3; preserved, hashes validated. The corrected run `core-trap-f0_20261113T063213Z_fc1404b5` simulated `F0_PASS instructions=6 gpr=4 stores=1` at 145 ns. Runner marked it failed only because its old pass regex expected `commits=4 stores=1`; this is not a simulation failure.
- **Second legal program:** `core-trap-f0-second_20261113T063354Z_71e99eab` passed through runner and IMC. It executed 7 instructions, 4 predicted GPR writes, and 2 accepted stores using dependent ADDI operations, negative immediate -5, different destinations, and a second word store. Input/output hash mismatches: zero; 136 output files verified.
- **Predictor:** event counts derive from semantic execution, from x0-only known initial register state. Expected queues are produced before reset release. Retirement uses `instr_retired_W`; physical GPR attempts and accepted stores have independent checks. SRAM/reference signature checks follow accepted writes.
- **Coverage:** IMC report generated for the second program; this is short directed simulation evidence, not whole-core closure. No functional covergroup report is claimed. The bench retains the aligned-PC assertion and fetch/store cover properties.
- **Pending:** rerun baseline with revised marker, reset offset, and expected-failure checker injection; inspect their exact logs and hashes before claiming F0.1 complete.

## F0.1 final-source validation â€” 2026-11-13

All three positive runs below used the final predictor, reformatted canonical responders, and identical checking logic. Transfer validation reported zero input/output hash mismatches and 136 retrieved output files per run. Each run generated Xcelium waveforms and IMC reports.

| Scenario | Run ID | Result | Evidence |
|---|---|---|---|
| Default | `core-trap-f0_20261113T063813Z_a7b44705` | PASS | `F0_PASS instructions=6 gpr=4 stores=1`, 145 ns |
| Reset offset (+0x40) | `core-trap-f0-offset_20261113T063906Z_63b936c3` | PASS | Same scenario checks at parameterized reset location |
| Different legal program | `core-trap-f0-second_20261113T064048Z_289f92d7` | PASS | 7 instructions, 4 GPR effects, 2 stores |
| Checker-negative | `core-trap-f0-negative_20261113T064145Z_f3b7f975` | EXPECTED FAIL | Exit 2; GPR mismatch index 0, expected `80001001`, actual `80001000`, 95 ns |

The negative run mutates only the predicted expected GPR copy after semantic execution. It is not a passing run and its coverage is not combined with positive runs. The retained failed offset compile `core-trap-f0-offset_20261113T063622Z_7c8963c8` documents the unsupported `-P` option; corrected `+define+F0_OFFSET` run above passed. Initial predictor typo and stale pass-regex integration artifacts are also retained above.

Default positive whole-DUT aggregate toggle coverage is 13.27% (251/1892). Nested instance rows in `metrics_summary.txt` carry useful block/expression results; for example Fetch block 7/7 and instruction controller block 3/3, expression 6/6. These short runs demonstrate execution and assertion/cover activity, not full-core signoff. The bench has one assertion property and two cover properties; these are not independent coverage closure claims. Broader F0.2 protocol hold/flush/wait assertions remain future work.

- **Final event-utility source confirmation:** `core-trap-f0_20261113T064315Z_ad32f68d` PASS, `F0_PASS instructions=6 gpr=4 stores=1`, 145 ns; IMC reported; zero hash mismatches and 136 output files verified. This is the final common-package source snapshot after adding reusable four-state event comparison helpers.


## Review correction work — 2026-11-13 (incomplete)

The reference execution loop now fetches through its independent model PC, with
alignment, image-range and step-limit guards. Program instructions are placed at
the parameterized reset offset. Decode observations are checked against the padded
independent image rather than retirement order, so speculative decode after a JAL
is permitted. Retirement and physical effects remain separately checked. A shared
byte-addressed reference-memory utility applies predicted SW writes in program
order; the final DUT memory check compares the final value per touched address.
Unknown accepted store payloads and accepted reads are rejected. RESET_PC is again
a parameter (F0_OFFSET selects its default), and the DBASE guard requires page
alignment for LUI-only initialization.

| Scenario | Run ID | Result | Hash status |
|---|---|---|---|
| JAL skip poison, repeated address SWs | `core-trap-f0-jal_20261113T065102Z_00a7dfe5` | PASS; 136 outputs verified | zero input/output mismatches; archive SHA-256 `4a6896c1a6924b19d265bf5d73f4014685ef8e7a00e08d90054fb8013dca6268` |
| Reset offset after fixing image placement | `core-trap-f0-offset_20261113T065413Z_823a789a` | PASS; 136 outputs verified | zero input/output mismatches; archive SHA-256 `e939fccd1dd670a70d50e027e94360af4d2ed2156095145f7369f6c155172f5f` |

The offset attempt `core-trap-f0-offset_20261113T064941Z_78357463` failed because the
model did not place the program at its absolute IMEM word offset (`RV32 unsupported
opcode xx` at `0x80000100`). It is preserved. The corrected offset run above passes.
The common bounded scoreboard extraction, complete formatted reorganization, and
final-source reruns of default/second/negative scenarios remain outstanding; this
ledger therefore does not claim F0.1 complete. Earlier results above retain their
original source identities and have not been overwritten.


The frozen-source correction matrix subsequently completed. All source inputs were
transferred and retrieved with zero input/output hash mismatches and 136 output files
verified per run. Xcelium 24.09-s001 and IMC reports were produced.

| Scenario | Run ID | Outcome | Artifact SHA-256 |
|---|---|---|---|
| Default | `core-trap-f0_20261113T065607Z_c3c7daef` | PASS; `F0_PASS instructions=6 gpr=4 stores=1` | `059b0deec0f1b4c3e2eac77bb8cefa8aafba5f6d32da5eb814e856e7ca26095b` |
| Reset offset | `core-trap-f0-offset_20261113T065413Z_823a789a` | PASS; same event counts | `e939fccd1dd670a70d50e027e94360af4d2ed2156095145f7369f6c155172f5f` |
| Existing second program | `core-trap-f0-second_20261113T065641Z_5f14115d` | PASS; 7 instructions, 4 GPR effects, 2 stores | `5e60c5a0c829daf9fd0288d1c49e5766dc920a4e96b12fd4a732fec1ada37224` |
| Forward JAL and repeated-address SW | `core-trap-f0-jal_20261113T065818Z_32341717` | PASS; 8 instructions, 4 GPR effects, 2 stores; poison GPR/store skipped | `cb7c7eb4ac9e9c955b45377d53ffe2f5d9fd7e01164b3c61f87beb5ec59084e3` |
| Store checker negative | `core-trap-f0-store-negative_20261113T065723Z_c47e26b9` | EXPECTED FAIL; exit 2 at first store check | `380a97228d66cc00615fa9890c0ae5098f8571a70765ef71812989a862faefe5` |

The negative changes a local checker-facing store event copy only. Its log reports
`F0 store mismatch index=0` at 115 ns; expected and raw physical payload display alike
because the diagnostic still prints the raw tap instead of the mutated checker copy. The
nonzero exit and mismatch are preserved. Negative coverage is not merged into positive
results. The common scoreboard extraction and requested full visual reformat remain
unimplemented, so this is evidence for the corrected predictor and memory behavior, not
completion of the entire review-correction request.

## F0.1 accepted common-scoreboard revision - 2026-11-13

This revision completes the previously outstanding common-scoreboard extraction
and readability work. Historical incomplete revisions above remain unchanged.
The common class owns all expected queues, counters, ordered comparisons and
completion drain checks. The fixture retains program selection, semantic run-ahead,
physical sampling and scenario policy. Named connections and visual code sections
separate configuration, state, connections, prediction, monitoring and assertions.

Final validation used Xcelium 24.09-s001 through the configured VLSI SSH helper.
Every row below has an identical HDL source/hash set, verified against current local
files; all transport input/output checks matched. Positive rows retained IMC reports
and waveforms. Negative rows deliberately exit 2 and are not merged into positive
coverage. The missing/extra tests did not request code coverage.

| Scenario | Outcome | Run evidence |
|---|---|---|
| Default | PASS; `F0_PASS instructions=6 gpr=4 stores=1` | [core-trap-f0_20261113T070326Z_54f5cd1f](../artifacts/vlsi_auto/core-trap-f0_20261113T070326Z_54f5cd1f/results/simulation.log) |
| Reset offset | PASS; `F0_PASS instructions=6 gpr=4 stores=1` | [core-trap-f0-offset_20261113T070326Z_a9b29c51](../artifacts/vlsi_auto/core-trap-f0-offset_20261113T070326Z_a9b29c51/results/simulation.log) |
| Dependent signed immediates | PASS; `F0_PASS instructions=7 gpr=4 stores=2` | [core-trap-f0-second_20261113T070326Z_6a4c98f0](../artifacts/vlsi_auto/core-trap-f0-second_20261113T070326Z_6a4c98f0/results/simulation.log) |
| Forward JAL, poison skip and overwrite | PASS; `F0_PASS instructions=8 gpr=4 stores=2` | [core-trap-f0-jal_20261113T070556Z_b8d5aa44](../artifacts/vlsi_auto/core-trap-f0-jal_20261113T070556Z_b8d5aa44/results/simulation.log) |
| Wrong predicted GPR | EXPECTED FAIL; `CORE_SB GPR mismatch index=0 expected=80000000/x1/80001001 actual=80000000/x1/80001000` | [core-trap-f0-negative_20261113T070556Z_cb92a319](../artifacts/vlsi_auto/core-trap-f0-negative_20261113T070556Z_cb92a319/results/simulation.log) |
| Wrong sampled store value | EXPECTED FAIL; `CORE_SB store mismatch index=0 expected=80001000/f/0000005a actual=80001000/f/0000005b` | [core-trap-f0-store-negative_20261113T070556Z_169452d5](../artifacts/vlsi_auto/core-trap-f0-store-negative_20261113T070556Z_169452d5/results/simulation.log) |
| Missing delivered store | EXPECTED FAIL; `CORE_SB undrained events retire=6/6 gpr=4/4 stores=0/1` | [core-trap-f0-missing-store-negative_20261113T070648Z_18a60e34](../artifacts/vlsi_auto/core-trap-f0-missing-store-negative_20261113T070648Z_18a60e34/results/simulation.log) |
| Extra delivered store | EXPECTED FAIL; `CORE_SB extra store address=80001000` | [core-trap-f0-extra-store-negative_20261113T070648Z_b57ec477](../artifacts/vlsi_auto/core-trap-f0-extra-store-negative_20261113T070648Z_b57ec477/results/simulation.log) |

[F0_1_FINAL_MATRIX.json](F0_1_FINAL_MATRIX.json) retains common source hashes,
archive hashes and per-run transfer/report status. Every final simulation exit code
and decisive diagnostic was inspected. Four positive configurations passed, and
four opt-in checker self-tests failed at their intended checks. The missing store
fails at final drain (stores=0/1); the duplicate fails immediately as an extra store.
The wrong-store diagnostic now prints the mutated checker-facing event correctly.

The default run reports DUT aggregate toggle 13.27% (251/1892); fetch block 7/7 and
instruction controller block 3/3, expression 6/6. These are measured coverage items,
not full-core closure. One alignment assert property and two hardware cover
properties remain; protocol hold/flush/wait assertions are F0.2, not completed here.
Waves capture static DUT/model signals; Xcelium warns that default -all probing
excludes dynamic class objects. Scoreboard expected/actual diagnostics remain in logs.

Reference memory is initialized independently and all configured physical SRAM
words are compared to its final state. Only LUI/ADDI/SW/JAL semantics are supported;
retirement comparison is PC-only. Store timing association with a dynamic instruction,
reset mid-flight, loads/errors/waits and trap/CSR behavior remain outside F0.1.
No RTL changes or genuine DUT failures occurred in this revision. Intentional
checker failures do not demonstrate an RTL bug or formal correctness.

Run default: `pwsh -NoProfile -File Verification/tb_core_trap_lean/run_f0.ps1`.
Run variants: load Vlsi.ps1 and ../scripts/vlsi/VlsiRun.ps1, then use
`Invoke-VlsiRun -Manifest Verification/tb_core_trap_lean/<variant>.json -NoThrow`.
Negative manifests intentionally return a failed functional status.

## F0.2 pipeline and memory protocol increment - 2026-11-13

Status: infrastructure and directed checker tests implemented. Clean F0.2 acceptance
is OPEN due to F02-WB-01, a repeated nonzero GPR write-enable while MEM/WB is held.
This run matrix is not an all-pass milestone and does not establish trap signoff.
All core RTL source hashes match the F0.1 snapshot; no RTL change was made.

The custom core observation interface and common stage/pipeline assertions are
connected in one adapter. Reset/hold/flush properties are defined once per rule,
not duplicated in the bench. The memory responder adds bounded WAIT_CYCLES while
retaining a zero-wait default and no flush/write-masking mechanism.

| Scenario | Classification | Mode | Evidence |
|---|---|---|---|
| Zero-wait JAL and overwrite | PASS | Iteration | [core-trap-f02-zero_20261113T082726Z_bf030b42](../artifacts/vlsi_auto/core-trap-f02-zero_20261113T082726Z_bf030b42/results/simulation.log) |
| One-cycle wait isolation | PASS | Iteration | [core-trap-f02-wait-one_20261113T082617Z_adcd2cff](../artifacts/vlsi_auto/core-trap-f02-wait-one_20261113T082617Z_adcd2cff/results/simulation.log) |
| Three-cycle wait isolation | PASS | Final artifacts | [core-trap-f02-wait_20261113T082726Z_deb29853](../artifacts/vlsi_auto/core-trap-f02-wait_20261113T082726Z_deb29853/results/simulation.log) |
| F0 baseline regression | PASS | Iteration | [core-trap-f0_20261113T082752Z_3838455d](../artifacts/vlsi_auto/core-trap-f0_20261113T082752Z_3838455d/results/simulation.log) |
| F0 reset-offset regression | PASS | Iteration | [core-trap-f0-offset_20261113T082752Z_3a1cf40c](../artifacts/vlsi_auto/core-trap-f0-offset_20261113T082752Z_3a1cf40c/results/simulation.log) |
| Hold assertion self-test | EXPECTED CHECKER FAIL | Iteration | [core-trap-f02-negative-hold_20261113T082617Z_f5fb88d0](../artifacts/vlsi_auto/core-trap-f02-negative-hold_20261113T082617Z_f5fb88d0/results/simulation.log) |
| Flush assertion self-test | EXPECTED CHECKER FAIL | Iteration | [core-trap-f02-negative-flush_20261113T082617Z_1e0eb9b0](../artifacts/vlsi_auto/core-trap-f02-negative-flush_20261113T082617Z_1e0eb9b0/results/simulation.log) |
| Ordinary F0 stream with waits | OPEN DUT FINDING | Final artifacts | [core-trap-f02-wb-wait_20261113T082726Z_3fdac335](../artifacts/vlsi_auto/core-trap-f02-wb-wait_20261113T082726Z_3fdac335/results/simulation.log) |

[F02_MATRIX.json](F02_MATRIX.json) retains common HDL source hashes, per-run modes,
coverage status, diagnostics, activation witnesses, archive hashes and retrieved-file
counts. All eight rows use the same final HDL hash set and zero input/output hash
mismatches. Exits are zero for the five positive scenarios and two for the three
failing scenarios. The ordinary-stream failure is NOT an expected checker self-test.

Full artifacts were requested only for the accepted three-wait isolation case and
for diagnosing the real write-enable failure. Other runs use the new iteration mode;
12 files were retrieved for positive iteration runs and 146 for these full runs.
There is no router/network-setting change. Waveforms and detailed code/HTML reports
are available in the two Final result directories. -Final is an artifact mode, not
a declaration of verification signoff. Negative coverage was not merged.

The three-wait isolation case witnesses reset and hold at all D/E/M/W stages,
D/E flush, fetch hold, JAL redirect, stable waiting request and successful release.
Its independent event model checks 7 completed instructions, 3 GPR effects and
1 store; the responder wait count is exactly 3. The one-wait variant checks exactly
1 wait edge. Cover callbacks provide activation witnesses (>0); Xcelium may stop
cover evaluation after the first hit. They are not assertion-attempt totals.

26 assert-property instances and 19 cover-property instances elaborate (45 constructs).
Two negative tests deliberately corrupt only the monitor observation: a changing MEM
payload is caught by stage[2].a_hold, and sticky D valid is caught by stage[0].a_flush.
M/W flush and WB trap/return redirects have no hits in F0.2. They are implemented
and explicitly pending F1 rather than counted as covered.

The full three-wait run reports DUT aggregate toggle 13.95% (264/1892); per-instance
block/expression values remain in metrics_summary.txt. This is coverage measurement,
not closure. There is no separate functional covergroup signoff claim.

Early compile attempts core-trap-f02-zero_20261113T082350Z_e9775f13 and
core-trap-f02-wait_20261113T082350Z_b5f43cf2 failed because monitor self-test variables
were declared after use. Those artifacts remain. Moving TB declarations before use
resolved compilation without changing RTL or expectations. Earlier behavioral
iterations are retained under the same core-trap-f02 name prefix.

[F02_CONTRACT.md](F02_CONTRACT.md) defines timing and scope.
[F02_FINDINGS.md](F02_FINDINGS.md) gives the exact failing trace, source evidence,
limits and next engineering decision. No exception, IRQ or MRET program has been
run yet. Before claiming clean trap commitment, resolve the physical-write contract
and retain this regression. No checker de-duplication or RTL fix was applied.

## F1 minimal ECALL/MRET smoke - 2026-11-13

Status: the minimal RF-first smoke and relocated-reset smoke PASS end to end.
General precise-exception squash acceptance is OPEN on F1-EXC-01: a store immediately
after ECALL modifies data SRAM on the older exception's WB commit edge. This is a
real failing regression, not an intentional-negative test. F02-WB-01 remains open.
No RTL change, write masking or assertion relaxation was made.

The independent model now supports the tested M-mode CSR register operations,
ECALL entry and MRET return. The existing physical-effect scoreboard is reused.
New common ECALL/MRET SVA uses independently predicted PC/status inputs. The local
program configures mtvec and MIE through software, records handler state in DMEM,
advances mepc, returns and completes application signatures. Every SRAM word is
compared against reference final state, including untouched handler poison memory.

| Case | Outcome | Mode | Evidence |
|---|---|---|---|
| ECALL/MRET smoke | PASS | Final artifacts | [core-trap-f1_20261113T141531Z_69310ea7](../artifacts/vlsi_auto/core-trap-f1_20261113T141531Z_69310ea7/results/simulation.log) |
| Relocated reset/handler smoke | PASS | Iteration | [core-trap-f1-offset_20261113T141531Z_c987d623](../artifacts/vlsi_auto/core-trap-f1-offset_20261113T141531Z_c987d623/results/simulation.log) |
| Adjacent-store exception squash | REAL DUT FAILURE | Final artifacts | [core-trap-f1-adjacent-store_20261113T141531Z_73e27421](../artifacts/vlsi_auto/core-trap-f1-adjacent-store_20261113T141531Z_73e27421/results/simulation.log) |
| Wrong mepc oracle | EXPECTED CHECKER FAILURE | Iteration | [core-trap-f1-negative-mepc_20261113T141631Z_2d412f02](../artifacts/vlsi_auto/core-trap-f1-negative-mepc_20261113T141631Z_2d412f02/results/simulation.log) |
| Wrong return oracle | EXPECTED CHECKER FAILURE | Iteration | [core-trap-f1-negative-return_20261113T141631Z_3d1fad06](../artifacts/vlsi_auto/core-trap-f1-negative-return_20261113T141631Z_3d1fad06/results/simulation.log) |
| F0 baseline regression | PASS | Iteration | [core-trap-f0_20261113T141631Z_9bced0db](../artifacts/vlsi_auto/core-trap-f0_20261113T141631Z_9bced0db/results/simulation.log) |
| F0.2 three-wait isolation regression | PASS | Iteration | [core-trap-f02-wait_20261113T141631Z_f7a2a6e1](../artifacts/vlsi_auto/core-trap-f02-wait_20261113T141631Z_f7a2a6e1/results/simulation.log) |

All seven rows use identical final HDL source hashes, verified against the current
local inputs. Exits are zero for four passing runs and two for three failing runs;
input/output transfer hashes match with no infrastructure errors. F1_MATRIX.json
records source/archive hashes, marker lines, coverage/report status and modes.
Core RTL hashes are unchanged from F0.2. The initial dense first attempt and its
subsequent reproduction remain preserved under the earlier core-trap-f1 prefixes.

Default smoke result at 425 ns:
`F1_PASS traps=1 mret=1 fault_pc=8000001c handler=80000100 resume=80000020 instructions=23 gpr=13 stores=5`.
ECALL commits at 165 ns and MRET at 315 ns. Expected entry status is 0x1880 and
returned status is 0x1888. The handler records the original mepc=0x8000001c, cause=11
and entry status; the application stores 0x5a and 2 after return. Handler poison
memory remains zero. Entry/return/WB and M/W-flush activation witnesses are nonzero.
The relocated scenario captures 0x8000005c and returns to 0x80000060 through the
handler at 0x80000140 with the same checker/model logic.

The two oracle-negative tests change only independently expected mepc/return-PC
inputs by +4. They fail at a_ecall_packet and a_mret_packet respectively; stimulus,
DUT state and the scoreboard expectation streams are not changed. Negative coverage
is not requested or merged into positive evidence.

Full artifact mode was used for the passing smoke and the dense-case real failure:
147 retrieved files per run, including SHM and detailed IMC/HTML reports. Other runs
used the bandwidth-reduced iteration mode. Full artifact mode is not a signoff claim.
Xcelium 24.09-s001 and IMC generated reports. The smoke's DUT aggregate toggle is
27.01% (511/1892); this is measurement, not closure. Thirty assert-property instances
and 21 cover-property instances elaborate (51 constructs); this is not 51 independent
proven properties or a formal result. No separate functional-covergroup signoff is
claimed. See each run's per-instance metrics for block/expression coverage.

The full dense-case final snapshot is decisive: at 165 ns, trap=1, memory write
request=1, stall=0, error=0; after the edge app0=0x5a while mret=0 and handler
signatures remain zero. The original common no-younger-request-on-WB-redirect rule
correctly fails. The RF-first smoke commutes the first post-ECALL ADDI and store
solely as a complementary isolation scenario; it does not replace/waive the dense case.

[F1_CONTRACT.md](F1_CONTRACT.md) describes source ownership, expectations, scope and
sampling. [F1_FINDINGS.md](F1_FINDINGS.md) records the real squash failure and reproduction.
Run default: `pwsh -NoProfile -File Verification/tb_core_trap_lean/run_f1.ps1 -Final`.

## F2 directed synchronous exceptions - 2026-11-13

Status: all four requested directed cases PASS under Xcelium 24.09-s001. F1 and
F0 regressions PASS; a deliberately wrong mtval oracle fails as intended. This
validates the selected zero-wait RF-first fixtures, not all exception squashing.
F1-EXC-01 and F02-WB-01 remain open. No RTL edit or GitHub/Issue #30 mutation was
performed in this task; the user-reported issue disposition is preserved.

The shared machine predictor adds explicit illegal/EBREAK and misaligned LW/SW
classification plus mtval state/readback. A single shared handler records mepc,
mcause, mstatus and mtval, advances mepc by four and returns to checked application
code. The generalized core_sync_trap_sva replaces the former ECALL-only checker
without copying assertions into four benches. The dedicated common
trap_functional_cov.sv is instantiated on actual trap/cause/mtvec signals.

| Case | Expected mcause | Expected mtval | Outcome | Evidence |
|---|---|---|---|---|
| illegal | 2 | `ffffffff` | PASS | [core-trap-f2-illegal_20261113T170000Z_8242fb3c](../artifacts/vlsi_auto/core-trap-f2-illegal_20261113T170000Z_8242fb3c/results/simulation.log) |
| ebreak | 3 | `8000001c` | PASS | [core-trap-f2-ebreak_20261113T170038Z_325e19f0](../artifacts/vlsi_auto/core-trap-f2-ebreak_20261113T170038Z_325e19f0/results/simulation.log) |
| load | 4 | `80001002` | PASS | [core-trap-f2-load_20261113T170058Z_c8f31cd1](../artifacts/vlsi_auto/core-trap-f2-load_20261113T170058Z_c8f31cd1/results/simulation.log) |
| store | 6 | `80001002` | PASS | [core-trap-f2-store_20261113T170119Z_f24e0579](../artifacts/vlsi_auto/core-trap-f2-store_20261113T170119Z_f24e0579/results/simulation.log) |

Each F2 case checks one trap and one MRET, exact mepc=0x8000001c, direct handler
0x80000100, software-updated return PC=0x80000020, entry/return status and final
application signatures. The independent model predicts 25 ordinary retirements,
14 nonzero-GPR effects and six stores for these images; these totals are generated,
not hardcoded scoreboard expectations. The handler's mtval DMEM word at +24 matches
the CSR. Handler poison word +20 remains zero. Load/store faulting memory-request
suppression has a required successful cover witness. The faulting load emits no GPR
effect and the faulting store emits no accepted write. The illegal marker is
0xffffffff; the handler skips it rather than retrapping indefinitely.

Final command executed:
`& ./Verification/tb_core_trap_lean/run_f2.ps1 -Case all -Final`.
All four cases returned pass/reported. Each final artifact folder contains 149
validated retrieved files, including SHM, UCM/UCD, detailed code/HTML and functional
summaries. Iterations used the compressed lightweight runner; full evidence was
collected only after the behavioral cases passed. Artifact mode is not signoff.

Additional same-source evidence:
- F1 ECALL regression: PASS [core-trap-f1_20261113T170010Z_389c1396](../artifacts/vlsi_auto/core-trap-f1_20261113T170010Z_389c1396/results/simulation.log).
- F0 regression: PASS [core-trap-f0_20261113T170010Z_95b6b12c](../artifacts/vlsi_auto/core-trap-f0_20261113T170010Z_95b6b12c/results/simulation.log).
- wrong mtval oracle: EXPECTED FAIL [core-trap-f2-negative-mtval_20261113T170010Z_bd2d85e2](../artifacts/vlsi_auto/core-trap-f2-negative-mtval_20261113T170010Z_bd2d85e2/results/simulation.log).

The negative changes only the independently predicted tval supplied to SVA from
0x80001002 to 0x80001003. It fails at a_trap_packet, exit 2; actual trap/CSR tval
remains 0x80001002. Negative coverage is neither requested nor aggregated. The
coverage-method informational message in that negative log reflects disabled
coverage instrumentation, not a positive coverage result.

All seven runs share the final HDL hash set, match current local sources, and have
zero input/output hash mismatches or infrastructure errors. Compiled core RTL
hashes match F1. F2_MATRIX.json records complete source/archive identities, marker
lines, code/functional reports and per-run modes. The two initial compile failures
(core-trap-f2-illegal_20261113T165629Z_7b42d3cd and
core-trap-f2-ebreak_20261113T165629Z_0bfbf547) remain preserved: the initial bin name
vectored was a reserved SV keyword; renaming bins fixed compilation, not expectations.

### Functional coverage evidence and limits

IMC functional_summary.txt is generated and inspected for each F2 case and the
F1 regression. Each single-cause run covers 3/17 bins: its cause, direct mode and
the corresponding cross. IMC reports 17.65% bin coverage and 26.67% coverpoint/cross
average per run. Across the positive F1/F2 logs, hardware observations cover causes
2,3,4,6,11 with five direct-mode samples and zero vectored samples. This is an
observed union, not a fabricated merged IMC percentage. No coverage exclusions,
refinements, synthetic loop samples or forced vector mode were used.

The current mtvec CSR mask exposes direct mode only. Vectored and its crosses
remain unhit and visible for future supported configurations. The current matrix
is not a >90% functional/full-core signoff campaign. Raw code coverage remains
per instance: the full load run's DUT aggregate toggle is 25.90% (490/1892), CSR-file
block 28/49 and expression 8/12, WB commit block 2/7 and expression 2/6. These are
measured structures, not correctness proof. Detailed unhit reports are retained.

[F2_CONTRACT.md](F2_CONTRACT.md) maps semantics, shared/local components, checks,
coverage definitions, replay commands and limits. Only word misalignment at offset
2, one illegal opcode marker and synchronous direct traps are claimed. Interrupts,
nested traps, vector mode, bus faults, halfword cases and trap/wait overlap remain
outside these runs. The preserved dense adjacent-store regression is unchanged.

## F3 asynchronous interrupts - 2026-11-13

Status: F3 is NOT SIGNED OFF. The user explicitly retained the requested
MEIP > MTIP > MSIP policy. Four supported service/replay cases pass; three real
requested-policy cases fail. No RTL, router configuration, test expectation waiver
or GitHub update was applied. Existing F1/F0.2 findings remain open.

| Case | Classification | Evidence |
|---|---|---|
| timer | PASS | [core-trap-f3-timer_20261113T174316Z_dd376068](../artifacts/vlsi_auto/core-trap-f3-timer_20261113T174316Z_dd376068/results/simulation.log) |
| timer-late | PASS | [core-trap-f3-timer-late_20261113T174317Z_11d0e62d](../artifacts/vlsi_auto/core-trap-f3-timer-late_20261113T174317Z_11d0e62d/results/simulation.log) |
| fast0 | PASS | [core-trap-f3-fast0_20261113T174046Z_7a203578](../artifacts/vlsi_auto/core-trap-f3-fast0_20261113T174046Z_7a203578/results/simulation.log) |
| fast6 | PASS | [core-trap-f3-fast6_20261113T174105Z_3527a82a](../artifacts/vlsi_auto/core-trap-f3-fast6_20261113T174105Z_3527a82a/results/simulation.log) |
| external | REAL REQUIREMENT FAILURE | [core-trap-f3-external_20261113T174123Z_eb6637d7](../artifacts/vlsi_auto/core-trap-f3-external_20261113T174123Z_eb6637d7/results/simulation.log) |
| software | REAL REQUIREMENT FAILURE | [core-trap-f3-software_20261113T174139Z_504548de](../artifacts/vlsi_auto/core-trap-f3-software_20261113T174139Z_504548de/results/simulation.log) |
| priority | REAL REQUIREMENT FAILURE | [core-trap-f3-priority_20261113T174316Z_bd3f6ebe](../artifacts/vlsi_auto/core-trap-f3-priority_20261113T174316Z_bd3f6ebe/results/simulation.log) |
| negative mepc oracle | EXPECTED CHECKER FAILURE | [core-trap-f3-negative-mepc_20261113T174019Z_7dfe2d9d](../artifacts/vlsi_auto/core-trap-f3-negative-mepc_20261113T174019Z_7dfe2d9d/results/simulation.log) |

The actual `run_f3.ps1 -Case all -NoThrow` batch returned four pass/reported rows
and three failed/reported rows. -NoThrow was used only to preserve and collect the
whole matrix; the failed statuses were never upgraded. Timer, late timer and the
priority failure were additionally rerun with -Final for full debug artifacts
(150 verified output files per full run). Other iterations used lightweight
logs/summaries (13 files); no network settings were changed.

Same-source positive regressions:
- F1 regression: PASS [core-trap-f1_20261113T174019Z_20995547](../artifacts/vlsi_auto/core-trap-f1_20261113T174019Z_20995547/results/simulation.log).
- F2 illegal regression: PASS [core-trap-f2-illegal_20261113T174019Z_8b8690e0](../artifacts/vlsi_auto/core-trap-f2-illegal_20261113T174019Z_8b8690e0/results/simulation.log).
- F2 ebreak regression: PASS [core-trap-f2-ebreak_20261113T174327Z_fc244b57](../artifacts/vlsi_auto/core-trap-f2-ebreak_20261113T174327Z_fc244b57/results/simulation.log).
- F2 load regression: PASS [core-trap-f2-load_20261113T174327Z_0212463a](../artifacts/vlsi_auto/core-trap-f2-load_20261113T174327Z_0212463a/results/simulation.log).
- F2 store regression: PASS [core-trap-f2-store_20261113T174327Z_60c75ae1](../artifacts/vlsi_auto/core-trap-f2-store_20261113T174327Z_60c75ae1/results/simulation.log).

All 13 retained rows in F3_MATRIX.json use the same final HDL/header hash set,
verified against current local files, with no input/output hash mismatches or
infrastructure errors. All compiled core RTL hashes match F2. Pass exits are zero;
three requirement failures and the one intentional oracle failure exit two.
The prior signed-off F2 directed scope is preserved by four passing regressions.

### Independent asynchronous PC precision

The reference snapshots pre-instruction architectural state. Ordinary DUT retirement
PCs must match the model before its cursor advances. At an interrupt commitment,
that NEXT EXPECTED PC supplies mepc; neither DUT PCE nor trap_pc supplies the oracle.
The model inserts handler execution at this frontier and predicts replay without
incrementing mepc. Guarded scoreboard revision checks already-observed RF/store
counts against the snapshot before replacing only unconsumed predictions. No
observed effect or counter is discarded. The fixture rejects interrupts after
application stores rather than pretending to roll back memory.

Early timer/fast cases retire prefix 20, so the expected next PC is 0x80000050;
the late timer retires prefix 24, so it is 0x80000060. Actual saved CSR mepc, handler
readback and final memory match those independent PCs. Each passing F3 run completes
55 ordinary instructions, 37 GPR effects and five stores; application results are
24/25, demonstrating no skipped or duplicated interrupted ADDI. Exactly one IRQ
and one MRET plus required status/mask witnesses are checked. Early sources retain
pending state for eight sampled masked cycles; timer/fast GPIO/event pins are
pulsed, so pending retention is exercised after deassertion. External/software
levels stay asserted as required by their source semantics.

Timer default: asynchronous edge 172 ns, first logged masked sample 195 ns,
MIE-enable retirement 265 ns, IRQ commit 295 ns. The fixture's six-cycle service
bound is checked independently of the DUT's accepted-IRQ flag. This is prompt
pipeline service in a zero-wait directed stream, not same-edge commitment or a
universal timing guarantee. The shifted late-arrival PC demonstrates that the PC
oracle is not a fixed label/result table.

The negative-mepc case changes only the PC input presented to SVA by +4. The model,
DUT and retirement cursor are unchanged; the correct actual mepc=0x80000050 causes
a_trap_packet to fail against the deliberately wrong input. Negative coverage is
not requested or combined. Its coverage-method informational message reflects
instrumentation disabled for the intentional failure.

### Masking, source selection and coverage

External and software cases pass mip/mie visibility during MIE=0, then fail prompt
service with global MIE=1 and their pending bits still high. In the simultaneous
case mip=mie=0x888 while masked; the core later commits timer cause 0x80000007,
not the requested external cause 0x8000000b. F3_FINDINGS.md records exact logs,
source-backed route explanation and what this does and does not establish.

trap_functional_cov now includes interrupt causes (timer/external/software and
fast 16..27) and before/after MIE/MPIE coverpoints qualified by actual trap/MRET
events. Software's initial enable is not counted as a return. Passing IRQ cases
have hardware counters mie_entry_clear=1 and mie_return_restore=1. Unserved external/
software bins, other fast bins and vector mode remain visibly unhit; no coverage
exclusions or manufactured samples are used. Reports are per run, not merged.

The full timer run reports covergroup average 31.46% and 7/72 bins covered (9.72%)
across the expanded cause/mode/status model. DUT aggregate toggle is 29.70%
(562/1892), CSR-file block 28/49 and expression 8/12, WB commit block 4/7 and
expression 3/6. These measurements are not coverage closure. All detailed reports
for representative full runs are retained. Earlier F2 percentages used the smaller
F2 coverage model and must not be compared as if the denominator were unchanged.

Application preemption/replay is tested. Nested IRQ-on-ISR preemption, multiple
sequential IRQs per session, custom class RR/fairness/threshold races, all fast
inputs, RV32M/memory-wait interruption and SoC/ISR-loop validation remain outside
this bounded matrix. Requested priority/preemption closure is blocked by the
routing/policy requirements above, not silently substituted by custom arbitration.
[F3_CONTRACT.md](F3_CONTRACT.md) defines ownership, stimulus, model and replay.


## F3 continuation — documentation reconciliation and execution delegation

Updated README.md, TESTPLAN.md, ARCHITECTURE.md and the common core library README
to describe the implemented F3 frontier/replanning contract, shared IRQ SVA,
hardware-qualified transition coverage, local/common ownership and requested-policy
failures. Regenerated the main diagram from its saved source-backed spec; the
validator passed. Checked local Markdown links in all four updated documents:
no broken links. Independently recomputed every F3_MATRIX.common_input_hashes entry:
no changed tested HDL or included SVH files. No RTL, check, manifest or policy edits.

GPT-6 Luna is assigned retained-artifact status/coverage auditing and concise
collection reports; the primary agent retains code and verification decisions.
The audit artifacts are F3_AUDIT.md / F3_AUDIT.json when completed. No new simulation
campaign was requested merely to repeat already completed same-input runs.
F3 remains NOT SIGNED OFF: external/software service and requested priority fail.


### F3 delegated audit completed and primary review applied

[F3_AUDIT.md](F3_AUDIT.md) and [F3_AUDIT.json](F3_AUDIT.json) record all 13 retained
verdicts and actual IRQ/return witnesses. All current matrix HDL/header hashes
match. Four F3 service cases and five F1/F2 regressions pass. External/software fail
enabled service; priority fails cause selection; only negative-mepc is intentional.
No missing reportable summaries, infrastructure errors or remote recollection need
was found. No simulations were rerun.

Primary review corrected the audit's coverage/exit prose: DUT timer toggle is
562/1892 (29.70%); late timer 566/1892 (29.92%). Monitor implementation code coverage
is separate from functional bins (7/72, 9.72%; average 31.46%). Failing simulations
have nonzero exit codes despite successful IMC reporting. Audit JSON retains exact
command exits. F3 remains NOT SIGNED OFF; requested-policy and older findings stay open.
