# Independent benchmark harness review (R1)

Date: 2026-11-04  
Scope: stable harness, result analyzer, file-list generator, testbench, launcher, contract, and documentation. Firmware port/build files were changing during this review and are not reviewed here. No production files or design RTL were edited.

## Findings

### High — The run metadata can hash different inputs from those used by the simulator

**Files:** `ips/benchmarks/tools/run_benchmark.py:347-352,395-396,420-428,439-447`; `ips/benchmarks/tools/generate_filelists.py:221-228`.

The runner copies `imem.hex`, `dmem.hex`, and the boot ROM into the unique run directory and records hashes for those copies, but XSim/VCS/Xcelium receive the original firmware-directory paths. The generated ROM include also points to the repository's live boot-ROM path; the copied run ROM is not used by the DUT. If a concurrent build or manual replacement changes an input after validation/copy, the simulation can consume bytes different from the recorded firmware and copied-input hashes. The captured metadata then does not identify the actual simulated inputs.

**Minimal correction:** stage immutable images first, validate and hash those staged copies, pass their paths to every simulator, and generate the TB ROM path from the staged ROM. Record or verify the exact generated file-list hashes as part of the same run snapshot.

### High — A preloaded terminal mailbox can satisfy the testbench without observing firmware enter RUNNING

**File:** `ips/benchmarks/tb/soc_benchmark_tb.sv:300-305,319-356`.

The TB preloads `dmem.hex`, then checks mailbox status after boot. It accepts `PASS` whenever magic, version, ID, zero validation errors, and a nonzero cycle delta match; it does not require the mailbox to have been empty initially or observe `RUNNING` before terminal `PASS`. Therefore, a stale or crafted DSRAM image containing a terminal pass record can produce `BENCH_TB_PASS` before benchmark firmware publishes a new result. The host trusts that marker and mailbox, so this can be counted as a functional pass without executing the benchmark.

**Minimal correction:** require a zero/empty initial result block and explicitly record a matching `RUNNING` transition after firmware starts before accepting terminal status. Preserve the transition evidence in raw JSON.

### High — The checked ELF is not tied to the SRAM images that actually execute

**File:** `ips/benchmarks/tools/run_benchmark.py:142-210`.

Preflight validates ELF class, machine, and PT_LOAD bounds independently from the hex images. It checks hex syntax/address bounds and records separate hashes, but never proves that `imem.hex`/`dmem.hex` encode the checked `program.elf` or match output hashes declared by `build.json`. A valid benchmark ELF and metadata can therefore be paired with stale or unrelated SRAM images; the reported architecture/source identity may describe a different program from the one run. This also makes the preloaded-mailbox path above easier to trigger accidentally.

**Minimal correction:** have the build manifest include deterministic image hashes and require exact matches, or reconstruct the expected SRAM images from the ELF and compare their contents before running. Keep the existing hash record for provenance.

### Medium — Counter deltas are not bounded by independently observed simulation cycles

**Files:** `ips/benchmarks/tools/analyze_results.py:139-169`; `ips/benchmarks/tb/soc_benchmark_tb.sv:79,184,352-356`; `ips/riscv_core/rtl/csr_regfile.v:152-154`.

The analyzer accepts any nonzero modulo-64-bit `mcycle` delta and can calculate an estimate without comparing it to `observed_clock_cycles`. The RTL increments `mcycle` once per core clock, while the TB independently counts post-boot clocks, so a firmware delta larger than the whole observed simulation is impossible for these benchmark images (which document that they do not write/reset the counter) and should fail closed.

**Reproduction:** a read-only call to `analyze_result` with a pass mailbox, `cycle_delta=1,000,000,000`, and `observed_clock_cycles=6,000` returned `valid: true` and produced a CoreMark engineering estimate. No simulator was involved in this probe.

**Minimal correction:** require a positive integer observed-cycle count and reject an `mcycle` delta exceeding the observed post-boot cycle window (with a documented tolerance only if a measured boundary justifies one). Keep `minstret` unqualified as it is now.

### Low — `benchmark.ps1 -Action Run -Iterations N` silently ignores `N`

**File:** `ips/benchmarks/benchmark.ps1:17-18,74-85`.

`-Iterations` is forwarded to `build_firmware.py` for `Build`/`All`, but `Run` does not pass or compare it; the runner derives the expected count from the existing `build.json`. A caller can request `-Action Run -Iterations 10` against a one-iteration image and still run one iteration without a mismatch. This may be intentional because `Run` consumes an existing build, but the parameter makes the command ambiguous.

**Minimal correction:** document that `-Iterations` only applies to `Build`/`All`, or make `Run` compare it with the firmware's declared iteration count and fail on mismatch.

## Verified behavior and remaining evidence

- `py -3 -B -m unittest discover -s ips/benchmarks/tests -v`: **17 tests passed**. The current tests cover metadata lists, sparse/out-of-range/repeated SRAM addresses, unknown hex bits, analyzer mismatch/failure paths, and file-list source checks.
- Current preflight rejects `@ffff`-style out-of-range SRAM addresses; the list-recursion issue noted in the original review brief is fixed in the current snapshot.
- The TB uses case-aware status/magic checks, checks benchmark ID and firmware validation errors, detects traps and sticky bus timeouts, and preserves terminal failures. `minstret`/CPI remain labeled unqualified; no duplicate-retirement expectation was added. CoreMark short-run score output remains explicitly engineering-only with published compliance false.
- The reported XSim full-DUT compile/elaboration used a compile-only fixture. That establishes compile/elaboration compatibility only. I found no real firmware simulation or CoreMark/Dhrystone validation evidence in the stable harness snapshot; no benchmark correctness, counter qualification, or performance result is established by this review.
