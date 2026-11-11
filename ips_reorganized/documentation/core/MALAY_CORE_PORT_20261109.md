# Selective malay core port into verification_infra

> **11 November retirement update:** the held-WB counter input is corrected and the 29-bin/12-run directed checklist passes. Fresh full-SoC smoke/probe/Dhrystone pass; CoreMark CRCs match but its short-duration failure remains. [Current source-backed diagrams, evidence and limits](MINSTRET_RETIREMENT_20261111.md). Issue #16 remains open for counter-write/collision and benchmark-window qualification. Original port text below is historical.

**10 November review correction:** the report's JALR missing-bit-zero-mask allegation is withdrawn. The existing ALU already computes (A+B) & ~32'd1 for JALR control 0110, selected by the decode chain. GitHub #17 was incorrectly filed and is now closed; JALR runtime coverage remains pending. Original port/provenance text below is preserved.

Base: `58af373e031e64c78b867cdbcbc86518b3fc6ec9`. Donor: `18fb4baac942e2e87921002dd1ae5fb8d084ceb8`. The target source tree is **ips_reorganized/**. This is a selective implementation port, not a whole-branch merge.

## Changes and provenance

- MDU completion carries a valid result, destination and originating PC; completion is retained across EX/MEM backpressure. Adapted from malay commits 629fce7 and a5cbb4c while preserving the target IRQ/class/abort interfaces.
- MDU FlushM is suppressed during an older memory wait. The already-present load-use memory-stall mask is preserved.
- MDU issue now requires a live non-excepting EX instruction and a free owner, and waits for older memory work. WB redirects clear the outstanding owner/held result and abort the engine. Each multiplier pipeline valid is also cancelled: a direct test exposed a lost new DIV after an aborted MUL when only the old owner's bit was cleared. Its failing log and corrected run are retained. This is integration-specific safety work beyond copying donor hunks.
- EX branch/JAL/JALR redirects wait for MEM to advance so that the link packet is not discarded. Adapted from e9da2e1. This does not correct JALR sum bit-zero clearing.
- Parameterized cause-1 fetch-map checks and SoC BootROM/ISRAM ranges, adapted from 1edf249. Core-only harnesses remain unrestricted unless FETCH_CHECK_ENABLE is selected. SoC enables the two concrete half-open regions. The subtraction-based range test avoids a constant-unsigned warning when the ROM base is zero.
- RS2 decode hazard input is used only for R/store/branch instructions, adapted from c74064e; raw EX forwarding fields remain intact. RS1 qualification is still separate work.
- Instruction opcode/subfield legality checks and software-write mepc low-bit masking, adapted from b1fda57. The target CSR map, custom mintprio at 0x7C0, MRET policy and 13-source IRQ gateway/arbiter are preserved.

## Evidence obtained

- Icarus 12.0: 13 directed current-core configurations pass. Unchanged-base comparison retains 11 failing configurations and two passing guards; tests and expected values are the same between them.
- Tests cover M arithmetic families and edge cases, immediate consumers, older-load/M overlap, consecutive loads, redirect/link during waits, illegal cause-2 metadata, unmapped-fetch cause-1 metadata, mepc masking and one older-ECALL/younger-DIV guard. Data waits are 0, 1 and 4 cycles for the arithmetic/load/redirect cases.
- Independent field-policy sweep: 131,072 opcode/funct3/funct7 combinations plus exact ECALL/EBREAK/MRET/WFI guards pass. CSR addresses and arbitrary operand/architectural state are outside this sweep.
- Execute-stage tests pass: held completion exactly once with its original PC, killed MUL suppression, killed DIV suppression, and correct new DIV result after MUL cancellation.
- Full-SoC Verilator 5.020 elaboration via the complete tier3 verification filelist: zero errors; 107 retained warnings in both base and candidate. XSIM compatibility disables some unsupported assertion syntax. This is not clean SpyGlass/VCS signoff.
- Runnable sources, selected before/after logs, source hashes and detailed results are in Verification/core_port_20261109/.

## Unsolved from the core-benchmark perspective

1. **minstret still counts a held WB packet repeatedly.** The retirement input remains valid_W & ~exc_valid_W; unique retirement/CPI is not qualified. Do not publish CPI or instruction counts from it.
2. **CoreMark and Dhrystone must be rerun on the integrated SoC.** These focused core tests address mechanisms behind the saved failures but do not establish CRC/final-state correctness, measured scores, compliant duration or clean complete benchmark execution.
3. **JALR target bit 0 remains uncleared.** Both source branches had this defect; it was not represented as an existing donor fix.
4. **Extra spec_tag fetch hold remains.** The controller is unchanged. Measure redirect-to-decode versus total branch penalty before performance claims.
5. **Broader memory-latency and MDU/IRQ interaction coverage remains.** Fixed directed waits are not a randomized latency campaign. IRQ acceptance during an MDU's busy bubble and replay/defer timing need their own tests.

## Unsolved or not yet closed from the RISC-DV perspective

1. **Saved failing seeds have not been rerun.** The legality port addresses the representative bad subencoding, and MDU ownership/cancellation has directed checks, but DEC-001/EXC-002 do not gain campaign closure from these tests alone. Restore exact generated images, reference configuration, DUT filelist and seed identity; rerun illegal seed 22 and the other failed illegal seeds, misaligned seeds 21/38 and unaligned load/store seed 38.
2. **Precise exceptions remain broader than the MDU guards tested here.** Cover all M phases and kill/completion coincidence, older exceptions of different origins, IRQ overlaps and younger GPR/CSR/store/MMIO effects. The new safety logic is not a complete proof.
3. **CSR-address/access validation and the platform contract remain open.** Keep custom mintprio at 0x7C0. Specify actual unsupported/read-only access expectations and CSR WARL/M-mode behavior against the pinned ISA and reference model; do not import malay's removed CSR map.
4. **GPR-only comparator/logging limits remain.** Saved comparison needs retirement identity, CSR state and memory effects; a tohost completion or final register convergence cannot establish precision.
5. **RISCOF/official ISA regression and tool acceptance remain pending.** This PR does not supply a fresh architectural compliance pass, coach disposition or coverage closure.
6. **RS1 false dependencies, fetch-fault boundary combinations and external memory effects need wider tests.** One selected unmapped address is checked; all region endpoints, redirect/stall precedence and the physical response contract are not exhaustively verified.

## Other core obligations preserved

Software/external interrupt delivery remains tied off at the SoC; PLIC/CLINT/CLIC alternatives need exact disposition. Source-to-handler interrupt validation, CSR-write/IRQ races, M-only CSR policy, forwarding corner checks and the conditional synthesized-x0 initialization concern remain separate. The peripheral/UART fixes on malay were not included.

The evidence above supports a focused functional integration. It does not close G4/G5/G6, authorize a tapeout freeze or validate an FPGA bitstream. Historical failures are retained.
