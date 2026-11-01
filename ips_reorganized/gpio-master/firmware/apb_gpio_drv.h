/* =============================================================================
 * RISCFORGE APB GPIO Driver & Register Definitions
 * Target: PULP Parametric GPIO IP (pulp-platform/gpio)
 * Base Address: GPIO_BASE = 0x40003000
 * ============================================================================= */

#ifndef APB_GPIO_DRV_H
#define APB_GPIO_DRV_H

#include <stdint.h>
#include <stdbool.h>

#define GPIO_REG32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))

#define GPIO_REG_EN(base)         GPIO_REG32((base) + 0x080) /* Output Enable Mask */
#define GPIO_REG_IN(base)         GPIO_REG32((base) + 0x100) /* Data Input Read */
#define GPIO_REG_OUT(base)        GPIO_REG32((base) + 0x180) /* Direct Data Output */
#define GPIO_REG_SET(base)        GPIO_REG32((base) + 0x200) /* Atomic Bit Set */
#define GPIO_REG_CLEAR(base)      GPIO_REG32((base) + 0x280) /* Atomic Bit Clear */
#define GPIO_REG_TOGGLE(base)     GPIO_REG32((base) + 0x300) /* Atomic Bit Toggle */
#define GPIO_REG_RISE_EN(base)    GPIO_REG32((base) + 0x380) /* Rising-edge Interrupt Enable */
#define GPIO_REG_FALL_EN(base)    GPIO_REG32((base) + 0x400) /* Falling-edge Interrupt Enable */
#define GPIO_REG_INTR_STAT(base)  GPIO_REG32((base) + 0x580) /* Interrupt Status (W1C) */

static inline void gpio_set_direction(uintptr_t base, uint32_t pin, bool is_output) {
    if (is_output) {
        GPIO_REG_EN(base) |= (1U << pin);
    } else {
        GPIO_REG_EN(base) &= ~(1U << pin);
    }
}

static inline void gpio_write_pin(uintptr_t base, uint32_t pin, bool val) {
    if (val) {
        GPIO_REG_SET(base) = (1U << pin);
    } else {
        GPIO_REG_CLEAR(base) = (1U << pin);
    }
}

static inline void gpio_toggle_pin(uintptr_t base, uint32_t pin) {
    GPIO_REG_TOGGLE(base) = (1U << pin);
}

static inline bool gpio_read_pin(uintptr_t base, uint32_t pin) {
    return (GPIO_REG_IN(base) & (1U << pin)) != 0;
}

static inline void gpio_enable_interrupt(uintptr_t base, uint32_t pin, bool rising, bool falling) {
    if (rising)  GPIO_REG_RISE_EN(base) |= (1U << pin);
    if (falling) GPIO_REG_FALL_EN(base) |= (1U << pin);
}

static inline void gpio_clear_interrupt(uintptr_t base, uint32_t pin) {
    GPIO_REG_INTR_STAT(base) = (1U << pin);
}

#endif /* APB_GPIO_DRV_H */
