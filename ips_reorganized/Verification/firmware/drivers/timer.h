/* =============================================================================
 * RISCFORGE 1TOPS — APB Timer Driver Header (timer.h)
 * ============================================================================= */

#ifndef RISCFORGE_TIMER_H
#define RISCFORGE_TIMER_H

#include <stdint.h>
#include "../bsp/soc_regs.h"

void     timer0_init(uint32_t compare_val, int irq_enable);
void     timer0_start(void);
void     timer0_stop(void);
void     timer0_reset(void);
uint32_t timer0_get_val(void);

#endif /* RISCFORGE_TIMER_H */
