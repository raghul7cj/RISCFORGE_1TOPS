/* =============================================================================
 * APB GPIO Verification Example
 * ============================================================================= */

#include "apb_gpio_drv.h"

#define SOC_GPIO_BASE 0x40003000UL

void test_gpio_blink(void) {
    /* Configure Pin 0 as output (e.g. onboard LED) */
    gpio_set_direction(SOC_GPIO_BASE, 0, true);
    
    /* Toggle Pin 0 */
    for (int i = 0; i < 10; i++) {
        gpio_toggle_pin(SOC_GPIO_BASE, 0);
        for (volatile int d = 0; d < 100000; d++);
    }
}
