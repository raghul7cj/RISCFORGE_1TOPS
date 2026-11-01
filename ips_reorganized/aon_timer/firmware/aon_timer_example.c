/* =============================================================================
 * OpenTitan Always-On (AON) Timer Example / Test Routine
 * ============================================================================= */

#include "aon_timer_regs.h"

void aon_timer_watchdog_start(uintptr_t base, uint32_t bark_ticks, uint32_t bite_ticks) {
    /* 1. Disable watchdog during configuration */
    AON_TIMER_WDOG_CTRL_REG(base) = 0x0;
    
    /* 2. Clear watchdog counter */
    AON_TIMER_WDOG_COUNT_REG(base) = 0x0;
    
    /* 3. Program Bark and Bite thresholds */
    AON_TIMER_WDOG_BARK_THOLD_REG(base) = bark_ticks;
    AON_TIMER_WDOG_BITE_THOLD_REG(base) = bite_ticks;
    
    /* 4. Enable Watchdog (bit 0 = enable, bit 1 = pause in sleep) */
    AON_TIMER_WDOG_CTRL_REG(base) = 0x1;
}

void aon_timer_watchdog_pet(uintptr_t base) {
    /* Reset watchdog counter to zero */
    AON_TIMER_WDOG_COUNT_REG(base) = 0x0;
    /* Clear any pending bark interrupt */
    AON_TIMER_INTR_STATE_REG(base) = AON_TIMER_INTR_WDOG_TIMER_BARK;
}
