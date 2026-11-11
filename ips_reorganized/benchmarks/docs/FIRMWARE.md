# RISCFORGE benchmark firmware

This directory builds bare-metal images for the RISCFORGE benchmark result
contract. The build layer contains a checked smoke workload, a diagnostic
counter probe, EEMBC CoreMark 1.0, and the RISC-V tests Dhrystone C Version 2.2
port. Firmware is linked for ISRAM at `0x00010000` and DSRAM at `0x00020000`.

## Source pins and offline builds

`vendor/sources.lock.json` pins the upstream commits and records the SHA-256 of
each downloaded source, header, and license file. The upstream files remain
under `vendor/upstream/`; do not edit them. `tools/fetch_sources.py` downloads
the exact pinned files and writes the lock on initial fetch. Once the vendor
tree and lock are present, builds are offline and verify every file before
compilation:

```powershell
python ips/benchmarks/tools/fetch_sources.py
python ips/benchmarks/tools/fetch_sources.py --check
```

The default source pins are [EEMBC CoreMark](https://github.com/eembc/coremark/tree/1f483d5b8316753a742cbf5590caf5bd0a4e4777)
and [RISC-V tests Dhrystone](https://github.com/riscv-software-src/riscv-tests/tree/3df703cd52d5f0d8224e3c50bf03c6cb70efff98).
The bundled CoreMark license text is `vendor/upstream/coremark/LICENSE.md`
(EEMBC Acceptable Use Agreement and Apache 2.0 text). Dhrystone uses the
RISC-V tests repository license at `vendor/upstream/dhrystone/LICENSE`.

## Build commands

The WSL toolchain used for the recorded builds is GCC 13.2.0:

```powershell
wsl.exe -e python3 "/mnt/c/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/benchmarks/tools/build_firmware.py" --benchmark smoke
wsl.exe -e python3 "/mnt/c/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/benchmarks/tools/build_firmware.py" --benchmark counter_probe
wsl.exe -e python3 "/mnt/c/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/benchmarks/tools/build_firmware.py" --benchmark coremark --iterations 1
wsl.exe -e python3 "/mnt/c/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/benchmarks/tools/build_firmware.py" --benchmark dhrystone --iterations 10
```

The CLI accepts `--benchmark smoke|counter_probe|coremark|dhrystone`,
`--iterations N`, `--output-dir PATH`, `--clock-hz HZ`,
`--arch rv32im_zicsr|rv32i_zicsr`, and `--cc PREFIX_OR_GCC_PATH`. Defaults are
RV32IM/Zicsr, 100 MHz, and 1/1/1/10 iterations respectively. Smoke and the
counter probe are fixed one-iteration diagnostics; other iteration counts for
those two targets are rejected rather than misreported. CoreMark and Dhrystone
accept the selected positive iteration count. The default
compiler is `riscv64-unknown-elf-gcc`; `-lgcc` is linked explicitly. There is
no silent architecture fallback. An explicit `rv32i_zicsr` build is a separate
configuration and can use libgcc software arithmetic.

Each build writes to `build/firmware/<benchmark>/` unless `--output-dir` is
given. Outputs are:

- `program.elf`, `program.map`, and `program.dis`;
- full-size `imem.hex` and `dmem.hex` images, each 8192 little-endian words;
- `build.json` with compiler, flags, pinned and local source hashes, contract
  hash, memory fit, output paths, and SHA-256 hashes of ELF/images/map/disassembly
  and build-local ported sources;
- `build.log` with the exact argument arrays and compiler output.

The images are 32 KiB each and are based at their respective SRAM origins.
`.text` is in ISRAM; `.rodata`, `.data`, and `.bss` are in DSRAM. Initialized
DSRAM bytes are present in `dmem.hex`; startup clears `.bss`. The linker keeps
`_start` and asserts that at least 4 KiB remains between the end of static
DSRAM allocation and stack top `0x00028000`. `build.json` reports that static
stack margin; it does not claim a dynamic stack high-water proof.

Build completion is compilation and image generation only. The firmware has
not been executed on the RTL by this build layer. Separate run evidence and its
actual outcomes are indexed in [DELIVERABLES.md](DELIVERABLES.md).

Before invoking build tools, the builder writes an `in_progress` manifest into
the selected output directory. It writes `complete` only after output generation
and hashing, or `failed` after a build error. Old images can remain as evidence,
but the runner rejects them under an incomplete/failed manifest or a mismatched
output hash. Normal Run also requires declared local source hashes to match the
current benchmark source checkout; rebuild after changing those sources.

## Result block and timing

The linker reserves all 256 bytes at `0x00020000` as a `NOLOAD` result block,
before DSRAM read-only data, initialized data, or BSS. Startup BSS clearing
does not touch this reservation. Firmware clears all 64 words, writes the
contract magic/version/benchmark ID and parameters, then writes `running`.
Terminal `pass` or `fail` status is the final result-block write. The 29
defined result fields are 32-bit words in the exact order from
`contract.json`; the remaining 35 words stay zero.

Both counters are read through machine CSRs only. Each 64-bit read uses
high-low-high retry over `mcycleh/mcycle` or `minstreth/minstret`; no
`rdcycle`/`rdinstret` aliases are used. Each start and end snapshot reads
`mcycle` first and `minstret` second. `timing_phase` is set to 1 before the
start reads and stays at 1 through the end reads; it becomes 2 afterward. It
marks a diagnostic window, not the exact CSR sample instant. The counter probe
also publishes all eight raw snapshot words after its measured body. Firmware does not
reset either counter or claim that the two counter samples are simultaneous.

`console_word` publishes each output byte with a wrapping 24-bit sequence in
bits 31:8. The firmware filters target-side rate/score lines; host software
should derive metrics from the raw absolute snapshots and the configured
`clock_hz`.

Result flags are:

| Bit | Meaning |
| --- | --- |
| 0 | `minstret` and CPI/IPC remain unqualified |
| 1 | Current RTL MDU and retirement caveats apply |
| 2 | CoreMark elapsed cycles are below its 10-second rule |
| 3 | Counter probe is diagnostic only |

The `counter_checks` bits report nonzero cycle delta, nonzero `minstret` delta,
and monotonic snapshots. The probe's assembly body contains eight explicit
`addi x0,x0,0` instructions (`probe_expected = 8`). `probe_observed` is the raw
`minstret` delta across the entire snapshot window; it includes counter-reader
instructions on both sides of the body, so it is not compared with 8 and does
not qualify the counter. Probe PASS means only that the diagnostic checks
observed nonzero, monotonic readings.

CoreMark error codes distinguish a short duration (`0x00003001`), an
algorithm CRC mismatch (`0x00003002`), and another upstream validation error
(`0x00003003`). The mailbox preserves the upstream signed `total_errors` bit
pattern in the unsigned `validation_errors` word; a negative upstream value is
therefore represented in two's complement. Dhrystone uses the first mismatch
code in the `0x00004001` range, smoke and counter checks use `0x000010xx` and
`0x00002001`, and traps use `0x0000f001`.

The existing RTL concerns remain open: an instruction in WB can be counted
more than once when a younger memory operation stalls, and MDU completion
validity around injected results is not established. The applicable evidence
and analysis are recorded in
[`BENCHMARK_FEASIBILITY_2026-11-04.md`](../../Verification/plans/BENCHMARK_FEASIBILITY_2026-11-04.md).
`minstret`-based instructions/iteration, CPI, and IPC are therefore
unqualified even when a firmware validation passes.

## Benchmark ports

### Smoke

The smoke workload writes and rereads a volatile DSRAM array, checks a fixed
integer accumulation, and checks runtime RV32M multiply, divide, and remainder
results. It also requires nonzero, monotonic counter snapshots. A failure
records its validation count and a stable error code; arithmetic failures are
not converted into expected values.

### Counter probe

The counter probe records absolute counter snapshots around the documented
eight-instruction assembly body. It checks only nonzero and monotonic counter
observations. The observed `minstret` count includes the sampling overhead and
is deliberately not treated as a qualification result.

### CoreMark

CoreMark uses its unchanged computational C files, a 2000-byte static data
block, one context, volatile validation seeds `0x3415, 0x3415, 0x66`,
`HAS_FLOAT=0`, and all three official algorithms. A build-local copy of
upstream `core_main.c` adds a result hook after upstream validation so the
mailbox captures the actual upstream `total_errors` and list/matrix/state/final
CRCs. A zero `main()` return is not used as evidence of CRC success. Nonzero
upstream errors produce FAIL. The official 10-second duration error remains in
`total_errors`; a short functional run may therefore fail even when CRCs match,
and is never reported as a compliant published score.

The reporting hook also receives upstream's CRC-only `results[0].err` after
`known_id` selects the correct seed/data-size table. It does not duplicate CRC
constants. Unknown seed configurations fail closed. A duration-only error is
`0x3001`; an upstream CRC error is `0x3002`; other/unknown or combined non-CRC
errors are `0x3003`. This fixes the former 6K-table comparison in a 2K build.

### Dhrystone

The pinned source is the RISC-V tests port of Dhrystone C Version 2.2. The
upstream computation file `dhrystone.c` is compiled byte-for-byte unchanged,
separately from the build-local instrumented main, with inlining and GCC
identical-code folding disabled. `strcpy` and `strcmp` remain real runtime
calls. The local header binds the measurement hooks to the 64-bit mailbox
snapshots, uses the configured clock frequency, and disables the old
time-threshold retry so the requested run count stays exact. The local main
omits upstream target-side score calculations/output. After the measured loop,
port code checks the 50-element array and all 2500 entries of the second array, final scalars and local strings,
and both records including pointer relationships and record strings. Each
mismatch increments `validation_errors` and retains the first stable error
code.

## Qualification limits

The result block is firmware evidence, not a substitute for SoC verification.
PASS requires zero independent validation errors, no recorded trap, and a
passing testbench. The build layer alone does not verify the MDU, the actual SRAM
paths, trap handling, or benchmark execution. Integrated runs and their preserved
outcomes are recorded in DELIVERABLES.md. Small CoreMark and Dhrystone
runs are for engineering validation only; host-derived performance metrics
must retain the selected compiler flags, configured frequency, memory timing,
and the counter qualification status.
