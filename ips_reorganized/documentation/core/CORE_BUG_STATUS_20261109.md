# Core bug status — screenshot claims cross-check

**10 November correction:** the JALR missing-bit-zero-mask allegation below was incorrect. ALU.v control 0110 clears bit zero, selected for JALR through Main_Decoder/ALU_Decoder. GitHub #17 is withdrawn; preserve the old allegation as history, not a current defect. Runtime JALR qualification remains separate.

**Current known-finding register:** use the [10 November reconciliation](../signoff/CJ_FINDING_RECONCILIATION_20261110.md) and [GitHub tracker #24](https://github.com/raghul7cj/RISCFORGE_1TOPS/issues/24). They account for merged fixes, current core defects, additional testbench/model defects and historical records awaiting triage; the pre-port findings below remain preserved.

**10 November local sync:** live `ips/` now includes the merged source at `a91edb7e666d5c374af70809703f52eb5513d96f`. See the [current remaining-work list](../signoff/CJ_REMAINING_WORK_20261110.md) and [exact sync review](../../../artifacts/verification_infra_sync_20261110/REVIEW.md). The observations and source hashes below are the retained pre-port review; they do not describe every current file after synchronization.

**Integration completed:** [PR #15](https://github.com/raghul7cj/RISCFORGE_1TOPS/pull/15) is merged into remote `verification_infra` at `a91edb7e666d5c374af70809703f52eb5513d96f`. The merged tree exactly matches the tested candidate. See the [merged changes and unresolved issues](MALAY_CORE_PORT_20261109.md). The exact earlier tested candidate remains under `artifacts/core_port_20261109/candidate/ips_reorganized/`; live local RTL has now also been synchronized.

**Historical pre-port branch comparison:** the screenshots concerned a different branch. [Pinned malay versus verification_infra review](../../../artifacts/malay_core_compare_20261109/REPORT.md) identified MDU completion/hold, MDU FlushM, fetch-region, RS2 and legality corrections missing from the then-reviewed verification_infra head `58af373...`. PR #15 subsequently integrated selected corrections with directed evidence, preserving the target load-use mask and 13-source IRQ gateway. Refer to the current list above for what remains unresolved.

Reviewed 9 November 2026 against the local `rtl/ips` source tree. This updates the earlier chat list for this source snapshot. The screenshot report's source path/revision was not supplied. No design RTL, firmware, verification expectation or official workbook was changed.

## Source identity and evidence

- Design filelist: [soc_subsystem.f](../../RTL_SOC/soc_subsystem.f:212). The verification manifest [rf_filelist.txt](../../Verification/infrastructure/rf_filelist.txt:221) names the same core files. Filelist comments about UART are known stale; only the explicit core entries are used for this binding.
- Compared every entry in [benchmark design_baseline.json](../../benchmarks/docs/design_baseline.json): **109 present, 109 hash matches, 0 changed, 0 missing**. This binds the retained benchmark findings to identical design bytes. It does not constitute a fresh full-SoC execution or bind a separately built FPGA bitstream.
- New Icarus Verilog 12.0 leaf probe: [source](../../../artifacts/core_claim_review_20261109/tb_claim_probe.sv), [compile log](../../../artifacts/core_claim_review_20261109/compile.log), [simulation log](../../../artifacts/core_claim_review_20261109/simulation.log), [review manifest](../../../artifacts/core_claim_review_20261109/review_manifest.json). Compile and simulation exited 0. The assertions check specifically described hazard/gateway behavior, not architectural correctness of the whole core.
- Earlier source/evidence records remain historical: [RISC-DV failure audit](RISCV_DV_FAILURE_AUDIT.md) and [benchmark waveform isolation](../../benchmarks/docs/RTL_FAILURE_ISOLATION.md).

## Screenshot claims

| Screenshot claim | Result for this local source | Evidence and limit |
|---|---|---|
| MUL/DIV result now written back | **Fix absent; retain open** | [execute_cycle.v:424](../../riscv_core/rtl/execute_cycle.v:424) still loads `valid_M_r <= valid_E` while completion replaces result/destination. [top.v:285](../../riscv_core/rtl/top.v:285) gates RF writes with `valid_W`. Retained waveforms demonstrate suppressed writes on these same design bytes. |
| Load no longer lost when load-use flush meets memory stall (arm bug) | **Correction implemented; full regression unverified** | [hazard_unit.v:192](../../riscv_core/rtl/hazard_unit.v:192) masks `lwstall` with `~mem_stall_i`. New leaf probe confirms E/M holds with no load-use FlushE, and confirms ordinary non-stalled load-use bubbling remains. Existing [DEF-001](../../Verification/status/defects.csv:2) is FIXED-UNVERIFIED; ACT-010 still requests directed before/after regression. This is not every possible flush/stall interaction. |
| MUL/DIV during load stall no longer erases load; result held | **Fix absent; retain open** | [hazard_unit.v:192](../../riscv_core/rtl/hazard_unit.v:192) and [:199](../../riscv_core/rtl/hazard_unit.v:199) still include unmasked `stallMUL`; [execute_cycle.v:368](../../riscv_core/rtl/execute_cycle.v:368) gives FlushM priority over StallM. New leaf probe observes stalls and both flushes together. Earlier full-SoC waveforms demonstrate older-load loss. Completion buffering/backpressure qualification is not established. |
| One-cycle interrupts latched until taken | **Partly supported; narrow the claim** | [top.v:208](../../riscv_core/rtl/top.v:208) configures GPIO rising-edge and timers/SPI event capture; UART/I2C are levels. [irq_gateway.v](../../riscv_core/rtl/irq_gateway.v) retains edge/event captures until clear, capture winning over clear. New probe demonstrates event retention/clear/capture-wins and level deassertion. It does not demonstrate every source through acceptance, WB commit and handler. Multiple captured events can coalesce; asynchronous pulses can be missed if not sampled. |
| Unmapped jump now traps with cause 1 | **Claim contradicted here; fetch-fault capability remains missing** | [fetch_cycle.v:183](../../riscv_core/rtl/fetch_cycle.v:183) raises only alignment cause 0. The fetch interface in [top.v](../../riscv_core/rtl/top.v) has no external instruction-error input. SoC connects raw read data and leaves demux grant/response-valid unread. No new unmapped-fetch cause-1 path is present. Do not substitute a later illegal-data decode for the missing access-fault check. |
| RS2_D qualified by instruction use; false hazards removed | **Fix absent** | [decode_cycle.v:148](../../riscv_core/rtl/decode_cycle.v:148) still assigns `RS2_D = InstrD[24:20]` for all opcodes, and [:352](../../riscv_core/rtl/decode_cycle.v:352) registers the raw bits into EX. [hazard_unit.v:148](../../riscv_core/rtl/hazard_unit.v:148) compares both source fields. The leaf probe confirms a supplied Rs2 field alone triggers load-use. In a load those bits encode immediate low bits. This can add stalls, but the masked load-use term alone does not now erase a load during memory wait. |
| A nonexistent CSR such as 0x7C0 silently ignores writes | **Example is wrong; general access-validation gap remains** | [csr_regfile.v:106](../../riscv_core/rtl/csr_regfile.v:106) defines 0x7C0 as custom `mintprio`; [:126](../../riscv_core/rtl/csr_regfile.v:126) reads it and [:193](../../riscv_core/rtl/csr_regfile.v:193) writes its low two bits. Actual unimplemented addresses use the read-default zero and write-default ignore paths; `csr_valid_o` remains unconnected in the core. |

The screenshot's UART fixes, UART scratch register, AXI write-hang injection and GPIO driver-mode recommendations are outside this core-only cross-check. They are not marked verified by inference from the core checks.

### Corrections to the causal explanation

The screenshot correctly describes how an **unmasked** load-use flush can destroy an EX load while memory backpressure prevents it advancing: ID/EX checks FlushE before StallE. However, the current local source already masks the load-use term. The old explanation therefore describes an earlier/unidentified version, not an established current load-use failure here.

The separate MDU flush/stall bug is still present and must not be merged with DEF-001. Its flush source is `stallMUL`, not `lwstall`; masking one does not fix the other.

The DSRAM responder inserts a wait phase for a newly accepted read in [hybrid_mem_interface.sv:152](../../riscv_core/rtl/hybrid_mem_interface.sv:152). The claim that a two-load/consumer pattern is the only trigger is too narrow: a load-use dependency can overlap another kind of legal memory wait. True rs1 dependencies and false rs2-field matches can both raise lwstall.

The reported arm `s4=4` instead of 8, `bad calls 4000/4000`, and firmware occurrence counts (2 Pong, 9 arm) were not independently established: no matching ELF/disassembly, scan command/output, board trace or source identity accompanied the screenshots. Treat these as reported diagnostic hypotheses, not board-confirmed results or proof of rarity.

### Architectural reference correction

The screenshot's blanket assertion that every nonexistent CSR access is necessarily a specification violation also needs a pinned specification and platform contract. The published [CSR chapter](https://docs.riscv.org/reference/isa/v20240411/priv/priv-csrs.html) describes nonexistent-CSR accesses as reserved instructions and separately requires illegal-instruction exceptions for writes to read-only registers. Do not invent a waiver or change expected results: explicitly record the release's intended illegal-access policy and reference-model expectations. The definite local findings are silent default handling and the incorrect 0x7C0 example.

JALR target bit-zero clearing is an architectural requirement in the [RV32I JALR definition](https://docs.riscv.org/reference/isa/v20240411/unpriv/rv32.html). The local omission is not merely a selectable alignment policy.

## Updated core list

IDs beginning CORE below are local tracking labels introduced by this review. DEF-001, DEC-001 and EXC-002 retain their existing identities. Status separates implementation, execution evidence and signoff closure.

| ID | Finding | Updated status | Required closure evidence |
|---|---|---|---|
| DEF-001 | Load-use FlushE during memory stall loses held EX instruction | **Implemented correction; leaf-tested; full regression pending** | Exact older-memory-wait + EX load + ID consumer, genuine and false-field dependency variants, preserved before/after result and normal progress; reconcile ACT-010. |
| CORE-MVALID | MDU completion loses valid packet | **Open; reproduced on retained identical-source full-SoC runs** | Correct ownership/validity through WB and dependent consumers for MUL/DIV/REM; rerun original benchmark smoke and workloads. |
| CORE-MWAIT | MDU start/flush loses older waiting load | **Open; retained full-SoC failure plus fresh hazard observation** | Older load must complete once, value preserved, younger M result not dropped/duplicated under backpressure. |
| CORE-RETIRE | Held WB packet repeatedly increments minstret | **Open; reproduced on retained identical-source runs** | Independent unique-retirement ledger versus counter across stalls, exceptions, MRET, counter reads/writes and measurement windows. |
| DEC-001 | Opcode-only illegal decode accepts bad subencodings | **Open; static code unchanged and saved illegal seed evidence** | Independent legality tests and directed no-side-effect illegal trap, then seed/candidate regression. |
| EXC-002 | Younger MDU completion survives older synchronous trap | **Open; saved remote evidence; local vulnerability remains static** | Current local directed older-trap/younger-M tests and kill-versus-completion ordering; check registers, CSRs and memory. Remote/local implementation differences remain. |
| CORE-JALR | JALR fails to clear sum bit 0 before alignment checking | **Open static defect; no new runtime check** | Targets whose raw sum ends 01 must use aligned target; raw sum ending 11 remains misaligned after bit-0 clear on IALIGN=32. Verify fault PC/no wrong-path effects. |
| CORE-RSUSE | Decode treats unused source fields as register operands | **Open static/performance issue; comparison observed at leaf** | Opcode-specific actual source-use matrix and hazard/forwarding cases. Do not assert all extra stalls imply corruption. |
| CORE-IFERR | No unmapped instruction-fetch cause-1 path | **Missing capability / architecture obligation, not a verified fix** | Define platform access-fault contract and implement/test if required; no approved architecture change inferred. |
| CORE-CSRACC | Unsupported CSR read-zero/write-ignore, validity output unused | **Open contract/validation gap; screenshot's 0x7C0 example rejected** | Freeze CSR/address/access policy and reference expectations; test genuinely unsupported and read-only writes, with no-write CSR forms distinguished. |
| CORE-FETCH | spec_tag holds usable redirect target for extra cycle | **Open static timing finding; unchanged source** | Actual SRAM timing waveform through redirect/target acceptance; count redirect-to-decode separately from total branch penalty. |
| CORE-YMEM | Younger store/MMIO effect might escape older WB trap | **Unverified static risk** | External transaction ledger around an older trap; waveform proof of no younger memory effects. |
| CORE-MABORT | Late multiplier completion after IRQ abort; busy-MDU acceptance window | **Unverified static risks** | Real MDU issue/busy/done/abort windows, live ownership, replay/defer policy and no stale effects. Event input latching does not resolve execution cancellation. |
| CORE-CSRIRQ | IRQ acceptance versus older CSR writes | **Unverified ordering risk** | Older mstatus/mie/mintprio write versus eligibility/commit timing using independent expected ordering. |
| CORE-SWEXT | Software/external interrupt delivery absent | **Architecture gap unchanged** | SoC ties sw_irq_i/ext_irq_i low; arbiter selects cause 7 and 16–27 only. Record exact approved disposition or implementation and tests. |
| CORE-CSRCONTRACT | M-only MPP/SIE WARL, direct-only mtvec/dead vector branch, mepc masking | **Contract review; not all observations are bugs** | Pin architectural choices, compare to required behavior, then qualify with tests. Direct-only mtvec is not inherently defective. |
| CORE-X0 | Potential uninitialized synthesized x0 | **Conditional concern; earlier wording needs qualification** | Register[0] is zeroed on any clock not writing a nonzero register. With a reset clock that guarantees WE3 low, x0 is initialized despite simulation-only array initialization. Prove reset/integration assumptions before calling this an active bug; x1–x31 do not inherently require reset. |
| CORE-FWD | Result-source forwarding and CSR dependency timing questions | **Static review concern; no new demonstrated failure** | Producer/consumer checks for loads, JAL/JALR PC+4 and CSR old values across relevant stages. Comments alone do not establish a missing interlock bug. |
| CORE-IRQLATCH | Edge/event pending retention | **Implemented and leaf-demonstrated; per-source core integration pending** | Capture-mode/rearm/coalescing tests and correct matching WB clear through handler/MRET; do not require pulse latching for configured level inputs. |

## Next review actions

1. Identify the screenshot report's exact checkout/revision before transferring any claimed fixes to this source tree. The screenshots do not establish that another source version is wrong or that a correction was never made elsewhere.
2. Use DEF-001 as implemented-but-not-closed; preserve its outstanding directed regression. Keep MVALID/MWAIT/RETIRE open on this snapshot.
3. Preserve the failing benchmark baseline and proposed expectations. No DUT fix was attempted in this review.
4. Pin the ISA/privileged specification and unsupported-CSR policy. Correct the nonexistent-0x7C0 example in downstream summaries.
5. Continue focused current-core experiments for decode, JALR, precise exceptions and memory side effects before broadening regression. The new diagnostic probe is development evidence, not VCS signoff or FPGA validation.

## Reproduce the leaf probe

From repository root with WSL Icarus Verilog installed:

```sh
iverilog -g2012 -s tb_claim_probe -o artifacts/core_claim_review_20261109/probe.vvp ips/riscv_core/rtl/hazard_unit.v ips/riscv_core/rtl/irq_gateway.v artifacts/core_claim_review_20261109/tb_claim_probe.sv
vvp artifacts/core_claim_review_20261109/probe.vvp
```

The executable exits successfully when the observed local behavior matches the explicit checks, including observations of still-problematic flush/stall overlap. This is not a test that expects every DUT behavior to be architecturally correct.
