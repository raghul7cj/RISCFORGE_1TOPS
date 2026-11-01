/* =============================================================================
 * RISCFORGE 1TOPS — APB Timer Driver Implementation (timer.c)
 * ============================================================================= */

#include "timer.h"

void timer0_init(uint32_t compare_val, int irq_enable) {
    /* Stop timer and reset counter */
    TIMER0_CTRL_CH0 = TIMER_CTRL_RESET;
    TIMER0_CMP_CH0  = compare_val;
    if (irq_enable) {
        TIMER0_CTRL_CH0 = TIMER_CTRL_IRQ_EN;
    } else {
        TIMER0_CTRL_CH0 = 0;
    }
}

void timer0_start(void) {
    TIMER0_CTRL_CH0 |= TIMER_CTRL_EN;
}

void timer0_stop(void) {
    TIMER0_CTRL_CH0 &= ~TIMER_CTRL_EN;
}

void timer0_reset(void) {
    TIMER0_CTRL_CH0 |= TIMER_CTRL_RESET;
}

uint32_t timer0_get_val(void) {
    return TIMER0_VAL_CH0;
}
