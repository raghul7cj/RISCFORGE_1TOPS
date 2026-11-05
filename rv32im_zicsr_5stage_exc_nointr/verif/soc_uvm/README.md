# SoC UVM Testbench

DUT: `riscforge_soc_subsystem` (RV32IM core + AXI-Lite xbar + APB peripherals).

## Layout

| Dir | Content |
| --- | --- |
| `if/` | `soc_ctrl_if`, `uart_if`, `trace_if` |
| `agents/` | UART agent (driver on `uart_sin_i`, monitor on `uart_sout_o`) |
| `env/` | config, writeback trace monitor, scoreboard, env |
| `seq/` | UART send sequence |
| `tests/` | `soc_base_test`, `soc_hello_test`, `soc_uart_echo_test` |
| `tb/` | `soc_pkg`, `tb_top` |
| `sw/` | firmware (asm), linker script, hex build |

## How it works

1. Test drives reset through `soc_ctrl_if`.
2. `tb_top` holds the core in reset, waits for `boot_done_o`, loads `+HEX=` into ISRAM, then releases the core.
   Use `+SKIP_BOOT` to bypass the bootloader (forces `core_rst_n` and `periph_rst_n`).
3. Firmware writes `1` to `TOHOST` (`0x0001_0FFC`) for pass, `(code<<1)|1` for fail.
4. Trace monitor watches the LSU for the `TOHOST` store and logs every register write to `rtl_trace.log`.
5. Scoreboard checks the `TOHOST` result and the UART text against `uart_expect`.

## Run

Needs Xcelium (or edit `Makefile` for VCS/Questa) and a RISC-V GCC.

`vendor.f` = your `soc_imem_boot_vendor.f` without the `-top`, testbench, `riscv_core_stub.sv`,
local SRAM/xbar files and the SoC top (those come from `rtl.f`).

```bash
make hello
make echo
make run TEST=soc_hello_test PROG=hello ARGS=+SKIP_BOOT
```

Plusargs: `+HEX=`, `+SKIP_BOOT`, `+TIMEOUT=`, `+UART_BIT_CLKS=`, `+UART_EXPECT=`.

UART baud: firmware sets divisor 1, so 1 bit = 16 clocks (`+UART_BIT_CLKS=16`).

## Next

- [ ] GPIO, SPI slave, I2C slave agents
- [ ] Timer + interrupt tests
- [ ] Compare `rtl_trace.log` with Spike `--log-commits`
- [ ] Functional coverage + AXI/APB assertions
- [ ] riscv-arch-test / riscv-dv programs through the same flow
