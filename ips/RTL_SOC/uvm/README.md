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
| `soc_core_test` | `lsu_hazard` | load right after an MMIO store |
| `soc_fault_test` | `mem_fault` | misaligned load/store (4/6), access faults (5/7) on ISRAM, unmapped, bad APB slot, mtval |
| `soc_irq_test` | `irq` | CPU interrupts: timer0 (MTIP), timer1 (fast 24), GPIO rise (fast 16), UART RX (fast 19) |
| `soc_warm_reset_test` | `warm_reset` | soft reset mid-run, DSRAM retained, core reboots |
| `soc_flash_boot_test` | `hello` | cold boot from SPI flash through the bootloader |

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

## Known RTL bugs found by this bench

| Test | Bug |
| --- | --- |
| `mext` | `mul`/`div` result reaches WB with `valid_W=0`, so `RegWriteW_gated` (`top.v`) drops it. M results never reach the register file. |
| `lsu_hazard`, `i2c` | A load right after a stalled MMIO store is dropped (no bus access, no commit). Polling loops exit early. |
| `uart_nofifo` | `obi_uart_tx.sv`: with FIFO off, a THR write does not clear LSR.THRE (the later `~thr_full_q` block overrides it), so characters are overwritten. |
| `irq` (note) | GPIO global interrupt defaults to a 1-cycle pulse and the core does not latch `mip` (`csr_regfile.v`), so a pulse can be missed while the core stalls. Firmware sets GPIO `CFG=1` (level mode). |
