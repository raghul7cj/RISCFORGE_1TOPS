# Independent benchmark harness closure review (R3)

Date: 2026-11-04  
Scope: focused closure review of R1/R2 responses, provenance preflight, result analysis, source rechecks, deliverable index, and the latest four-run XSim campaign. This review writes only this report; it makes no RTL or implementation changes.

## Disposition

The R1 findings are closed in the reviewed snapshot. Both specific R2 medium reproductions now fail closed: missing or invalid trap evidence is rejected, and failed build metadata or a recorded source digest that does not match the current file is rejected. The Windows PowerShell test entry point passes all 37 host tests, the pinned-source check passes, and the runner accepts all four real builder manifests.

One related medium provenance gap remains: a complete CoreMark build manifest can omit every hash for its compiled port and upstream algorithm sources and still pass normal-run preflight. See the finding below. Therefore, source provenance is improved but not yet fail-closed for incomplete benchmark source inventories.

## Finding

### Medium — A complete benchmark manifest may omit hashes for compiled benchmark sources

**File:** `ips/benchmarks/tools/run_benchmark.py:210-225`

The runner requires `firmware`, `ports`, `upstream_files_compiled`, and `build_tools` to be dictionaries, and requires selected common firmware/tool hashes. It does not require benchmark-specific port or upstream source records for CoreMark or Dhrystone. Empty dictionaries satisfy the current structure check.

**Reproduction:** In a temporary copy of the actual CoreMark build directory, retain `build_status: "complete"`, ELF/images and all other metadata, but replace `source_hashes.ports` and `source_hashes.upstream_files_compiled` with empty objects. Calling `validate_firmware(temp_dir, "coremark", 3, False)` accepts the build and reports `source_files_verified: 7`, `output_files_verified: 6`. The actual CoreMark manifest contains two port files and four compiled upstream files, so the accepted copy no longer fingerprints those inputs. The original build directory was not modified.

**Impact:** An incomplete or edited manifest can leave the executable ELF and images runnable without binding them to the benchmark implementation sources. This leaves a gap in the provenance check for ordinary stale or malformed build metadata, even though a recorded but incorrect digest is rejected.

**Suggested correction:** Require the benchmark-specific compiled-source inventory emitted by the builder, including CoreMark/Dhrystone port files and upstream files, and require a valid current digest for each. Add a negative test that empties these groups for a real benchmark build while keeping its status and outputs complete. This is a completeness check; it does not require cryptographic signatures or claim proof against a malicious author who can rewrite every manifest field.

## R2 closure checks and integration evidence

- **Trap evidence:** `analyze_results.py` accepts only exact `false` or integer `0` for `trap_seen`, and only exact `true` or integer `1` for `running_seen`. The host tests cover missing, null, and floating-point zero trap values; all are rejected. A positive valid-result fixture remains accepted.
- **Failed/forged build metadata:** a failed build status is rejected. The prior wrong-source-digest reproduction is rejected with a source SHA-256 mismatch. Tests also reject missing output hashes and an ELF whose bytes no longer match its recorded output hash.
- **Real builder compatibility:** normal preflight accepted smoke, counter probe, CoreMark, and Dhrystone build outputs. The latest run records report respectively 8, 8, 13, and 13 verified source files, with 5, 5, 6, and 7 verified output files. Build output digests are SHA-256 hex strings, and source/output paths are checked against their intended roots.
- **Source rechecks:** the runner calls the source snapshot recheck after XSim compile/elaboration, after VCS compile/elaboration, and after the single Xcelium `xrun` invocation. Each of the four latest XSim run records reports 120 source/generated files rechecked. VCS and Xcelium command paths were inspected but were not executed in this campaign.
- **Host checks:** `benchmark.ps1 -Action Test` completed with **37 tests passed**. `benchmark.ps1 -Action CheckSources` verified the pinned sources.
- **Deliverables reference:** `docs/DELIVERABLES.md` exists and the adjacent reference in `architecture.html` resolves to it.

## Latest full-SoC outcomes

The new runs under `ips/benchmarks/runs/` reproduce the previous campaign outcomes and do not claim benchmark qualification:

| Workload | Latest run | Result |
| --- | --- | --- |
| Smoke | `smoke_20261104T065353Z_7108f0a2` | Failed three arithmetic checks; expected accumulation 2,980, observed 1,016 (`0x03f8`), first error `0x1001`. |
| Counter probe | `counter_probe_20261104T065406Z_9f3abc11` | Diagnostic pass; 38-cycle timing window, raw `minstret` delta 24 for an eight-instruction body plus measurement overhead. Retirement accounting remains unqualified. |
| CoreMark | `coremark_20261104T065419Z_d28e58b8` | Trapped before timing: cause 6, PC `0x00010fa4`, `mtval=0x0002092d`. |
| Dhrystone | `dhrystone_20261104T065432Z_8cffc712` | Trapped before timing: cause 5, PC `0x00010088`, `mtval=0x00040231`. |

The analyzer preserves these failures. No CoreMark/Dhrystone pass, qualified retirement count, or published score is established. The source snapshot mechanism fingerprints the live design files before tool use and rehashes them afterward; it is not an immutable RTL snapshot or a cryptographic source-to-binary attestation. The actual design/runtime failures remain outside this infrastructure review, and no design RTL was changed.
