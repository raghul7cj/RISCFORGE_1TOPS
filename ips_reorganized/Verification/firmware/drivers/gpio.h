/* =============================================================================
 * RISCFORGE 1TOPS — 32-bit GPIO Driver Header (gpio.h)
 * ============================================================================= */

#ifndef RISCFORGE_GPIO_H
#define RISCFORGE_GPIO_H

#include <stdint.h>
#include "../bsp/soc_regs.h"

void     gpio_set_output_enable(uint32_t mask);
void     gpio_write(uint32_t value);
uint32_t gpio_read(void);
void     gpio_set_interrupt_enable(uint32_t mask);
void     gpio_clear_interrupt(uint32_t mask);

#endif /* RISCFORGE_GPIO_H */
