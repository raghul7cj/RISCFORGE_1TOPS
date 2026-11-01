/* =============================================================================
 * APB UART Verification Example
 * ============================================================================= */

#include "apb_uart_drv.h"

#define SOC_UART_BASE 0x40002000UL

void test_uart_hello(void) {
    /* 50MHz clk, 115200 baud -> divisor = 50000000 / (16 * 115200) = 27 */
    uart_init(SOC_UART_BASE, 27);
    uart_puts(SOC_UART_BASE, "RISCFORGE 1TOPS SoC UART Initialized!\r\n");
}
