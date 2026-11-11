# Review response and integration corrections

All delegated planning, implementation and review tasks were requested as `gpt-6-luna`, `reasoningEffort=xhigh`, provider `codex`. Returned task selections matched that request. The parent integrated the interfaces and collected the full-SoC runtime evidence.

## Initial independent review

The full findings remain in [REVIEW_R1.md](REVIEW_R1.md). No finding was discarded to obtain a pass.

| Finding | Response and evidence |
| --- | --- |
| Simulator could read mutable inputs instead of hashed copies | Firmware/ELF/map/disassembly/build metadata and ROM are staged first. Preflight validates the staged copies. All simulators load run-local image names, the ROM `defparam` uses the staged ROM, and generated file-list/config hashes are retained. |
| Preloaded PASS could bypass actual execution | Host rejects a nonempty reserved result block; TB independently requires an empty preload and observes matching RUNNING before a terminal state. Actual negative-fixture simulation rejected a preloaded PASS. |
| Checked ELF was unrelated to executable SRAM images | Preflight reconstructs load bytes, BSS zero-fill and zero SRAM defaults, compares preload contents, rejects extra payload and verifies entry/ABI/bounds. Negative tests reject stale/missing instructions and extra data. |
| Impossible counter deltas accepted | Analyzer requires a positive observed cycle count and rejects deltas larger than the whole post-boot window. It also rejects a firmware clock declaration that differs from the TB's clock. |
| Run iteration parameter ambiguous | README, launcher and deliverable guide state that Iterations changes Build/All; Run consumes the existing build metadata. Smoke/probe reject counts other than one because their bodies are fixed diagnostics. |

## Additional integration corrections

- Fixed nested-list metadata traversal; preserved its original NameError in the failing test log.
- Enforced sparse hex address bounds and rejected repeated word addresses.
- Changed XSim launch to a response file after actual Windows batch-launch failures. XSim can return zero after TB `$fatal`, so the host still requires a checked PASS record.
- Required a consistent console PASS marker and rejected a console FAIL/fatal even if structured JSON claims PASS. Rechecked the four actual logs and added positive/contradictory-marker host tests.
- Collected validation failures at terminal status so firmware can finish writing its first error code and expected/observed data.
- Sampled trap commits at the clock edge and retained cause, PC and trap value together.
- Published the counter probe's eight raw snapshot words; its original zero-export failure remains in the earlier run record.
- Preserved all smoke arithmetic expectations and benchmark validation failures.
- Corrected a negative watchdog fixture to fill instruction SRAM with NOPs. The earlier one-word fixture correctly trapped on zero-filled instruction memory and is retained.

## Integrated review

The second review is preserved in [REVIEW_R2.md](REVIEW_R2.md). Its two medium findings were corrected: missing/null trap observation now fails analysis, and normal runs require completed build status, matching declared source provenance and hashed staged outputs. The builder invalidates a prior complete manifest before starting a rebuild. Unit checks reproduce absent trap evidence, failed rebuild metadata, forged source hashes, changed ELF and missing output hashes.

The HDL hash-window follow-up was also addressed with a postcompile fingerprint recheck for each backend. The design remains referenced from its live checkout; a before/after fingerprint is not an immutable RTL snapshot. A directed host test mutates a source after fingerprinting and requires rejection.

The promised index exists at `docs/DELIVERABLES.md`, adjacent to the architecture page. It was written while the second review was running; the original review finding is retained unchanged.

A third Luna xhigh review is limited to closing these acceptance changes and checking the final default workflow. Its result is recorded in `REVIEW_R3.md`.

## Closure of the R3 completeness finding

[REVIEW_R3.md](REVIEW_R3.md) confirmed the prior fixes and identified one related missing-source-inventory check. The parent added explicit required port/upstream file sets for CoreMark and Dhrystone and bound each required build-local entry-point/header record to its actual staged output path. Empty groups or omitted ported-source records are now rejected.

The exact review reproduction was repeated using a temporary copy of the real CoreMark build: emptying both groups now fails with `missing required coremark ports source hashes`. All four genuine builder manifests remain accepted. [Directed closure evidence](evidence/r3_closure_check.json) records both the positive compatibility check and the rejection. The original build directories were untouched by that reproduction.

The final host suite has **39 passing tests**. This last correction restricts preflight acceptance; it changes neither firmware computation nor RTL. The latest four full-SoC execution records remain the runtime evidence. R3's original report is retained unchanged; this response and its directed tests record the subsequent correction, rather than claiming a fourth independent review occurred.
