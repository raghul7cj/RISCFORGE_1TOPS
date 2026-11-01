# APB I2C Master IP - Firmware & Driver Documentation

## 1. Upstream GitHub Provenance
* **Origin**: ETH Zurich & University of Bologna (PULP Platform) / OpenCores (Richard Herveille)
* **Repository**: [pulp-platform/apb_i2c](https://github.com/pulp-platform/apb_i2c) (branch `master`)
* **Firmware Origin**: [pulp-platform/pulpino](https://github.com/pulp-platform/pulpino) (`sw/libs/sys_lib/inc/i2c.h`, `sw/libs/sys_lib/src/i2c.c`)

## 2. RTL Match & Verification Status
* `i2c_master_bit_ctrl.sv`: **100% Identical** to upstream.
* `i2c_master_byte_ctrl.sv`: **100% Identical** to upstream.
* `i2c_master_defines.sv`: **100% Identical** to upstream.
* `apb_i2c.sv`: Identical RTL logic (includes verification comments).

## 3. SoC Memory Map & Registers
* **Base Address**: `0x40000000` (APB[0])
| Offset | Name | Description |
|---|---|---|
| `0x00` | `I2C_PRE_LO` | Prescaler divider Low byte |
| `0x04` | `I2C_PRE_HI` | Prescaler divider High byte |
| `0x08` | `I2C_CTR` | Control: `[7]`=EN, `[6]`=IEN |
| `0x0C` | `I2C_TXR`/`RXR`| Transmit Data (W) / Receive Data (R) |
| `0x10` | `I2C_CR`/`SR` | Command (W) / Status (R) |

## 4. Interrupt Routing
* I2C Interrupt (`interrupt_o`) -> Core `fast_irq_i[1]` (Cause 17, `mip[17]`)
