# SoC UVM Testbench

DUT: `riscforge_soc_subsystem` (`../rtl`) with the real RV32IM core, boot ROM, AXI-Lite xbar,
APB I2C / Timer0 / Timer1 / UART / GPIO / SPI and the bootloader.

## Layout

| Dir | Content |
| --- | --- |
| `if/` | ctrl, uart, gpio, spi, i2c, irq, trace interfaces |
| `agents/` | UART (driver + monitor), GPIO (driver + monitor), SPI slave (on `csn1`), I2C slave (addr `0x50`) |
| `env/` | config, irq monitor, trace monitor, scoreboard, coverage, env |
| `seq/` | UART send, GPIO set |
| `tests/` | base test + one test per block |
| `tb/` | package, assertions (6 APB slaves, core, bus timeouts), `tb_top` |
| `sw/` | asm firmware per block, linker script, hex build |
| `soc_ip.f` | full SoC filelist (IP paths of this branch) |

## Flow

1. Default (warm boot): test holds `hard_rst_ni` and `soft_rst_ni` low, releases hard reset, then soft
   reset. The bootloader sees a warm boot (no flash fetch, no SRAM clear) and releases the core.
   `tb_top` loads `+HEX=` into ISRAM (`0x0001_0000`) and clears DSRAM at that point.
2. Flash boot (`make flash`): real cold boot. The S25FS512S flash model holds the program, the
   bootloader clears SRAM, copies the image over SPI into ISRAM and releases the core.
3. Boot ROM (`0x0`) sets `sp` and jumps to `0x0001_0000`.
4. Firmware drives the block under test. Agents respond and monitor the pins.
   Firmware writes `n` to `0x0002_0004` to tell the test it reached phase `n` (used for stimulus).
5. Firmware writes `1` to `0x0002_0000` for pass, `(code<<1)|1` for fail.
6. Scoreboard checks the pass code and each block's traffic. Assertions check APB handshakes,
   PC X, LSU errors and the bus timeout flags.

## Tests

| Test | Firmware | Checks |
| --- | --- | --- |
| `soc_hello_test` | `hello` | UART TX `hello\n` (FIFO mode) |
| `soc_hello_test` | `uart_nofifo` | same, UART in 16450 (no FIFO) mode |
| `soc_uart_echo_test` | `uart_echo` | UART RX -> TX echoes `ping` |
| `soc_gpio_test` | `gpio` | GPIO out `0xA5A5`, input `0x5A5A` |
| `soc_timer_test` | `timer` | timer0 + timer1 count, compare irqs on pins |
| `soc_spi_test` | `spi` | MOSI `0xDEADBEEF`, MISO `0xCAFEF00D` |
| `soc_i2c_test` | `i2c` | write `0x3C` to `0x50`, read `0x96`, I2C irq |
| `soc_core_test` | `isa` | all RV32I ALU / shift / compare / branch / jal / jalr / lui / auipc / CSR ops |
| `soc_core_test` | `mext` | mul/mulh/div/rem incl. divide by zero and overflow |
| `soc_core_test` | `mem` | word/half/byte load-store, sign/zero extend |
| `soc_core_test` | `mem_march` | full 32 KB DSRAM: address, inverse address, walking ones |
| `soc_core_test` | `trap` | ecall, illegal, ebreak -> mcause, mepc, mret |
| `soc_core_test` | `lsu_hazard` | load right after an MMIO store, load-load-use with offset bits equal to the second load's rd, `jal`/`jalr`/branch right after a stalled load or store |
| `soc_fault_test` | `mem_fault` | misaligned load/store (4/6), access faults (5/7) on ISRAM, unmapped, bad APB slot, mtval |
| `soc_irq_test` | `irq` | CPU interrupts: timer0 (MTIP), timer1 (fast 24), GPIO rise (fast 16), UART RX (fast 19) |
| `soc_warm_reset_test` | `warm_reset` | soft reset mid-run, DSRAM retained, core reboots |
| `soc_flash_boot_test` | `hello` | cold boot from SPI flash through the bootloader |
| `soc_timer_full_test` | `timer_full` | register read-back, prescaler, overflow wrap, channel 1 compare irq |
| `soc_uart_full_test` | `uart_full` | IER/MCR/LCR read-back, 8-byte TX burst, 8-byte RX FIFO |
| `soc_i2c_full_test` | `i2c_full` | 3-byte write, 3-byte read with NACK, unused address NACK, IF/IACK |
| `soc_spi_full_test` | `spi_full` | cmd+addr+data frame, read with dummy cycles, 8-bit write, clkdiv change |
| `soc_core_test` | `csr` | all implemented CSRs, mcycle/minstret, mret MPIE->MIE |
| `soc_uart_modes_test` | `uart_modes` | 8N1, 7E1, 6O2, 5N1, 8 forced-1 parity at divisor 3, 8 forced-0 parity 2 stop; TX checked on the pin (parity, stop bits), RX checked in firmware |
| `soc_uart_err_test` | `uart_err` | THRE irq, parity error + RLS irq, framing error, break, overrun, FIFO trigger irq, char timeout irq, loopback + MSR irq, non-FIFO RX |
| `soc_spi_more_test` | `spi_more` | all register read-back, FIFO level in STATUS, soft reset, clkdiv 0 write, INTCFG/INTSTA + both SPI events, quad write/read |
| `soc_gpio_full_test` | `gpio_full` | INFO, all 4 pin modes on the pins, SET/CLEAR/TOGGLE, 32-bit input, rise/fall/level-high/level-low interrupts + clear |
| `soc_i2c_more_test` | `i2c_more` | register read-back, slave clock stretching, repeated start, bus free after stop |
| `soc_core_test` | `rand1`..`rand4` | 400 random RV32IM instructions each (ALU, M, loads/stores, branches, hazards), self-checked against `tools/gen_rand.py` reference model |
| `soc_irq_all_test` | `irq_all` | every CPU interrupt: software (MSIP), timer0/1 overflow + compare on both channels, SPI events, SPI end of transfer, I2C |
| `soc_uart_more_test` | `uart_more` | DLAB-mode register access, 1.5 stop bits, FIFO trigger 8 and 14, several errored chars in FIFO, resync after framing error, non-FIFO overrun |
| `soc_spi_more2_test` | `spi_more2` | addr-only write, dummy-only read, counter-mode interrupt, RX FIFO full stall, addr+dummy read, TX underrun mid-transfer |
| `soc_i2c_more2_test` | `i2c_more2` | CMD ignored when core disabled, START+READ, injected arbitration loss, bus recovery |
| `soc_bus_fault_test` | `bus_fault` | each of the 6 APB slaves hung (PREADY stuck) and an AXI hang: core gets access fault with correct mtval, every slot works again after release |
| `soc_core_test` | `fetch_fault` | jump to unmapped addresses: instruction access fault, mcause 1, mtval/mepc = target |
| `soc_hard_reset_test` | `warm_reset` | second hard reset mid-run, program reloaded, DSRAM retained, core reboots |
| `soc_core_test` | `illegal` | 17 invalid encodings (bad funct3/funct7/shift, `sret`/`uret`, bad SYSTEM/FENCE) trap with mcause 2 and mtval = instruction; `wfi`, `fence.i`, M ops do not trap; `mepc[1:0]` reads 0 |
| `soc_core_test` | `regs` | every software register of GPIO, UART, SPI, I2C, Timer0/1 (both channels): reset value, all-ones / all-zeros / `0xA5A5A5A5` / `0x5A5A5A5A` write and read-back, read-only and reserved bits |
| `soc_flash_boot_test` | `flash_data` | cold boot from SPI flash with code and a data section copied into DSRAM over AXI |

## Run (from this folder)

```bash
make compile
make run TEST=soc_irq_test PROG=irq
make flash PROG=hello
make regress
make regress COV=1 && make cov_report
make run TEST=soc_spi_test PROG=spi GUI=1
```

Results: `logs/<test>_<prog>.log`, `logs/summary.txt`, `rtl_trace.log`.

Plusargs: `+HEX=`, `+TIMEOUT=`, `+UART_BIT_CLKS=`, `+UART_EXPECT=`.

## RTL bugs found by this bench (fixed on this branch)

| Test | Bug | Fix |
| --- | --- | --- |
| `mext` | `mul`/`div` result reached WB in a bubble slot (`valid_W=0`, `PC_W=0`), so `RegWriteW_gated` dropped it | `riscv_core/rtl/execute_cycle.v`: keep the M instruction PC at start, mark the result slot valid |
| `lsu_hazard`, `i2c` | Load waiting in EX behind a stalled MMIO store was flushed by `lwstall` (flush beats stall in ID/EX) | `riscv_core/rtl/hazard_unit.v`: gate `lwstall` and `csr_stall` in `FlushE` with `~mem_stall_i` |
| `rand4` | M instruction starting while a load/store waits in MEM raised `FlushM` and erased the stalled load; an M result finishing during an LSU stall had nowhere to go | `hazard_unit.v`: `FlushM` uses `stallMUL & ~mem_stall_i`; `execute_cycle.v`: hold the M result until EX/MEM is free |
| `uart_nofifo` | With FIFO off, THR write did not clear LSR.THRE, characters overwritten | `SOC_FILES_CENTOS/obi/obi_uart_tx.sv`: keep THRE low in the cycle THR is written |
| `uart_modes` | Stop bits inverted: LCR[2]=0 sent 2 stop bits, LCR[2]=1 sent 1 | `obi_uart_tx.sv`: invert the `stop_bits` test in TXSTOP1 |
| `uart_err` | Line status and modem status interrupts lasted one cycle, IIR never showed them | `obi_uart_interrupts.sv`: hold `rls` until LSR read, `mstat` until MSR read |
| `uart_err` | Reading LSR never cleared OE/PE/FE/BI (`*_valid` was 0 on the clear) | `obi_uart_rx.sv`: set the `*_valid` strobes on the LSR-read clear |
| `uart_err` | Non-FIFO RX set the break indicator on every character (`break_ind = 1'b1` overrode the real value) | `obi_uart_rx.sv`: remove the override |
| `irq_all` | One-cycle interrupt pulses (timer, SPI events) were lost if they landed on a pipeline bubble, because `mip` is not latched | `riscv_core/rtl/top.v`: capture rising edges of enabled interrupt lines, hold until taken or disabled |
| `uart_more` | With DLAB=1 every read except DLL/DLM returned a bus error (load access fault) | `obi_uart_register.sv`: offsets 2-7 readable with DLAB=1 |
| `lsu_hazard` | `RS2_D` was taken from `InstrD[24:20]` for every instruction, so loads and other I-type instructions raised false load-use stalls when `imm[4:0]` matched the previous load's rd | `riscv_core/rtl/decode_cycle.v`: `RS2_D` only for R-type, store and branch |
| `lsu_hazard` | `jal`/`jalr` right after a stalled load or MMIO access redirected the PC and was then flushed from EX, so `ra` was never written and `ret` jumped to 0 | `riscv_core/rtl/execute_cycle.v`: gate `PCSrcE` with `~StallM` |
| `illegal` | Only the opcode was checked: invalid funct3/funct7/shift encodings, `sret`/`uret` and bad SYSTEM forms ran instead of trapping | `riscv_core/rtl/Control_Unit_Top.v`: full field check ORed into `illegal_instr` |
| `illegal` | `mepc` kept bits [1:0] on a CSR write | `riscv_core/rtl/csr_regfile.v`: write `mepc` with bits [1:0] = 0 |
| `regs` | UART IIR always reported FIFOs enabled (`0xC1`), even with FIFOs off | `obi_uart_interrupts.sv`: IIR[7:6] follow FCR.fifo_en |
| `regs` | UART IER[7:4] and MCR[7:5] are unused but kept written values | `obi_uart_register.sv`: mask IER to `0x0F`, MCR to `0x1F` on write |
| `fetch_fault` | A jump to an unmapped address did not trap; the core fetched garbage and ran away | `fetch_cycle.v`/`top.v`: fetch regions as parameters, instruction access fault (mcause 1) outside them; SoC sets boot ROM + ISRAM |

## Notes and limits

- UART scratch register (`0x1C`) is not implemented in `obi_uart` (reads 0).
- Writing a non-existent CSR (e.g. `0x7C0`) does not raise an illegal-instruction exception (RISC-V spec says it should); the write is ignored.
- The SPI interrupt state machine only arms after a read of INTSTA.
- SPI reads need `CLKDIV >= 2` (documented in `spi_master_clkgen.sv`); at 0 the read gets an extra clock and wrong data. Tests read at 2.
- Not reachable in this SoC: SPI quad data on `sdi0/2/3` and `sdo1-3` (tied off / not pinned out), UART modem pins (tied off, covered through loopback), I2C arbitration loss (single master).
- New random programs: `python3 tools/gen_rand.py <seed> <count> > sw/randN.S`, add `soc_core_test:randN` to `REGRESS`.
