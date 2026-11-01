/* =============================================================================
 * RISCFORGE 1TOPS — 32-bit GPIO Driver Implementation (gpio.c)
 * ============================================================================= */

#include "gpio.h"

void gpio_set_output_enable(uint32_t mask) {
    GPIO_DIRECT_OE = mask;
}

void gpio_write(uint32_t value) {
    GPIO_DIRECT_OUT = value;
}

uint32_t gpio_read(void) {
    return GPIO_DATA_IN;
}

void gpio_set_interrupt_enable(uint32_t mask) {
    GPIO_INTR_ENABLE = mask;
}

void gpio_clear_interrupt(uint32_t mask) {
    GPIO_INTR_STATE = mask;
}
