# OpenTitan Always-On (AON) Timer IP - Firmware & Driver Documentation

## 1. Upstream GitHub Provenance
* **Origin**: lowRISC OpenTitan Project
* **Repository**: [lowRISC/opentitan](https://github.com/lowRISC/opentitan) (`hw/ip/aon_timer`)
* **Firmware Origin**: OpenTitan Device Interface Functions (DIF)
  * [dif_aon_timer.h](https://github.com/lowRISC/opentitan/blob/master/sw/device/lib/dif/dif_aon_timer.h)
  * [dif_aon_timer.c](https://github.com/lowRISC/opentitan/blob/master/sw/device/lib/dif/dif_aon_timer.c)

## 2. RTL Match & Verification Status
* Local RTL (`aon_timer/rtl`) contains the complete OpenTitan AON timer core (`aon_timer.sv`, `aon_timer_core.sv`, `aon_timer_reg_pkg.sv`, `aon_timer_reg_top.sv`).
* Tested with thorough TL-UL self-checking testbenches (`tb_watchdog_full.sv`).

## 3. Register Offsets
| Offset | Name | Description |
|---|---|---|
| `0x04` | `WKUP_CTRL` | Wakeup timer control: `[0]`=enable, `[12:1]`=prescaler |
| `0x08` | `WKUP_THOLD_HI` | Wakeup threshold high word |
| `0x0C` | `WKUP_THOLD_LO` | Wakeup threshold low word |
| `0x18` | `WDOG_REGWEN` | Watchdog configuration write enable lock |
| `0x1C` | `WDOG_CTRL` | Watchdog control: `[0]`=enable, `[1]`=pause in sleep |
| `0x20` | `WDOG_BARK_THOLD` | Watchdog bark threshold |
| `0x24` | `WDOG_BITE_THOLD` | Watchdog bite threshold |
| `0x28` | `WDOG_COUNT` | Watchdog counter current value |
| `0x2C` | `INTR_STATE` | Interrupt state (`[0]`=wkup, `[1]`=bark) |
