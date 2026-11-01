/* =============================================================================
 * APB Timer Verification Example
 * ============================================================================= */

#include "apb_timer_drv.h"

#define SOC_TIMER0_BASE 0x40001000UL

void test_timer_periodic(void) {
    /* Initialize Channel 0 with prescaler = 0 (1:1 clock) */
    timer_init(SOC_TIMER0_BASE, 0, 0);
    
    /* Start timer to fire compare interrupt at 50,000 cycles (1 ms @ 50MHz) */
    timer_start(SOC_TIMER0_BASE, 0, 50000);
}
