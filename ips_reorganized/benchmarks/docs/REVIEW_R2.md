# Independent Benchmark Harness Review (R2)

Date: 2026-11-04  
Scope: benchmark build and run tools, result analysis, firmware/result contract, SoC testbench, file-list generation, evidence, and `architecture.html`. Read `ips/AGENTS.md` and the benchmark documentation. No RTL or production design files were changed; this review adds only this document.

## Disposition

The R1 corrections are present: each run stages and validates its firmware images, ELF, metadata, and boot ROM; the simulator loads those staged files; ELF load bytes are compared with the actual SRAM images; preloaded results are rejected; terminal status requires an observed matching `RUNNING`; and counter deltas are bounded by observed post-boot clocks. The XSim response-file path and fixed diagnostic iteration count are also covered.

Two medium issues remain before treating the host result path as fail-closed for arbitrary run artifacts: a raw result can omit trap evidence and still validate, and the runner accepts a failed or forged build manifest. A conditional race also remains between hashing the live RTL tree and compiling it. None of these mismatches was observed in the retained campaign. No successful CoreMark or Dhrystone result, qualified retirement count, or published score is established.

## Findings

### Medium — Missing trap observation is treated as no trap

**File:** `ips/benchmarks/tools/analyze_results.py:148-151`

The analyzer rejects `trap_seen` only when its value is outside `(0, False, None)`. A missing field returns `None`, so an otherwise passing raw result is accepted without evidence that the testbench observed no trap.

**Reproduction:** Start from the passing fixture in `tests/test_results.py`, remove its `trap_seen` field, and call `analyze_result(..., expected_benchmark="coremark", expected_iterations=100)`. The current analyzer returns `valid: true` with no failure reasons.

**Impact:** An incomplete or older raw JSON record can produce a valid engineering estimate despite not satisfying the contract's no-trap requirement. The current testbench always emits this field, so the recorded simulator runs are unaffected; the host analyzer should still fail closed on absent evidence.

**Correction:** Require `trap_seen` to be exactly numeric zero or boolean false. Add negative cases for both a missing field and `null`.

### Medium — Failed or unverified build metadata is accepted for a run

**Files:** `ips/benchmarks/tools/run_benchmark.py:210-254`; `ips/benchmarks/tools/build_firmware.py:419-430,796-805`

Normal-run preflight checks benchmark name, ID, iterations, architecture, ELF bounds, and ELF/image equality. It does not require `build_status == "complete"`, validate `source_hashes`, or bind the ELF and SRAM images to output hashes in `build.json`. The builder reuses an existing output directory and writes a failed manifest on error without first removing prior output images.

**Reproduction:** In a temporary copy of the current CoreMark build directory, change only `build.json` to `build_status: "failed"` and replace `source_hashes` with an invalid hash entry. `validate_firmware(..., "coremark", 3, False)` accepts the staged image because its ELF and hex files still match.

**Impact:** After a failed rebuild, a caller using `-Action Run` can run stale artifacts left in the reused directory and retain a valid result with metadata that explicitly says the build failed or carries false source provenance. The current recorded campaign used completed builds; this finding affects future runs from incomplete or edited build directories.

**Correction:** Require a completed build manifest for normal runs, validate the provenance fields expected from the builder, and record/verify hashes for ELF and SRAM outputs in the build manifest. Make a failed build unable to leave runnable prior outputs in its output directory, or publish from a clean temporary directory only after successful completion.

### Low — HDL source hashes are fingerprints, not an immutable compile input

**Files:** `ips/benchmarks/tools/generate_filelists.py:243-267`; `ips/benchmarks/tools/run_benchmark.py:431-453`

The generated file lists resolve HDL paths back to the live repository tree. The generator hashes those files before compilation, and the runner does not recheck them after compile/elaboration. If a source changes between hash generation and the simulator reading it, the run can retain a source hash that does not identify the compiled bytes.

No mismatch was observed in the checked CoreMark run: all 102 source hashes and the three generated-file hashes still match the retained manifest, and the design baseline records no changed files. This is a concurrency limitation, not a finding that the recorded runs used different RTL.

**Correction:** Rehash every compiled source after compile/elaboration and fail if any differs from the recorded precompile digest, or compile from an immutable source snapshot.

### Low — Architecture page refers to a missing deliverables index

**File:** `ips/benchmarks/docs/architecture.html:106-108`

The page refers to `DELIVERABLES.md`, but no such file exists under `ips/benchmarks`. `KNOWN_FAILURES.md` and the benchmark README are present, but neither is the named deliverables index.

**Correction:** Update the reference to an existing file or add the promised index.

## Verification and evidence

- `py -3 -B -m unittest discover -s ips/benchmarks/tests -v`: **28 tests passed**. The suite covers staged-image consistency, bounds, result status, cycle plausibility, source lists, and simulator argument handling. It does not cover the two medium cases above.
- `py -3 -B ips/benchmarks/tools/fetch_sources.py --check`: **passed**; pinned vendor sources match their lock.
- The final TB guard batch `docs/evidence/tb_guards/guard_20261104T063315Z_d02d3391_summary.json` reports all three rejections observed: watchdog timeout, illegal instruction, and preloaded terminal result. The earlier watchdog fixture attempt failed by trapping because it did not load the full NOP image; `KNOWN_FAILURES.md` documents the correction and both evidence records remain available.
- The latest recorded full-SoC runs are: smoke `smoke_20261104T063104Z_966a0568` failed three checks (first error `0x00001001`, observed 1016 versus expected 2980); counter probe `counter_probe_20261104T063117Z_4d182349` passed as a diagnostic (38-cycle sample window, raw `minstret` delta 24 for an eight-instruction body, including reader overhead); CoreMark `coremark_20261104T063130Z_2322af4d` trapped with cause 6 at PC `0x00010fa4`, `mtval=0x0002092d`, before timing; Dhrystone `dhrystone_20261104T063143Z_0d61b923` trapped with cause 5 at PC `0x00010088`, `mtval=0x00040231`, before timing.
- The `architecture.html` preview at 1280 px reports four panels, no horizontal overflow, and no browser errors. Its recorded results match the latest campaign, aside from the missing `DELIVERABLES.md` reference noted above.
- `minstret`/CPI remain explicitly unqualified. The counter probe is a liveness diagnostic, not a counter-accuracy qualification. Compile/elaboration, firmware build, simulation, benchmark validation, and published scoring remain separate claims.

## Summary

The harness preserves the observed negative benchmark outcomes and the testbench guard checks; no false pass was observed in the recorded runs. The two medium findings should be closed before relying on arbitrary raw results or reused firmware directories as fail-closed, provenance-valid inputs. The live RTL hash window and missing documentation reference are lower-priority follow-ups. The actual CoreMark/Dhrystone workloads still require engineering diagnosis before any successful benchmark measurement can be claimed.
