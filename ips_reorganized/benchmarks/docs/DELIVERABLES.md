# Benchmark infrastructure deliverables and evidence

Recorded: 2026-11-04. Implementation, execution evidence, three independent review rounds and the directed closure checks are complete. The review reports and responses retain the finding history. This is an engineering infrastructure handoff. CoreMark and Dhrystone have not passed on the current SoC, retirement accounting remains unqualified, and no published score is claimed.

## Start here

- [Workflow and one-command Windows entry point](../README.md)
- [Interactive HTML testbench architecture](architecture.html)
- [Firmware and port guide](FIRMWARE.md)
- [Harness, file lists and result interpretation](HARNESS.md)
- [Shared result ABI](../contract.json)
- [Machine-readable evidence index](DELIVERABLES.json)
- [Known runtime failures and proposed distinguishing experiments](KNOWN_FAILURES.md)

## Source deliverables

| Area | Files / purpose |
| --- | --- |
| Entry point | [benchmark.ps1](../benchmark.ps1): offline source check, WSL build, Windows XSim run, host tests. |
| Firmware | [startup](../firmware/start.S), [linker](../firmware/linker.ld), [runtime](../firmware/runtime.c), [result header](../firmware/benchmark.h), [smoke](../firmware/smoke.c), [counter probe](../firmware/counter_probe.c). |
| Benchmark ports | [CoreMark port](../ports/coremark/core_portme.c), [CoreMark configuration](../ports/coremark/core_portme.h), [Dhrystone validation](../ports/dhrystone/dhrystone_port.c), freestanding header shims. |
| Upstream identity | [source lock](../vendor/sources.lock.json), pinned sources and license texts under `vendor/upstream/`. |
| TB / design references | [soc_benchmark_tb.sv](../tb/soc_benchmark_tb.sv), [dedicated manifest](../filelists/soc_benchmark.f), [existing UART dependencies](../filelists/uart_runtime_dependencies.f). Original design RTL is referenced rather than copied. |
| Build tools | [fetch_sources.py](../tools/fetch_sources.py), [build_firmware.py](../tools/build_firmware.py), [generate_filelists.py](../tools/generate_filelists.py). |
| Run / analysis | [run_benchmark.py](../tools/run_benchmark.py), [analyze_results.py](../tools/analyze_results.py), [negative TB checks](../tools/check_tb_failures.py). |
| Packaging | [package_deliverables.py](../tools/package_deliverables.py): source plus selected build/run evidence; generated simulator caches excluded. |
| Review | [initial review](REVIEW_R1.md), [integrated review](REVIEW_R2.md), [closure review](REVIEW_R3.md), [response and correction record](REVIEW_RESPONSE.md). |

## Actual checks

- **39 host tests passed.** [Final test log](evidence/final_host_tests.txt). These cover source preflight, result identity/failures, address bounds, ELF/preload agreement, clock/delta plausibility, console verdict consistency, complete benchmark source inventories and stale terminal-state rejection. [All four actual console verdicts agree with the retained outcomes](evidence/final_log_marker_checks.json). [Final preflight closure](evidence/r3_closure_check.json) accepts all four genuine builds and rejects the reproduced incomplete CoreMark manifest.
- **Four actual RV32IM firmware targets compiled**, with explicit machine CSR reads and static memory fit. Compiler: WSL GCC 13.2.0. Build records include ELF, map, disassembly, both 8192-word SRAM images, source hashes and exact commands.
- **Full SoC and TB compiled and elaborated in XSim 2022.2.** Each selected run has its own compiler/elaboration logs and generated source lists. Existing RTL warnings are retained.
- **Three negative TB fixtures were rejected for the expected reason:** hang/watchdog, illegal instruction/trap, and a prepopulated terminal result. [Successful guard-check record](evidence/tb_guards/guard_20261104T063315Z_d02d3391_summary.json). Earlier failed fixture/launch attempts are also retained.
- **109 baseline design/manifest/header files are unchanged.** [Hash comparison](evidence/design_unchanged.json), [baseline hashes](design_baseline.json).
- **HTML checked at desktop and mobile widths**, in light and dark appearances, with no horizontal overflow or reported JavaScript exception in the inspected views.

XSim uses the source tree's existing `XSIM` compatibility branches for unsupported assertion syntax. The benchmark TB's own failure guards are enabled. These runs do not establish all default RTL assertion coverage or the checklist's VCS signoff requirement. VCS/Xcelium command paths are implemented but were not executed here.

## Linked firmware sizes

| Image | Iterations | ISRAM text | Static DSRAM | Remaining static stack margin |
| --- | ---: | ---: | ---: | ---: |
| Smoke | 1 | 2,616 B | 732 B | 32,036 B |
| Counter probe | 1 | 2,304 B | 716 B | 32,052 B |
| CoreMark | 1 | 11,856 B | 4,352 B | 28,416 B |
| Dhrystone | 10 | 6,220 B | 12,408 B | 20,360 B |

The linker enforces at least 4 KiB of margin. Static margin is not a measured dynamic stack high-water bound. Both benchmarks fit the current SRAMs in these builds.

## Actual full-SoC executions

All four used a modeled 100 MHz clock, a 2,000,000-cycle watchdog, the current full SoC and an independently staged firmware/ROM snapshot.

| Workload | Outcome | Evidence |
| --- | --- | --- |
| Smoke | FAIL: 3 arithmetic checks; first code `0x1001`, expected accumulation 2980, observed 1016. | [analysis](../runs/smoke_20261104T065353Z_7108f0a2/analysis.json), [raw](../runs/smoke_20261104T065353Z_7108f0a2/result.json), [metadata](../runs/smoke_20261104T065353Z_7108f0a2/run_metadata.json), [simulation log](../runs/smoke_20261104T065353Z_7108f0a2/simulation.log). |
| Counter probe | PASS for diagnostic execution, result transport and liveness. Raw window: 38 cycles, 24 unqualified minstret increments; eight-instruction body plus measurement overhead. | [analysis](../runs/counter_probe_20261104T065406Z_9f3abc11/analysis.json), [raw](../runs/counter_probe_20261104T065406Z_9f3abc11/result.json), [metadata](../runs/counter_probe_20261104T065406Z_9f3abc11/run_metadata.json), [simulation log](../runs/counter_probe_20261104T065406Z_9f3abc11/simulation.log). |
| CoreMark | FAIL: cause 6, PC `0x10fa4`, address `0x2092d` in `core_list_init`, before timing/CRC validation. | [analysis](../runs/coremark_20261104T065419Z_d28e58b8/analysis.json), [raw](../runs/coremark_20261104T065419Z_d28e58b8/result.json), [metadata](../runs/coremark_20261104T065419Z_d28e58b8/run_metadata.json), [simulation log](../runs/coremark_20261104T065419Z_d28e58b8/simulation.log). |
| Dhrystone | FAIL: cause 5, PC `0x10088`, address `0x40231` in `emit_unsigned`, before timing/final-state validation. | [analysis](../runs/dhrystone_20261104T065432Z_8cffc712/analysis.json), [raw](../runs/dhrystone_20261104T065432Z_8cffc712/result.json), [metadata](../runs/dhrystone_20261104T065432Z_8cffc712/run_metadata.json), [simulation log](../runs/dhrystone_20261104T065432Z_8cffc712/simulation.log). |

The failing programs remain useful baselines. This task established infrastructure and exposed runtime findings; it did not diagnose or correct the underlying core/runtime behavior. The expected arithmetic, upstream CRC validation and trap checks were preserved.

## Reproduce and package

```powershell
.\ips\benchmarks\benchmark.ps1 -Action CheckSources
.\ips\benchmarks\benchmark.ps1 -Action Test
.\ips\benchmarks\benchmark.ps1 -Action All -Benchmark counter_probe
.\ips\benchmarks\benchmark.ps1 -Action All -Benchmark smoke
.\ips\benchmarks\benchmark.ps1 -Action All -Benchmark coremark -Iterations 1 -TimeoutCycles 2000000
.\ips\benchmarks\benchmark.ps1 -Action All -Benchmark dhrystone -Iterations 10 -TimeoutCycles 2000000
py -3 ips/benchmarks/tools/package_deliverables.py
```

The wrapper defaults to one iteration; the direct Dhrystone builder defaults to ten. Run consumes the count from the existing image's build metadata; `-Iterations` changes only Build/All.

The archive includes the benchmark sources, documentation, selected ELF/images/maps/disassembly, raw results, logs, metadata and a per-file SHA-256 manifest. It excludes large simulator caches and original design RTL. Use it alongside the matching repository checkout, where the file lists can resolve the original SoC sources. A ZIP CRC check and a separate SHA-256 receipt accompany packaging. It is not a standalone chip-design archive.
