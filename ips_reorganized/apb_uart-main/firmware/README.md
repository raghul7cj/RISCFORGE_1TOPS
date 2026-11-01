# APB UART IP - Firmware & Driver Documentation

## 1. Upstream GitHub Provenance
* **Origin**: ETH Zurich & University of Bologna (PULP Platform)
* **Repository**: [pulp-platform/apb_uart](https://github.com/pulp-platform/apb_uart) (branch `main`)
* **Firmware Origin**: [pulp-platform/pulpino](https://github.com/pulp-platform/pulpino) (`sw/libs/sys_lib/inc/uart.h`, `sw/libs/sys_lib/src/uart.c`)

## 2. RTL Match & Verification Status
* `apb_uart.sv`: **100% Identical** to upstream `pulp-platform/apb_uart/src/apb_uart.sv`.
* `apb_uart_wrap.sv`: Identical (with minor trailing comma parameter syntax adjustment).
* 16550-compatible register interface.

## 3. SoC Memory Map & Registers
* **Base Address**: `0x40002000` (APB[2])
| Offset | Name | Read/Write | Function |
|---|---|---|---|
| `0x00` | `RBR` / `THR` | R / W | RX Buffer / TX Holding (DLAB=0) |
| `0x00` | `DLL` | R/W | Baud Divisor LSB (DLAB=1) |
| `0x04` | `IER` | R/W | Interrupt Enable (DLAB=0) |
| `0x04` | `DLM` | R/W | Baud Divisor MSB (DLAB=1) |
| `0x08` | `IIR` / `FCR` | R / W | Interrupt ID / FIFO Control |
| `0x0C` | `LCR` | R/W | Line Control Register (DLAB bit 7) |
| `0x14` | `LSR` | R | Line Status Register (`THRE`=bit 5, `DR`=bit 0) |

## 4. Interrupt Routing
* UART Interrupt (`INT`) -> Core `fast_irq_i[3]` (Cause 19, `mip[19]`)
