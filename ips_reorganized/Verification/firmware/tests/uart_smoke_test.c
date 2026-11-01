/* =============================================================================
 * RISCFORGE 1TOPS — UART Smoke Test
 * ============================================================================= */

#include <stdint.h>
#include "../bsp/soc_regs.h"
#include "../drivers/uart.h"

int main(void) {
    /* Initialize UART with divisor 27 */
    uart_init(27);

    /* Transmit pass signature */
    uart_puts("UART_PASS\n");

    return 0;
}
