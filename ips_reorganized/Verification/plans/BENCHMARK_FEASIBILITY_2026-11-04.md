# Dhrystone / CoreMark feasibility on the current SoC

Reviewed 2026-11-04. Scope: current local sources, BSP/build setup, WSL toolchain inspection, and upstream benchmark requirements. No RTL changes, benchmark port, benchmark compilation, or simulation was performed. A compiler header preprocessing probe was performed and failed on missing `stdio.h`. No benchmark score or exact linked memory footprint is established.

## Assessment

Both benchmarks are plausible bare-metal workloads for the RV32IM core. The SoC has 32 KiB ISRAM at 0x00010000 and 32 KiB DSRAM at 0x00020000, with stack top 0x00028000. CoreMark is the preferred first port because its standard data block is 2000 bytes and it supplies CRC validation. Dhrystone is also plausible: its 50x50 and 50-element integer arrays alone require 10,200 bytes on RV32, before other data and stack. Exact code/data fit requires linking each actual port and measuring stack use.

The current setup is incomplete. Performance measurement with `mcycle` is plausible; `minstret` is not yet trustworthy as a count of unique retired instructions. Qualify both counters and arithmetic before publishing performance results.

## Counter implementation and measurement concerns

- `riscv_core/rtl/csr_regfile.v:108-111,127-130` implements machine CSRs `mcycle` (0xB00), `mcycleh` (0xB80), `minstret` (0xB02), and `minstreth` (0xB82), backed by 64-bit registers.
- `mcycle` increments every core clock outside reset. `minstret` increments whenever `instr_retired_i` is high (`csr_regfile.v:153-154`).
- `top.v:572` connects that input to `valid_W & ~exc_valid_W`. Meanwhile, `memory_cycle.v:260-264` holds all MEM/WB state, including `valid_W`, during `core_stall_gated`. Therefore, if a normal valid instruction is in WB while a younger memory operation stalls, the same WB instruction can contribute multiple increments. This is a static RTL finding; no new waveform reproduction was performed. A monitor using the same validity expression is not an independent reference.
- The user counter aliases at 0xC00/0xC80 and 0xC02/0xC82 are absent from the read mux. The default read value is zero. Explicit machine CSR reads are required; ordinary `rdcycle` / `rdinstret` instructions address the missing aliases.
- Existing stage-2 evidence demonstrates a live `mcycle` read, not exact cycle accounting or unique retirement counting. The SoC testbench's `minstret != 0` guard establishes activity only.
- Use RV32 high-low-high retry reads for each 64-bit counter. Keep snapshots as deltas rather than writing counters to zero. Use compiler barriers around the timed region, preserve calls/data dependencies, inspect generated assembly, and measure empty-wrapper overhead. A `memory` clobber alone does not prevent all pure register computation from moving across a timing boundary.
- Cycle and instruction snapshots occur at different instants; define the read order and account for measurement instructions. Counter CSR data is sampled in EX, while retirement is counted in WB, so a short interval needs careful boundary accounting.

## Arithmetic prerequisite

Recheck the existing MDU integration concern before an RV32IM benchmark. `execute_cycle.v:293,329-331` selects a completed M result and destination, but `valid_M_r <= valid_E` at line 424 does not explicitly mark an injected completion valid. MDU stalls flush E/M in `hazard_unit.v:192,199`; a result arriving while EX holds a bubble may consequently lose its valid tag. Memory stall overlap and multiply abort are additional documented uncertainties in `documentation/signoff/Core_Microarchitecture.md:452` onward. These are static concerns, not newly measured benchmark failures.

A separately labeled RV32I build using matching software arithmetic helpers can help isolate MDU behavior, but it is a different benchmark configuration. It cannot establish correctness or performance of the RV32IM configuration.

## Environment checked

- Windows PATH did not expose a RISC-V compiler. WSL exposes `/usr/bin/riscv64-unknown-elf-gcc`, GCC 13.2.0, with RV32IM/ILP32 multilib support.
- For `-march=rv32im_zicsr -mabi=ilp32`, libgcc resolves to `/usr/lib/gcc/riscv64-unknown-elf/13.2.0/rv32im/ilp32/libgcc.a`.
- `-print-file-name=libc.a` returns the unresolved name `libc.a`; a preprocessing probe fails with `fatal error: stdio.h: No such file or directory`. A complete C library was not established. GCC's `stdint.h` passed before that failure.
- WSL also exposes Icarus Verilog and Verilator. Their presence does not establish that the complete SoC environment builds with either, or fulfill the checklist's VCS requirement.
- No CoreMark/Dhrystone source or build target was found in the inspected `ips/Sw` and `verification` inventories. `ips/Sw/Makefile` currently builds UART, timer IRQ, and datapath programs.
- Git baseline/dirty identity was not established: Windows PATH lacked Git, and the WSL Git attempt reported no repository. Source hashes below pin the principal reviewed RTL files.

## Proposed setup

1. Pin upstream benchmark source revisions. Keep CoreMark computational sources unchanged; put platform changes in `core_portme.*` and external runtime support. Pin the Dhrystone variant/version as well.
2. Use `-march=rv32im_zicsr -mabi=ilp32 -O2 -ffreestanding`, with explicit startup, linker script, runtime and `-lgcc` as required. Do not enable C/F/D/A extensions. Start without LTO. Dhrystone's compilation rules require separate compilation and no procedure merging; retain and disclose the selected string-library/builtin policy.
3. Keep `.text` in ISRAM and `.rodata/.data/.bss`, benchmark buffers and stack in DSRAM. Constants must be accessible on the data port. Reserve the mailbox if using the verification testbench. Produce a linker map, section sizes, disassembly, and a stack high-water measurement; enforce a stack margin at link time.
4. Reuse reviewed startup responsibilities: disable interrupts, initialize gp/sp, clear BSS and install a trap handler that reports failure. The existing BSP variants are not interchangeable: `Verification/tests/bsp/link.ld` reserves the first 64 DSRAM bytes for the mailbox, whereas `Verification/firmware/bsp/link.ld` and `Sw/bsp/link.ld` do not. Also, `Verification/tests/bsp/crt0.s` writes legacy completion values 1/2 on return; the current mailbox header and TB expect 0xC0DEC0DE / 0xBAADF00D. Choose and reconcile these interfaces explicitly during a port.
5. Implement minimal runtime services or provide a suitable RV32 bare-metal libc. CoreMark can use static allocation, volatile seeds, one context, `HAS_FLOAT=0`, no OS timing, and a platform `ee_printf`/output path. Dhrystone needs string functions and reporting; the inspected RISC-V variant also uses alloca and platform `util.h`/statistics hooks. Capture raw 64-bit counters and compute decimal scores on the host to avoid target floating-point formatting.
6. Hook CoreMark `start_time()` / `stop_time()` to explicit machine counter snapshots. Preserve CRC validation and report failure independently of program termination. For Dhrystone, preserve its computation and check final values. The inspected RISC-V Dhrystone header hard-codes `HZ=1000000` despite reading `mcycle`; do not inherit that as the SoC frequency.
7. Use the existing warm preload sequence after reset synchronization, with separate IMEM/DMEM hex generated by `Sw/tools/elf_to_hex.py`. The canonical bench accepts `+BOOT_MODE=WARM +IMEM_HEX=... +DMEM_HEX=... +TIMEOUT=...` and is built from `Verification/infrastructure/rf_filelist.txt` through its generator.
8. The existing SoC bench requires real AXI/APB activity and firmware attestation before accepting PASS. Perform an existing checked peripheral sanity operation outside the measured interval, or propose a distinct benchmark-specific completion contract for review. Do not fabricate activity or weaken existing guards. Also reserve additional result storage outside the mailbox and benchmark buffers for both halves of each counter.
9. Begin with a fixed small iteration count and an explicit watchdog for correctness. The existing bench defaults to one million cycles. Leave UART/mailbox output, boot, initialization, peripheral sanity, validation and final score calculation outside the benchmark's timed region.

## Qualification and result interpretation

Before trusting a score, distinguish these checks:

- **Cycle counter:** compare cycle deltas against independently counted core clock edges at the actual CSR sampling boundary; cover stalls and low-half rollover.
- **Retirement counter:** compare against a known instruction stream with unique dynamic retirement events; cover SRAM/MMIO waits, branches, bubbles, MDU operations and synchronous traps. A repeated-PC loop is legal, so PC equality alone cannot identify duplicate retirement.
- **Core correctness:** require MDU result retirement, load/store and CSR dependencies, call/return behavior, and benchmark CRC/final-state checks to pass on the selected source snapshot.
- **Port fit:** actually link each ELF, verify supported instructions and memory regions, convert to SRAM images, then run on the full SoC memory path. Compilation alone proves neither execution nor benchmark validation.

For N measured iterations, C elapsed core cycles and I uniquely retired instructions:

- cycles/iteration = C/N; instructions/iteration = I/N.
- CPI = C/I; IPC = I/C. These remain unqualified until retirement accounting is resolved.
- CoreMark/MHz = N * 1,000,000 / C.
- Dhrystones/second = N * core_frequency_hz / C; conventional DMIPS = Dhrystones/second / 1757.

The current canonical bench models a 100 MHz clock (10 ns period). This is a simulation setting, not achieved silicon Fmax. Report the actual memory timing/configuration with the compiler version and flags. Host simulator wall time is not target execution time.

Upstream CoreMark requires at least 10 seconds of target execution and successful standard performance/validation seed runs. At modeled 100 MHz, 10 target seconds means at least one billion measured cycles. A small RTL run can establish correctness and cycles/iteration, but does not satisfy the published-duration rule. Do not change the declared frequency to make a short run qualify. Both 64-bit counters should be used for long campaigns.

## References

- [EEMBC CoreMark rules and reporting](https://github.com/eembc/coremark/blob/main/README.md)
- [EEMBC bare-metal porting guide](https://github.com/eembc/coremark/blob/main/barebones_porting.md)
- [CoreMark barebones port configuration](https://github.com/eembc/coremark/blob/main/barebones/core_portme.h)
- [RISC-V Dhrystone source](https://github.com/riscv-software-src/riscv-tests/tree/master/benchmarks/dhrystone)
- [RISC-V machine counter specification](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html)

## Reviewed RTL SHA-256

```text
csr_regfile.v  4D991CABDE1DA22E93DDC61D77628BDA90168E28A6F7DCD2B56B5D2A22592D1D
top.v          2FC6A4DCFC0FB1C9CAE418CDB8CEF553699F336DCF59C8D75EE12A39871EBBB6
memory_cycle.v D63E8DC31C47772FFA9DD6CA55D63A91BAA2F3BF798D66D4B2AF949114136593
execute_cycle.v A93C807E262628F44F85DEE44E8466498F404214591E04C6B6A9A903C39313F2
```
