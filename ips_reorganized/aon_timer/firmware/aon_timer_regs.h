/* =============================================================================
 * OpenTitan Always-On (AON) Timer Register Definitions Header
 * Target: OpenTitan hw/ip/aon_timer (lowRISC/opentitan)
 * ============================================================================= */

#ifndef AON_TIMER_REGS_H
#define AON_TIMER_REGS_H

#include <stdint.h>

#define AON_REG32(base, offset) (*(volatile uint32_t *)(uintptr_t)((base) + (offset)))

#define AON_TIMER_ALERT_TEST_REG(base)     AON_REG32(base, 0x00)
#define AON_TIMER_WKUP_CTRL_REG(base)      AON_REG32(base, 0x04)
#define AON_TIMER_WKUP_THOLD_HI_REG(base)  AON_REG32(base, 0x08)
#define AON_TIMER_WKUP_THOLD_LO_REG(base)  AON_REG32(base, 0x0C)
#define AON_TIMER_WKUP_COUNT_HI_REG(base)  AON_REG32(base, 0x10)
#define AON_TIMER_WKUP_COUNT_LO_REG(base)  AON_REG32(base, 0x14)
#define AON_TIMER_WDOG_REGWEN_REG(base)    AON_REG32(base, 0x18)
#define AON_TIMER_WDOG_CTRL_REG(base)      AON_REG32(base, 0x1C)
#define AON_TIMER_WDOG_BARK_THOLD_REG(base) AON_REG32(base, 0x20)
#define AON_TIMER_WDOG_BITE_THOLD_REG(base) AON_REG32(base, 0x24)
#define AON_TIMER_WDOG_COUNT_REG(base)     AON_REG32(base, 0x28)
#define AON_TIMER_INTR_STATE_REG(base)     AON_REG32(base, 0x2C)
#define AON_TIMER_INTR_TEST_REG(base)      AON_REG32(base, 0x30)
#define AON_TIMER_WKUP_CAUSE_REG(base)     AON_REG32(base, 0x34)

/* Interrupt State / Test bits */
#define AON_TIMER_INTR_WKUP_TIMER_EXPIRED (1U << 0)
#define AON_TIMER_INTR_WDOG_TIMER_BARK    (1U << 1)

#endif /* AON_TIMER_REGS_H */
