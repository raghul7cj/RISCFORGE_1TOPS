/* =============================================================================
 * RISCFORGE 1TOPS — APB Timer Driver (timer_driver.h)
 * Direct Register Model for ETH Zurich APB Timer
 * ============================================================================= */

#ifndef RISCFORGE_TIMER_DRIVER_H_
#define RISCFORGE_TIMER_DRIVER_H_

#include <stdint.h>
#include "soc_regs.h"

/* Register Offsets (Direct Hardware Model) */
#define TIMER_VAL_OFFSET       0x00  /* 32-bit Counter Value */
#define TIMER_CTRL_OFFSET      0x04  /* Control & Prescaler Register */
#define TIMER_CMP_OFFSET       0x08  /* 32-bit Compare Register (writes reset timer) */

/* CTRL Bitfields */
#define TIMER_CTRL_EN          (1 << 0)
#define TIMER_CTRL_PRESC_SHIFT 3
#define TIMER_CTRL_PRESC_MASK  (0x7 << 3)

/* Basic Testing & Control API */
void     timer_init(uint32_t timer_base, uint8_t prescaler_exp, uint32_t compare_val);
void     timer_start(uint32_t timer_base);
void     timer_stop(uint32_t timer_base);
uint32_t timer_get_count(uint32_t timer_base);
void     timer_set_count(uint32_t timer_base, uint32_t val);
void     timer_set_compare(uint32_t timer_base, uint32_t cmp_val);

/* Error & Illegal State Recovery */
void     timer_recover(uint32_t timer_base);

#endif /* RISCFORGE_TIMER_DRIVER_H_ */
