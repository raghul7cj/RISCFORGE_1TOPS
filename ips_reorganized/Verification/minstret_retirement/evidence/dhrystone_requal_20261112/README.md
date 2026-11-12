# Dhrystone re-run on the closed retirement-counter source (12 November 2026)

This bundle records a fresh full-SoC Dhrystone re-run performed after issue
#16 ("minstret counts a held WB packet more than once") was closed in
`raghul7cj/RISCFORGE_1TOPS` commit
`eaca32ef031b9a16e3751462afb5fc2565d86bfa` (issue closed 2026-11-12
08:41:35Z).

No production RTL, testbench, firmware source, benchmark algorithm or memory
size was changed for this re-run. The pinned core RTL used here is
byte-identical to branch `verification_infra` at the published commit.

## What changed relative to the retained 11 November run

| Item | 11 Nov (retained) | 12 Nov (this bundle) |
| --- | --- | --- |
| Retirement counter | pre-fix baseline recorded in the same campaign | post-fix source, identical to the closed issue's fix commit |
| Analyzer verdict | `minstret`/`cpi` = unqualified (hard-coded conservative default) | qualified through an explicit qualification record, bound to pinned source hashes |
| Dhrystone counters | 10,163 cycles, 5,575 retired instructions, CPI 1.82296 | identical counters, reproduced exactly |

The unchanged counter values are the point: the fix changed *when* an
instruction is counted, not how many instructions the workload executes, so a
corrected counter and a workload that is stable produce the same totals here.
The re-run proves the numbers are reproducible on the closed source and that
the qualification claim is attached to the source that produced them.

## The two runs in this bundle

| Run | Simulator | Iterations | Timed cycles | Retired instructions | CPI | Cycles/iteration |
| --- | --- | --- | --- | --- | --- | --- |
| `run_dhrystone_20261112T091521Z_102701f4` | AMD Vivado XSim 2022.2, local | 10 | 10,163 | 5,575 | 1.82296 | 1,016.3 |
| `run_dhrystone_10000_iterations_xcelium` | Cadence Xcelium 24.09, `vlsi` server | 10,000 | 10,120,043 | 5,540,035 | 1.82671 | 1,012.0 |

Both runs: firmware status `pass`, zero validation errors, zero counter-check
failures, no trap, and the same qualified instruction/CPI verdict. The CPI
agrees across simulators to 0.2%, and the per-iteration cycle count to 0.4%,
which is the expected spread between two event schedulers on zero-delay
memory.

The 10,000-iteration run is the campaign-scale one: about 0.101 s of modeled
target time, 98,814 Dhrystones/second (DMIPS 56.24) as an *engineering
estimate*. It runs on the Cadence server, which completes in minutes where the
local XSim campaign would need hours.

Source binding for the remote run: 115 of the 117 sources listed by the
run's own `source_hashes.json` were re-hashed on the server and matched
byte-for-byte; the two exceptions are run-directory inputs (the generated
`benchmark_config.svh` and the boot ROM copy of the local run) that the
remote run replaced with its own generated equivalents. The record is in
`run_dhrystone_10000_iterations_xcelium/source_verification.json`.

## Qualification method

The analyzer no longer infers qualification from a constant. A run may claim
a qualified instruction counter only when it is given an explicit
`qualification_record.json` that

* names the issue and the fix commit it relies on,
* states the basis and the limits of the claim,
* pins the SHA-256 of the RTL sources that carry the fix
  (`ips/riscv_core/rtl/top.v`, `ips/riscv_core/rtl/csr_regfile.v`).

The analyzer verifies those hashes against the run's own
`source_hashes.json` and fails closed: a missing file, a changed file or a
missing hash list makes the analysis invalid and leaves the counters
unqualified. The default, with no record, is still the conservative
`unqualified` verdict, so existing evidence keeps its original meaning.

Record used here: `qualification_record.json` (copy of
`ips/benchmarks/qualification/retirement_counter_20261112.json`).

## What remains open

* The Dhrystone figure is an RTL-simulation engineering estimate; cycles come
  from simulation and the 100 MHz clock is modeled, not measured on hardware.
  `published_compliance` stays `false`.
* CoreMark is unaffected by this re-run and still fails the upstream
  minimum-duration rule (`0x3001`): 534,940 timed cycles are about 5.35 ms at
  the modeled clock against the required 10 seconds.
* The wider benchmark qualification obligations tracked in issue #23 remain
  open. Closing issue #16 does not close gate item 5.7.

## Files

| File | Content |
| --- | --- |
| `summary.json` | Machine-readable summary of both runs and the retained baseline |
| `qualification_record.json` | The qualification record applied to the analysis |
| `run_dhrystone_20261112T091521Z_102701f4/` | 10-iteration XSim run: analysis, raw mailbox, logs, images, source hashes |
| `run_dhrystone_10000_iterations_xcelium/` | 10,000-iteration Xcelium run: analysis, raw mailbox, xrun log, source verification |

## Reproduce

The 10-iteration local run:

```sh
# build the firmware (WSL, riscv64-unknown-elf-gcc 13.2)
python3 ips/benchmarks/tools/build_firmware.py --benchmark dhrystone \
  --iterations 10 --output-dir ips/benchmarks/build/firmware/dhrystone_requal_20261112

# run the full SoC in XSim and analyze with the qualification record
python ips/benchmarks/tools/run_benchmark.py --benchmark dhrystone \
  --firmware-dir ips/benchmarks/build/firmware/dhrystone_requal_20261112 \
  --simulator xsim --tool-bin C:/Xilinx/Vivado/2022.2/bin \
  --timeout-cycles 2000000 \
  --qualification-record ips/benchmarks/qualification/retirement_counter_20261112.json \
  --output-dir ips/benchmarks/runs
```

The 10,000-iteration campaign on the Cadence server: upload the design
sources, the testbench, the firmware images and the qualification record to
the `vlsi` host, then run

```sh
xrun -sv -timescale 1ns/1ps -f soc_benchmark.f -top soc_benchmark_tb \
  +incdir+. +IMEM_HEX=imem.hex +DMEM_HEX=dmem.hex +RESULT_JSON=result.json \
  +BENCHMARK_ID=4 +TIMEOUT_CYCLES=40000000
```

and analyze the produced `result.json` with

```sh
python ips/benchmarks/tools/analyze_results.py result.json --benchmark dhrystone \
  --iterations 10000 --qualification-record ips/benchmarks/qualification/retirement_counter_20261112.json \
  --source-hashes source_hashes.json --output analysis.json
```

Tooling change used by this evidence: `ips/benchmarks/tools/analyze_results.py`
gained an opt-in `--qualification-record` input, `run_benchmark.py` gained the
matching `--qualification-record` option, and
`ips/benchmarks/tests/test_results.py` gained four regression tests for the
default, qualified, mismatched-source and malformed-record paths.
