/* =============================================================================
 * RISCFORGE APB Timer Driver & Register Definitions
 * Base Addresses: TIMER0 = 0x40001000, TIMER1 = 0x40005000 (2 Channels Each)
 * Verified directly against RTL: apb_timer-master/rtl/apb_timer.sv
 * (Channel 0 at +0x00, Channel 1 at +0x10 per PADDR[4] selection)
 * ============================================================================= */

#ifndef APB_TIMER_DRV_H
#define APB_TIMER_DRV_H

#include <stdint.h>
#include <stdbool.h>

#define TIMER_REG32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))

#define TIMER_CH_OFFSET(ch)      ((ch) ? 0x10 : 0x00)
#define TIMER_REG_VAL(base, ch)  TIMER_REG32((base) + TIMER_CH_OFFSET(ch) + 0x00)
#define TIMER_REG_CTRL(base, ch) TIMER_REG32((base) + TIMER_CH_OFFSET(ch) + 0x04)
#define TIMER_REG_CMP(base, ch)  TIMER_REG32((base) + TIMER_CH_OFFSET(ch) + 0x08)

#define TIMER_CTRL_EN            (1U << 0)
#define TIMER_CTRL_PRESCALER(x)  (((x) & 0x07U) << 1)

static inline void timer_init(uintptr_t base, uint32_t ch, uint32_t prescaler) {
    TIMER_REG_CTRL(base, ch) = 0;
    TIMER_REG_VAL(base, ch)  = 0;
    TIMER_REG_CMP(base, ch)  = 0;
    TIMER_REG_CTRL(base, ch) = TIMER_CTRL_PRESCALER(prescaler);
}

static inline void timer_start(uintptr_t base, uint32_t ch, uint32_t cmp_val) {
    uint32_t ctrl = TIMER_REG_CTRL(base, ch);
    TIMER_REG_CMP(base, ch)  = cmp_val;
    TIMER_REG_VAL(base, ch)  = 0;
    TIMER_REG_CTRL(base, ch) = ctrl | TIMER_CTRL_EN;
}

static inline void timer_stop(uintptr_t base, uint32_t ch) {
    TIMER_REG_CTRL(base, ch) &= ~TIMER_CTRL_EN;
}

static inline uint32_t timer_get_val(uintptr_t base, uint32_t ch) {
    return TIMER_REG_VAL(base, ch);
}

#endif /* APB_TIMER_DRV_H */
