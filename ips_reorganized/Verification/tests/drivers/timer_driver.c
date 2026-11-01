/* =============================================================================
 * RISCFORGE 1TOPS — APB Timer Driver (timer_driver.c)
 * Direct Register Model for ETH Zurich APB Timer
 * ============================================================================= */

#include "timer_driver.h"

void timer_init(uint32_t timer_base, uint8_t prescaler_exp, uint32_t compare_val) {
    /* Stop timer first */
    REG32_WRITE(timer_base + TIMER_CTRL_OFFSET, 0x00);
    
    /* Set Compare value (this also resets the timer counter in hardware) */
    REG32_WRITE(timer_base + TIMER_CMP_OFFSET, compare_val);
    
    /* Set Prescaler while keeping timer disabled */
    uint32_t ctrl = ((uint32_t)(prescaler_exp & 0x07) << TIMER_CTRL_PRESC_SHIFT);
    REG32_WRITE(timer_base + TIMER_CTRL_OFFSET, ctrl);
}

void timer_start(uint32_t timer_base) {
    uint32_t ctrl = REG32_READ(timer_base + TIMER_CTRL_OFFSET);
    REG32_WRITE(timer_base + TIMER_CTRL_OFFSET, ctrl | TIMER_CTRL_EN);
}

void timer_stop(uint32_t timer_base) {
    uint32_t ctrl = REG32_READ(timer_base + TIMER_CTRL_OFFSET);
    REG32_WRITE(timer_base + TIMER_CTRL_OFFSET, ctrl & ~TIMER_CTRL_EN);
}

uint32_t timer_get_count(uint32_t timer_base) {
    return REG32_READ(timer_base + TIMER_VAL_OFFSET);
}

void timer_set_count(uint32_t timer_base, uint32_t val) {
    REG32_WRITE(timer_base + TIMER_VAL_OFFSET, val);
}

void timer_set_compare(uint32_t timer_base, uint32_t cmp_val) {
    REG32_WRITE(timer_base + TIMER_CMP_OFFSET, cmp_val);
}

/* Recover from illegal state / runaway timer / stuck IRQ */
void timer_recover(uint32_t timer_base) {
    /* 1. Force disable timer and clear prescaler */
    REG32_WRITE(timer_base + TIMER_CTRL_OFFSET, 0x00);
    
    /* 2. Clear compare register (disabling cmp IRQ generation) */
    REG32_WRITE(timer_base + TIMER_CMP_OFFSET, 0x00);
    
    /* 3. Reset counter value to 0 */
    REG32_WRITE(timer_base + TIMER_VAL_OFFSET, 0x00);
}
