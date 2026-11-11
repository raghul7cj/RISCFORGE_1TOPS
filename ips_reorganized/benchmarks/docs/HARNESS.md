# RISCFORGE full SoC benchmark harness

This directory contains a reproducible simulation harness for benchmark firmware that has already been built elsewhere. It instantiates the actual `riscforge_soc_subsystem` from `ips/RTL_SOC/soc_subsystem.f`; it contains no substitute for the CPU, SRAM, boot ROM, bus, or peripherals. The dedicated manifest adds the real OBI UART package/wrapper dependencies because the current design-only list omits them even though `apb_uart.sv` instantiates `apb_uart_wrap`. It does not edit the original design list.

## Inputs and output layout

The firmware directory passed to the runner contains:

| File | Use |
| --- | --- |
| `program.elf` | RV32 little-endian RISC-V identity and load-segment bounds check |
| `imem.hex` | 32 KiB instruction SRAM preload |
| `dmem.hex` | 32 KiB data SRAM preload |
| `build.json` | Benchmark name, numeric ID, iteration count, and ISA metadata |

For a normal run, the runner stages firmware and the boot ROM into a new run directory, then validates those staged inputs. It checks the benchmark, ID, positive iteration count, ELF32 little-endian RISC-V identity, entry address, ABI flags and load-segment SRAM bounds. It checks sparse hex addresses, rejects duplicate/out-of-range words, compares the actual preload bytes with the ELF, and rejects a prepopulated result block or extra payload outside the ELF. It records hashes for the actual staged inputs and every listed HDL source/file list/include. The DUT uses the staged boot ROM through a generated absolute-path `defparam`.

Normal runs also require `build_status=complete`, well-formed source/output SHA-256 records, matching source pins, matching declared benchmark source files in the current checkout, and matching staged ELF/image/ported-source hashes. A failed or interrupted rebuild cannot authorize stale images through the runner. The raw result must explicitly report no trap; missing or null trap evidence fails analysis.

The runner requires the selected benchmark's known port and upstream source inventory, not merely nonempty or well-formed hash dictionaries. It also requires the build-local entry-point/header hashes to identify their exact staged files. Omitting those source groups fails preflight even when the ELF and SRAM images still match each other.

Every run gets a fresh UTC/UUID directory under `ips/benchmarks/build/runs/` (or `--output-dir`). The PowerShell wrapper selects `ips/benchmarks/runs/`. A run retains generated per-simulator file lists and their hashes, source hashes, copied ELF/map/disassembly/build metadata/SRAM images, tool logs, `run_metadata.json`, raw `result.json`, and host-derived `analysis.json`. Failure logs and partial result evidence stay in that directory. No previous result file is reused.

## Generate and inspect the simulator file lists

The human-readable manifest is `filelists/soc_benchmark.f`. Paths inside these lists follow the existing SoC convention and are relative to `ips/`, including its `-f RTL_SOC/soc_subsystem.f` reference. The generator expands that design-only list, validates all listed source/include paths and HDL `` `include`` files, removes the original top/timescale/language switches, and emits:

- `soc_benchmark_xsim.f`, with Vivado's `-i <directory>` include syntax and the source tree's `XSIM` compatibility define (which selects its existing assertion guards for unsupported XSim syntax);
- `soc_benchmark_vcs_xcelium.f`, with `+incdir+<directory>` syntax.

Run it from the repository root:

```powershell
python ips/benchmarks/tools/generate_filelists.py
```

The generated list paths are relative to their containing output directory, so compilation and simulation can run in the unique build directory even when the repository path contains spaces. `source_hashes.json` is the source snapshot record for that generation.

The runner rehashes the recorded HDL/include/file-list/generated configuration inputs after XSim/VCS compilation and elaboration, or after Xcelium's single combined invocation. A changed fingerprint fails the run. The design paths still refer to the live checkout, so this is a before/after consistency check rather than an immutable copy of the entire RTL tree.

## Run a firmware benchmark

Example with Vivado 2022.2 XSim:

```powershell
python ips/benchmarks/tools/run_benchmark.py `
  --benchmark coremark `
  --firmware-dir C:/path/to/coremark/build `
  --simulator xsim `
  --timeout-cycles 1000000 `
  --output-dir ips/benchmarks/build/runs `
  --tool-bin C:/Xilinx/Vivado/2022.2/bin
```

Available benchmark names and contract IDs are `smoke=1`, `counter_probe=2`, `coremark=3`, and `dhrystone=4`. `--simulator` accepts `xsim`, `vcs`, or `xcelium`; `--tool-bin` can identify a tool directory or executable. `--wall-timeout-seconds` bounds the host process separately from the cycle watchdog. `--waves` requests a VCD dump. `--compile-only` compiles/elaborates without executing target code; its metadata explicitly says no performance was measured. A compile-only fixture is not benchmark firmware.

Simulators receive run-local `IMEM_HEX=imem.hex` and `DMEM_HEX=dmem.hex` names and load the staged copies. For XSim, the runner writes quoted `-testplusarg` operands to `xsim_options.txt` and invokes `xsim -f xsim_options.txt`. This avoids the Windows batch launcher's splitting of `NAME=value` arguments and paths containing spaces. VCS/Xcelium receive conventional plusargs directly.

VCS and Xcelium file-list dialects and invocation templates are generated by the runner, but this checkout's local verification is performed with XSim. A runner result records actual tool paths, version-probe output, exact argument vectors, working directory, and exit codes; it does not claim a simulator was used unless its command ran.

## Reset, preload, and observations

The testbench uses a 10 ns clock (modeled 100 MHz), keeps hard and soft reset asserted together, releases hard reset while soft reset remains low, then waits with bounds for `dut.hard_rst_sync_n` and `dut.i_bootloader.warm_boot_q`. During the selected warm boot it clears both SRAM arrays, reads the supplied images into `dut.i_isram.u_imem.mem_array` and `dut.i_dsram.mem`, and releases soft reset. It waits for both `dut.core_rst_n` and `boot_done_o` before starting the firmware watchdog. XSim requires the RTL's existing `XSIM` preprocessor branch because it does not support the default-disable-iff assertion declaration used by the SoC source; the benchmark harness's timeout, trap, status, and validation guards remain active.

Idle external inputs are connected: I2C SCL/SDA high, UART RX high, SPI MISO low, and GPIO inputs low. The harness observes the complete DUT outputs, APB/AXI sticky timeout outputs, `dut.i_riscv_core.trap_commit_valid`, the 64-word result block at `dut.i_dsram.mem[0..63]`, and the console sequence/character word. It also records the number of cycles in which `valid_W && !exc_valid_W && mem_stall_out` is true and the raw `valid_W && !exc_valid_W` sample count. These are diagnostics only; the latter is not an independent instruction-retirement count.

The testbench requires an empty initial result block and observes a matching RUNNING state before accepting terminal status. It fails on bad magic/version/status, benchmark-ID mismatch, terminal validation errors, zero timing delta, a sampled trap commit, a sticky bus timeout, missing terminal status, or watchdog expiration. It lets firmware publish complete validation-failure details before collecting its terminal result. A host wall timeout kills the simulator process tree, records the timeout, and returns nonzero. A process exit alone never means PASS: the runner also requires a `BENCH_TB_PASS` marker and a valid raw JSON capture. XSim was observed to return zero even after a TB `$fatal`; the host still rejected the result.

## Result contract and interpretation

`contract.json` is the fixed ABI source. DSRAM words 0–63 (the reserved first 256 bytes at `0x00020000`) are captured as hexadecimal strings in raw JSON. The firmware's terminal PASS status is only accepted after the independent firmware validation fields are checked and no testbench guard has fired. A FAIL, timeout, trap, or compile/simulator error is retained as a failure with its reason.

The analyzer uses unsigned modulo-64-bit subtraction for the raw `mcycle` and `minstret` deltas, rejects a cycle delta larger than the observed post-boot run, then reports cycles per iteration, the raw instruction delta, and raw CPI. It also requires observed RUNNING, checks the error/trap words and refuses estimates for failed results. `minstret` and CPI remain explicitly **unqualified** because the current RTL can hold a valid WB instruction during a younger memory stall. No testbench duplicate-retirement expectation is used to turn that counter into a functional PASS gate.

CoreMark/MHz and Dhrystones/second/DMIPS, when calculable, are labeled engineering estimates using the modeled 100 MHz clock. The analyzer always leaves `published_score` null and `published_compliance` false; the current short RTL campaign does not establish the full published-duration, validation-seed, source/configuration, or platform evidence required for a compliant score. There is no option to relabel an estimate as compliant.

The firmware clock word must match the TB's 100 MHz clock. A different declared frequency fails analysis; it cannot change the target time or produce a rate estimate using an incorrect clock.

## Exercise the actual TB failure guards

After a normal XSim run has compiled the snapshot, run:

```powershell
py -3 ips/benchmarks/tools/check_tb_failures.py `
  --snapshot-dir ips/benchmarks/runs/<counter-probe-run-id> `
  --output-dir ips/benchmarks/docs/evidence/tb_guards
```

This deliberately bypasses normal ELF preflight to inject three negative fixtures: a full NOP image that never completes, an illegal instruction, and a preloaded terminal mailbox. A guard check passes only when the TB emits the expected FAIL reason. The fixtures, options, raw records and logs have unique names and do not replace the original run's firmware or result. A negative-fixture success is not benchmark validation.

Run the host unit tests with:

```powershell
python -m unittest discover -s ips/benchmarks/tests -v
```
