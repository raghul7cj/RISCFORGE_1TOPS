/* =============================================================================
 * RISC-V CLIC Verification Example
 * ============================================================================= */

#include "clic.h"

#define SOC_CLIC_BASE 0x40008000UL /* Placeholder base address */

void test_clic_setup(void) {
    /* Initialize CLIC */
    clic_init(SOC_CLIC_BASE);
    
    /* Configure Interrupt 16 (e.g. GPIO event) with Priority 128, positive edge */
    clic_set_priority(SOC_CLIC_BASE, 16, 128);
    clic_set_trigger(SOC_CLIC_BASE, 16, CLIC_ATTR_TRIG_EDGE_POS, false);
    clic_enable_interrupt(SOC_CLIC_BASE, 16);
}
