/* =============================================================================
 * RISCFORGE 1TOPS — UART Minimal Verification Test
 * =============================================================================
 * Verifies:
 *   1. Direct execution from ISRAM (0x0001_0000)
 *   2. DSRAM read/write and stack frame operations (0x0002_0000)
 *   3. AXI-Lite Crossbar + APB Bridge MMIO writes to UART (0x4000_2000)
 *   4. LSR Status Polling & Byte Transmission
 * ============================================================================= */

#include "../bsp/uart_min.h"

int main(void) {
    /* Initialize UART at 0x4000_2000 */
    uart_init();

    /* Send banner */
    uart_puts("\n==============================================\n");
    uart_puts("   RISCFORGE SoC UART Verification Smoke Test  \n");
    uart_puts("==============================================\n");

    /* Test ALU & arithmetic printing */
    uint32_t a = 0x12340000;
    uint32_t b = 0x00005678;
    uint32_t sum = a | b;

    uart_puts("[INFO] Testing MMIO & ALU:\n");
    uart_puts("  Value A   : ");
    uart_puthex(a);
    uart_puts("\n  Value B   : ");
    uart_puthex(b);
    uart_puts("\n  A | B     : ");
    uart_puthex(sum);
    uart_puts("\n");

    if (sum == 0x12345678) {
        uart_puts("\n>>> UART & DATAPATH TEST: [ PASSED ] <<<\n\n");
    } else {
        uart_puts("\n>>> UART & DATAPATH TEST: [ FAILED ] <<<\n\n");
    }

    return 0;
}

