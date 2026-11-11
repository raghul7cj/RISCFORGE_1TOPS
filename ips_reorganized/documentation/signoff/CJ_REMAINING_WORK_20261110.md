# CJ remaining work after local source synchronization

**Unified review package:** [HTML entry](cj_review/index.html) · [maintained document map](cj_review/README.md). The four topic pairs explain architecture, verification boundaries, benchmark/SPI evidence and all 18 responsibility closures without changing official statuses.

**Known-finding reconciliation:** [CJ_FINDING_RECONCILIATION_20261110.md](CJ_FINDING_RECONCILIATION_20261110.md) maps all eight discussions, current defects, integrated corrections, testbench/model issues and legacy records to these 18 responsibilities. [GitHub register #24](https://github.com/raghul7cj/RISCFORGE_1TOPS/issues/24) tracks the same scope. This adds traceability without promoting official checklist status.

Local `ips/` now contains every tracked file from remote
`verification_infra/ips_reorganized` at commit
`a91edb7e666d5c374af70809703f52eb5513d96f`, plus preserved local-only work.
The download is an augmented offline source copy, not a Git checkout.

The parent completed and approved the local sync after the Luna/high staging
task ended incomplete. All 1,570 remote file blobs were verified, ten existing
files were backed up/replaced, nineteen missing files were added, and no
local-only file was deleted. See the [sync review and exact diffs](../../../artifacts/verification_infra_sync_20261110/REVIEW.md)
and [receipt](../../../artifacts/verification_infra_sync_20261110/sync_receipt.json).

Fresh post-sync checks passed all 13 directed core configurations, the 131,072
legality-field combinations plus exact SYSTEM guards, and four MDU ownership/
abort checks. SoC Verilator lint/elaboration exited zero with 107 retained
warnings using `-DXSIM -Wno-fatal`. All 1,570 live/snapshot/archive file blobs
match the pinned source; the ten backups and offline ZIP integrity were also
checked. See [the validation record](../../../artifacts/verification_infra_sync_20261110/validation/POST_SYNC_VALIDATION.json)
for logs, scope and limitations. These checks do not close the full campaigns below.

## RTL corrections now present locally

| Files | Current implementation | Remaining evidence limit |
|---|---|---|
| [execute_cycle.v](../../riscv_core/rtl/execute_cycle.v), [hazard_unit.v](../../riscv_core/rtl/hazard_unit.v) | MDU result validity/origin PC/hold, issue ownership, older-memory preservation, WB cancellation and redirect/link preservation during memory wait | Directed checks cover selected overlaps, not every precise-trap/IRQ/memory scenario |
| [rv32m_mul.v](../../riscv_core/rtl/rv32m_mul.v), [rv32m_unit.v](../../riscv_core/rtl/rv32m_unit.v) | Abort propagates through all multiplier valid stages; old completion cannot interfere with the tested next DIV | Wider abort/completion/IRQ windows still need qualification |
| [Control_Unit_Top.v](../../riscv_core/rtl/Control_Unit_Top.v) | Instruction subfield legality and exact SYSTEM guards | CSR address/access policy and complete architectural state space are outside the field sweep |
| [decode_cycle.v](../../riscv_core/rtl/decode_cycle.v) | RS2 decode hazard input qualified by actual instruction class | RS1 false dependencies remain separate |
| [csr_regfile.v](../../riscv_core/rtl/csr_regfile.v) | Software-written mepc low bits masked for the no-C configuration | Full CSR/WARL/trap/MRET races remain to be checked |
| [fetch_cycle.v](../../riscv_core/rtl/fetch_cycle.v), [top.v](../../riscv_core/rtl/top.v), [SoC top](../../RTL_SOC/riscforge_soc_subsystem.sv) | Optional cause-1 fetch-map checks, SoC BootROM/ISRAM wiring, WB cancellation connection | All map boundaries and redirect/stall/physical-response cases are not exhaustively checked |

The 13-source IRQ gateway/arbiter and custom mintprio remain intact. This sync
does not import a different interrupt architecture or unrelated peripheral fixes.

## All 18 responsibilities

This is a current engineering task list. It does not alter official workbook
statuses, invent coach approval, or equate downloaded/merged source with closure.

| ID | Current basis | What CJ still needs to do |
|---|---|---|
| 1.1 | ISA described; corrected decoder now local | Freeze exact RV32IM/Zicsr and extension/unsupported-encoding policy against the reviewed source |
| 1.3 | M-only implementation description exists | Resolve intended privilege/MPP behavior and record the frozen contract |
| 1.4 | Implemented CSR table exists; mintprio preserved | Reconcile current masks/reset/access types, read-only/unsupported access policy and approved table |
| 1.5 | Trap/MRET model plus selected directed evidence | Freeze trap boundary, priority, IRQ eligibility/resume rules and nesting policy; distinguish as-coded behavior from agreed intent |
| 1.9 | Current 13-source map and gateway/arbiter available | Freeze source/subevent IDs, capture modes, masks and priority with the accepted controller disposition |
| 2.7 | LSU exists; selected stalled-load/MDU checks pass in port evidence | Qualify byte enables, sizes/offsets, sign/zero extension, alignment, one-outstanding and error/latency behavior on this source |
| 2.9 | CSR/trap RTL updated; corner-bench skeleton available | Complete independent model, checks/stimulus/coverage and WARL/CSR/trap/MRET race verification; do not count the skeleton as a pass |
| 2.10 | C unsupported in the documented configuration | Record N/A explicitly with the frozen ISA and no-C build flags; retain applicable alignment checks |
| 3.4 | Custom IRQ controller rather than integrated PLIC | Record exact approved architecture alternative/waiver, or separately plan required implementation; no approval is inferred |
| 3.6 | Custom controller; software/external delivery gap remains | Resolve timer/software IRQ requirements and exact CLINT/CLIC disposition; test the accepted implementation |
| 4.12 | Scoped core trap tests and historical IRQ unit evidence | Verify RESET_PC, clean IRQ acceptance, mtvec redirect, mepc save, handler/MRET/resume and gating-CSR ordering on the current core |
| 5.2 | Earlier RISCOF pass reported; latest passing bundle not bound here | Recover its identity, select actual current DUT/plugin/reference/ISA and run the applicable official suite with retained signatures/logs |
| 5.3 | Illegal/ECALL/MRET guards and detailed corner plan exist | Run all applicable machine trap/privilege tests and asynchronous IRQ/collision corners; map each to checks and evidence |
| 5.7 | Benchmark infrastructure and failing historical runs retained; relevant MDU mechanisms corrected | Run smoke, then correct-result CoreMark/Dhrystone on the integrated SoC; qualify measurement counters/window and record defensible metrics/configuration/images |
| 5.10 | Several fixes have scoped evidence; open issues remain | Close required-severity bugs with before/after and regression evidence; rerun saved RISC-DV failures; justify lower-severity dispositions |
| 6.5 | Unit IRQ evidence and detailed event plan, proposed new TB | Implement/check real peripheral events through routing, masking/priority and required commit/handler behavior for all sources/subevents |
| 6.10 | Historical SPI bootloader and SoC passing evidence exists | Reproduce current external-flash image transfer, SRAM integrity, release/handoff and SRAM execution with independent pass proof; resolve boot-mode departure |
| 6.13 | Shared CSR/trap/IRQ/pipeline plans and selected MDU guards | Implement legal memory-load/branch/M-operation/IRQ schedules; prove precise effects, bounded progress, return and declared nesting under load |

## Unresolved RTL and coverage priorities

1. **minstret overcount during WB hold:** still open. Use a unique-retirement
   ledger before CPI/instruction-count claims.
2. **JALR runtime coverage:** the missing-bit-zero-mask allegation was withdrawn
   after tracing Main_Decoder → ALU_Decoder → ALU: ALU.v already clears bit 0.
   Check raw target sums ending in 01 and 11 as remaining coverage, not an
   established missing-mask RTL defect. GitHub #17 is closed as incorrectly filed.
3. **Extra spec_tag fetch hold:** unchanged performance finding. Measure the
   actual SRAM/redirect timing and record the accepted performance disposition.
4. **RISC-DV DEC-001/EXC-002 campaign closure:** current legality/ownership fixes
   have directed evidence, but saved illegal seeds and misaligned 21/38 plus
   unaligned load/store 38 must be rerun with identified source/program/reference.
5. **Broader precise effects and IRQ ordering:** exercise kill/completion
   coincidence, MDU issue/busy/done IRQ arrival, CSR writes before eligibility,
   and younger GPR/CSR/store/MMIO effects. Treat untested risks as unverified,
   not additional reproduced defects.
6. **CSR policy, M-only WARL and source-use questions:** custom 0x7C0 is
   implemented; freeze actual unsupported/read-only policy. RS1 qualification,
   forwarding corners and conditional x0 initialization require bounded review.
7. **Full evidence campaigns:** architectural suite, current SoC benchmarks,
   real per-source IRQ, current SPI boot and coverage/tool acceptance are not
   replaced by this synchronization or its smoke regression.

## Useful next sequence

First review the downloaded [regression guide](../../Verification/core_port_20261109/README.md)
and one source/test/result path from the [learning route](cj_learning/START_HERE.md).
Then choose a bounded open defect or contract decision, preserve a distinguishing
failure and define the correction/check together before broadening the campaign.
For benchmark readiness, retirement accounting and correct-result workload reruns
are immediate dependencies. For RISC-DV, bind the actual candidate and recover
the saved test images/reference configuration before claiming a seed is fixed.

The official checklist remains unchanged. New post-sync local-path development
results are recorded under artifacts/verification_infra_sync_20261110/validation/;
their scope is separate from accepted-tool signoff, architectural campaigns or
board validation.
