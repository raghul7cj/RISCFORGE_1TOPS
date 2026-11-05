# SoC UVM Testbench

DUT: `riscforge_soc_subsystem` (RV32IM core, AXI-Lite xbar, APB I2C / Timer / UART / GPIO / SPI).

## Layout

| Dir | Content |
| --- | --- |
| `if/` | ctrl, uart, gpio, spi, i2c, irq, trace interfaces |
| `agents/` | UART (driver + monitor), GPIO (driver + monitor), SPI slave, I2C slave |
| `env/` | config, irq monitor, trace monitor, scoreboard, coverage, env |
| `seq/` | UART send, GPIO set |
| `tests/` | base test + one test per block |
| `tb/` | package, assertions (APB + core), `tb_top` |
| `sw/` | asm firmware per block, linker script, hex build |

## Flow

1. Test resets the SoC.
2. `tb_top` loads `+HEX=` into ISRAM and releases the core (`+SKIP_BOOT` bypasses the bootloader, on by default).
3. Firmware drives the peripheral, agents respond and monitor the pins.
4. Firmware writes `1` to `0x0001_0FFC` for pass, `(code<<1)|1` for fail.
5. Scoreboard checks the pass code and each block's expected traffic. Assertions check APB handshakes, PC X and LSU errors.

## Tests

| Test | Firmware | Checks |
| --- | --- | --- |
| `soc_hello_test` | `hello` | UART TX prints `hello\n` |
| `soc_uart_echo_test` | `uart_echo` | UART RX -> TX echoes `ping` |
| `soc_gpio_test` | `gpio` | GPIO out `0xA5A5`, firmware reads input `0x5A5A` |
| `soc_timer_test` | `timer` | timer counts, timer irq fires |
| `soc_spi_test` | `spi` | MOSI `0xDEADBEEF`, MISO `0xCAFEF00D` read back |
| `soc_i2c_test` | `i2c` | write `0x3C` to addr `0x50`, read back `0x96` |
| `soc_core_test` | `mem` | word/half/byte load-store, DSRAM fill |
| `soc_core_test` | `mext` | mul/mulh/div/rem incl. divide by zero and overflow |
| `soc_core_test` | `trap` | ecall, illegal, ebreak -> mcause, mepc, mret |

## Run

`vendor.f` = `soc_imem_boot_vendor.f` without `-top`, the testbench, `riscv_core_stub.sv`,
local SRAM/xbar files and the SoC top (these come from `rtl.f`). Use absolute paths.

```bash
make compile
make run TEST=soc_hello_test PROG=hello
make regress
make regress COV=1 && make cov_report
make run TEST=soc_spi_test PROG=spi GUI=1
```

Results: `logs/<test>_<prog>.log`, `logs/summary.txt`, `rtl_trace.log`.

Plusargs: `+HEX=`, `+SKIP_BOOT`, `+TIMEOUT=`, `+UART_BIT_CLKS=`, `+UART_EXPECT=`, `+ALLOW_LSU_ERR`.

## Check before first run

Peripheral register offsets are in `sw/common.h`. They follow the PULP IP defaults;
check them against your vendor RTL (`gpio_reg_pkg`, `apb_timer`, `apb_spi_master`, `apb_i2c`, `apb_uart`).
