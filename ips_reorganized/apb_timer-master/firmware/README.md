# APB Timer IP - Firmware & Driver Documentation

## 1. Upstream GitHub Provenance
* **Origin**: ETH Zurich & University of Bologna (PULP Platform)
* **Repository**: [pulp-platform/apb_timer](https://github.com/pulp-platform/apb_timer) (branch `master`)
* **Firmware Origin**: [pulp-platform/pulpino](https://github.com/pulp-platform/pulpino) (`sw/libs/sys_lib/inc/timer.h`, `sw/libs/sys_lib/src/timer.c`)

## 2. RTL Match & Verification Status
* `apb_timer.sv`: **100% Identical** to upstream `pulp-platform/apb_timer/src/apb_timer.sv`.
* `timer.sv`: Logic identical to upstream with one intentional bug fix: interrupt generation and auto-clear logic are qualified with `regs_q[`REG_CTRL][`CTRL_EN]` so a disabled timer does not trigger false traps.

## 3. SoC Memory Map & Registers
In `riscforge_soc_subsystem.sv`, two APB timer instances are present:
* **Timer 0**: Base `0x40001000` (Channels 0 and 1)
* **Timer 1**: Base `0x40005000` (Channels 0 and 1)

Each channel occupies 12 bytes:
| Offset | Name | Description |
|---|---|---|
| `+0x00` | `TIMER_VAL` | Current 32-bit counter value |
| `+0x04` | `TIMER_CTRL` | Control: `[0]` = EN, `[3:1]` = Prescaler divider |
| `+0x08` | `TIMER_CMP` | Compare value for match interrupt |

## 4. Interrupt Routing
* Timer 0 Ch0 Compare -> Core `timer_irq_i` (Cause 7, `mip[7]`, MTIP)
* Timer 0 Ch0 Overflow -> Core `fast_irq_i[4]` (Cause 20, `mip[20]`)
* Timer 0 Ch1 Overflow -> Core `fast_irq_i[5]` (Cause 21, `mip[21]`)
* Timer 0 Ch1 Compare -> Core `fast_irq_i[6]` (Cause 22, `mip[22]`)
* Timer 1 Ch0 Overflow -> Core `fast_irq_i[7]` (Cause 23, `mip[23]`)
* Timer 1 Ch0 Compare -> Core `fast_irq_i[8]` (Cause 24, `mip[24]`)
* Timer 1 Ch1 Overflow -> Core `fast_irq_i[9]` (Cause 25, `mip[25]`)
* Timer 1 Ch1 Compare -> Core `fast_irq_i[10]` (Cause 26, `mip[26]`)
