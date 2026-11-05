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

1. Test holds `hard_rst_ni` and `soft_rst_ni` low, releases hard reset, then soft reset.
   The bootloader sees a warm boot: no flash fetch, no SRAM clear, then it releases the core.
2. `tb_top` loads `+HEX=` into ISRAM (`0x0001_0000`) when soft reset is released.
3. Boot ROM (`0x0`) sets `sp` and jumps to `0x0001_0000`.
4. Firmware drives the peripheral, agents respond and monitor the pins.
5. Firmware writes `1` to `0x0002_0000` for pass, `(code<<1)|1` for fail.
6. Scoreboard checks the pass code and each block's traffic. Assertions check APB handshakes,
   PC X, LSU errors and the bus timeout flags.

## Tests

| Test | Firmware | Checks |
| --- | --- | --- |
| `soc_hello_test` | `hello` | UART TX prints `hello\n` (FIFO mode) |
| `soc_hello_test` | `uart_nofifo` | same, UART in 16450 (no FIFO) mode |
| `soc_uart_echo_test` | `uart_echo` | UART RX -> TX echoes `ping` |
| `soc_gpio_test` | `gpio` | GPIO out `0xA5A5`, firmware reads input `0x5A5A` |
| `soc_timer_test` | `timer` | timer0 counts, compare irq fires |
| `soc_spi_test` | `spi` | MOSI `0xDEADBEEF`, MISO `0xCAFEF00D` read back |
| `soc_i2c_test` | `i2c` | write `0x3C` to `0x50`, read back `0x96` |
| `soc_core_test` | `mem` | word/half/byte load-store, DSRAM fill |
| `soc_core_test` | `mext` | mul/mulh/div/rem incl. divide by zero and overflow |
| `soc_core_test` | `trap` | ecall, illegal, ebreak -> mcause, mepc, mret |
| `soc_core_test` | `lsu_hazard` | load right after an MMIO store |

## Run (from this folder)

```bash
make compile
make run TEST=soc_hello_test PROG=hello
make regress
make regress COV=1 && make cov_report
make run TEST=soc_spi_test PROG=spi GUI=1
```

Results: `logs/<test>_<prog>.log`, `logs/summary.txt`, `rtl_trace.log`.

Plusargs: `+HEX=`, `+TIMEOUT=`, `+UART_BIT_CLKS=`, `+UART_EXPECT=`, `+ALLOW_LSU_ERR`.

## Known RTL bugs found by this bench

| Test | Bug |
| --- | --- |
| `mext` | `mul`/`div` result reaches WB with `valid_W=0`, so `RegWriteW_gated` (`top.v`) drops it. M results never reach the register file. |
| `lsu_hazard`, `i2c` | A load right after a stalled MMIO store is dropped (no bus access, no commit). Polling loops exit early. |
| `uart_nofifo` | `obi_uart_tx.sv`: with FIFO off, a THR write does not clear LSR.THRE (the later `~thr_full_q` block overrides it), so characters are overwritten. |
