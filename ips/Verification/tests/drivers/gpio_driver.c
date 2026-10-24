/* =============================================================================
 * RISCFORGE 1TOPS — APB GPIO Driver (gpio_driver.c)
 * Direct Register Model matching lowRISC gpio_reg_pkg.sv
 * ============================================================================= */

#include "gpio_driver.h"

void gpio_init(void) {
    /* Set all pins to normal GPIO mode */
    REG32_WRITE(APB_GPIO_BASE + GPIO_CFG_OFFSET, 0x00);
    REG32_WRITE(APB_GPIO_BASE + GPIO_MODE_0_OFFSET, 0x00);
    REG32_WRITE(APB_GPIO_BASE + GPIO_MODE_1_OFFSET, 0x00);
    
    /* Disable all interrupts and clear any pending flags */
    REG32_WRITE(APB_GPIO_BASE + GPIO_INTRPT_RISE_EN_OFFSET, 0x00);
    REG32_WRITE(APB_GPIO_BASE + GPIO_INTRPT_FALL_EN_OFFSET, 0x00);
    REG32_WRITE(APB_GPIO_BASE + GPIO_INTRPT_LVL_HIGH_EN_OFFSET, 0x00);
    REG32_WRITE(APB_GPIO_BASE + GPIO_INTRPT_LVL_LOW_EN_OFFSET, 0x00);
    REG32_WRITE(APB_GPIO_BASE + GPIO_INTRPT_STATUS_OFFSET, 0xFFFFFFFF);
}

void gpio_set_direction(uint32_t dir_mask) {
    /* 1 = output enabled, 0 = input */
    REG32_WRITE(APB_GPIO_BASE + GPIO_EN_OFFSET, dir_mask);
}

void gpio_write(uint32_t val) {
    REG32_WRITE(APB_GPIO_BASE + GPIO_OUT_OFFSET, val);
}

uint32_t gpio_read(void) {
    return REG32_READ(APB_GPIO_BASE + GPIO_IN_OFFSET);
}

void gpio_set_bits(uint32_t mask) {
    /* Atomic Set without read-modify-write hazard */
    REG32_WRITE(APB_GPIO_BASE + GPIO_SET_OFFSET, mask);
}

void gpio_clear_bits(uint32_t mask) {
    /* Atomic Clear without read-modify-write hazard */
    REG32_WRITE(APB_GPIO_BASE + GPIO_CLEAR_OFFSET, mask);
}

void gpio_toggle_bits(uint32_t mask) {
    /* Atomic Toggle */
    REG32_WRITE(APB_GPIO_BASE + GPIO_TOGGLE_OFFSET, mask);
}

void gpio_config_irq(uint32_t rise_mask, uint32_t fall_mask, uint32_t lvl_hi_mask, uint32_t lvl_lo_mask) {
    REG32_WRITE(APB_GPIO_BASE + GPIO_INTRPT_RISE_EN_OFFSET, rise_mask);
    REG32_WRITE(APB_GPIO_BASE + GPIO_INTRPT_FALL_EN_OFFSET, fall_mask);
    REG32_WRITE(APB_GPIO_BASE + GPIO_INTRPT_LVL_HIGH_EN_OFFSET, lvl_hi_mask);
    REG32_WRITE(APB_GPIO_BASE + GPIO_INTRPT_LVL_LOW_EN_OFFSET, lvl_lo_mask);
}

uint32_t gpio_get_irq_status(void) {
    return REG32_READ(APB_GPIO_BASE + GPIO_INTRPT_STATUS_OFFSET);
}

void gpio_clear_irq(uint32_t mask) {
    REG32_WRITE(APB_GPIO_BASE + GPIO_INTRPT_STATUS_OFFSET, mask); /* W1C */
}

/* Recover from floating pins, stuck interrupts, or corrupted direction registers */
void gpio_recover(void) {
    /* 1. Disable all interrupt enables */
    REG32_WRITE(APB_GPIO_BASE + GPIO_INTRPT_RISE_EN_OFFSET, 0x00);
    REG32_WRITE(APB_GPIO_BASE + GPIO_INTRPT_FALL_EN_OFFSET, 0x00);
    REG32_WRITE(APB_GPIO_BASE + GPIO_INTRPT_LVL_HIGH_EN_OFFSET, 0x00);
    REG32_WRITE(APB_GPIO_BASE + GPIO_INTRPT_LVL_LOW_EN_OFFSET, 0x00);
    
    /* 2. Clear all pending interrupt bits via W1C */
    REG32_WRITE(APB_GPIO_BASE + GPIO_INTRPT_STATUS_OFFSET, 0xFFFFFFFF);
    
    /* 3. Tri-state all output drivers (set all as inputs) to prevent bus contention */
    REG32_WRITE(APB_GPIO_BASE + GPIO_EN_OFFSET, 0x00000000);
    REG32_WRITE(APB_GPIO_BASE + GPIO_OUT_OFFSET, 0x00000000);
}
