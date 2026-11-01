# APB SPI Master IP - Firmware & Driver Documentation

## 1. Upstream GitHub Provenance
* **Origin**: ETH Zurich & University of Bologna (PULP Platform)
* **Repository**: [pulp-platform/apb_spi_master](https://github.com/pulp-platform/apb_spi_master) (branch `master`)
* **Firmware Origin**: [pulp-platform/pulpino](https://github.com/pulp-platform/pulpino) (`sw/libs/sys_lib/inc/spi.h`, `sw/libs/sys_lib/src/spi.c`)

## 2. RTL Match & Verification Status
* All controller, clock generator, RX/TX, and FIFO files match the upstream PULP implementations (resolved from upstream symlinks into local standalone RTL).
* `apb_spi_master.sv` logic matches upstream.

## 3. SoC Memory Map & Registers
* **Base Address**: `0x40004000` (APB[4])
| Offset | Name | Description |
|---|---|---|
| `0x00` | `SPI_STATUS` | Status (`BUSY`=bit 0, `RX_EMPTY`=bit 1, `TX_FULL`=bit 2) |
| `0x04` | `SPI_CLKDIV` | Clock divider counter |
| `0x08` | `SPI_TXDATA` | Transmit FIFO 32-bit register |
| `0x0C` | `SPI_RXDATA` | Receive FIFO 32-bit register |
| `0x10` | `SPI_CTRL` | Control register: Chip selects and transfer mode |

## 4. Interrupt Routing
* SPI Threshold Event (`events_o[0]`) -> Core `fast_irq_i[2]` (Cause 18, `mip[18]`)
* SPI End-of-Transfer Event (`events_o[1]`) -> Core `fast_irq_i[11]` (Cause 27, `mip[27]`)
