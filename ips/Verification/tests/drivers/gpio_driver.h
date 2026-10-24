/* =============================================================================
 * RISCFORGE 1TOPS — APB GPIO Driver (gpio_driver.h)
 * Direct Register Model matching lowRISC gpio_reg_pkg.sv
 * ============================================================================= */

#ifndef RISCFORGE_GPIO_DRIVER_H_
#define RISCFORGE_GPIO_DRIVER_H_

#include <stdint.h>
#include "soc_regs.h"

/* Register Offsets (Direct Hardware Model: gpio_reg_pkg.sv) */
#define GPIO_INFO_OFFSET                0x000
#define GPIO_CFG_OFFSET                 0x004
#define GPIO_MODE_0_OFFSET              0x008
#define GPIO_MODE_1_OFFSET              0x00C
#define GPIO_EN_OFFSET                  0x080  /* Direction / Output Enable */
#define GPIO_IN_OFFSET                  0x100  /* Pin Input Read */
#define GPIO_OUT_OFFSET                 0x180  /* Direct Output Write */
#define GPIO_SET_OFFSET                 0x200  /* Atomic Bit Set (W1S) */
#define GPIO_CLEAR_OFFSET               0x280  /* Atomic Bit Clear (W1C) */
#define GPIO_TOGGLE_OFFSET              0x300  /* Atomic Bit Toggle */
#define GPIO_INTRPT_RISE_EN_OFFSET      0x380  /* Rising Edge IRQ Enable */
#define GPIO_INTRPT_FALL_EN_OFFSET      0x400  /* Falling Edge IRQ Enable */
#define GPIO_INTRPT_LVL_HIGH_EN_OFFSET  0x480  /* Level High IRQ Enable */
#define GPIO_INTRPT_LVL_LOW_EN_OFFSET   0x500  /* Level Low IRQ Enable */
#define GPIO_INTRPT_STATUS_OFFSET       0x580  /* Interrupt Pending / Clear (W1C) */

/* Basic Testing & Pin IO API */
void     gpio_init(void);
void     gpio_set_direction(uint32_t dir_mask); /* 1 = output, 0 = input */
void     gpio_write(uint32_t val);
uint32_t gpio_read(void);
void     gpio_set_bits(uint32_t mask);
void     gpio_clear_bits(uint32_t mask);
void     gpio_toggle_bits(uint32_t mask);

/* Interrupt Management */
void     gpio_config_irq(uint32_t rise_mask, uint32_t fall_mask, uint32_t lvl_hi_mask, uint32_t lvl_lo_mask);
uint32_t gpio_get_irq_status(void);
void     gpio_clear_irq(uint32_t mask);

/* Error & Illegal State Recovery */
void     gpio_recover(void);

#endif /* RISCFORGE_GPIO_DRIVER_H_ */
