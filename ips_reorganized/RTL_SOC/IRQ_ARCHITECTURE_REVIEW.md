# RISCFORGE SoC — Interrupt Architecture Review

Scope: `RTL_SOC/riscforge_soc_subsystem.sv` (interrupt wiring, Section 21),
`riscv_core/rtl/top.v` (gateway/arbiter/CSR), `irq_gateway.v`, `irq_arbiter.v`,
`wb_trap_mret_commit_controller.v`, `apb_timer-master/rtl/timer.sv`,
`gpio-master/gpio.sv`, `apb_uart`, `apb_i2c-master/apb_i2c.sv`,
`spi_master_ip/spi_master/apb_spi_master.sv`.

Method: static RTL reading only. Nothing simulated or synthesised.

## 1. Source map

| Source | mip cause | Gateway mode | Class | Notes |
|---|---|---|---|---|
| Timer 0 ch0 compare | 7 (MTIP) | event (latched) | 2 fixed | `timer_irq_i` = `timer0_irq_o[1]` on the top port (note: not `[0]`) |
| Timer 1 ch0 overflow / compare | 23 / 24 | event | 2 fixed | |
| Timer 1 ch1 overflow / compare | 25 / 26 | event | 2 fixed | |
| Timer 0 ch0 overflow | 20 | event | 2 fixed | |
| Timer 0 ch1 overflow / compare | 21 / 22 | event | 2 fixed | |
| UART | 19 | level | 1 RR | |
| SPI threshold | 18 | event | 1 RR | |
| SPI end of transfer | 27 | event | 1 RR | |
| I2C | 17 | level | 0 RR | |
| GPIO global | 16 | rising edge | 0 RR | |

Mode masks: `edge_mode = 13'h0002`, `event_mode = 13'h1fe9` (top.v:213-214). Consistent with the table above.

## 2. What checks out

- Indexing from `fast_irq_i` through the gateway to the arbiter to `mip` bits matches the comments in the SoC top.
- Arbiter class ordering, round-robin pointers and the `mintprio` threshold are correct.
- Clear strobe: `clear_gateway_r[cause - 15]` maps causes 16..27 to bits 1..12, and cause 7 to bit 0. Interrupt-qualified. A new capture on the same cycle wins over the clear.

## 3. Open issues

### BUG-IRQ-1 — Stale latched events cannot be discarded (severity: medium)
The gateway latches event and edge sources regardless of `mie`. The only clear is trap commit (`irq_gateway.v`, `pend_q & ~clear_i`). `mip` writes only touch MSIP. Consequence: a timer or SPI event that fired while its enable was off, or a timer run in polling mode, produces a spurious interrupt as soon as its `mie` bit is set.
**Suggested fix:** add a software write-1-to-clear for the latched bits, via `mip` or a custom CSR.

### BUG-IRQ-2 — GPIO can go deaf in sticky mode (severity: high when sticky mode is used)
With `CFG.glbl_intrpt_mode = 1` the GPIO output is the OR of sticky status bits (`gpio.sv:140`). If a new pin event arrives between the handler's status read and its clear, the line never drops. The edge gateway then never sees another rising edge, and the source is lost until reset.
**Suggested fix:** use mode 0 (one-cycle pulse), or switch the gateway bit to level mode when sticky is selected.

### BUG-IRQ-3 — Fast event sources drop ticks silently; can starve mainline code (severity: medium)
- Timer period is `(CMP+1) × (PRESCALER+1)` cycles, minimum 2 (`timer.sv:63`).
- Pulses arriving while the bit is already pending coalesce with no overrun flag.
- Interrupts are accepted on the first instruction after `mret`. A period shorter than the handler means no mainline progress.
- Class 2 is fixed priority, so a very fast MTIP starves all other sources.
- The prescaler counter free-runs, so the first period after enable can be short by up to `PRESCALER` cycles.
**Suggested fix:** document a minimum period, add an overrun/missed-count status bit, and consider a minimum-service guarantee in the arbiter.

## 4. Minor / documentation

- MTIP behaves as a latch cleared on trap entry, not a level cleared by rewriting the compare. Ported code expecting a compare-clear will differ.
- `mip.MSIP` is writable but no cause 3/11 exists in the arbiter, so software interrupts can never fire.
- `CMP = 0xFFFF_FFFF` raises compare and overflow in the same cycle, giving two causes for one event.
- `timer_irq_i` is driven from `timer0_irq_o[1]`, which is Timer 0 channel 0 compare (`timer.sv`: bit 0 = overflow, bit 1 = compare). The table above lists MTIP as ch0 compare, which is consistent with this. Confirm that is the intended MTIP source.
- UART `INT` polarity and held-level behaviour not confirmed from the UART source.

## 5. Status

Findings only. No RTL changed. No simulation run.
