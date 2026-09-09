/* =============================================================================
 * RISCFORGE 1TOPS — UART0 Datapath Verification Test Program
 * ============================================================================= */

#include "uart_min.h"

int main(void) {
    /* Initialize UART */
    uart_init();

    /* Transmit Verification Banner */
    uart_puts("\r\n=======================================================\r\n");
    uart_puts("   RISCFORGE 1TOPS — UART0 & Datapath Smoke Test       \r\n");
    uart_puts("=======================================================\r\n");

    /* Test ALU & Memory writeback */
    volatile uint32_t val1 = 0xAA550000;
    volatile uint32_t val2 = 0x00001234;
    volatile uint32_t result = val1 | val2;

    uart_puts("[INFO] Core ALU Execution:\r\n");
    uart_puts("  Operand 1 : ");
    uart_puthex(val1);
    uart_puts("\r\n  Operand 2 : ");
    uart_puthex(val2);
    uart_puts("\r\n  Result    : ");
    uart_puthex(result);
    uart_puts("\r\n");

    if (result == 0xAA551234) {
        uart_puts("\r\n>>> TEST RESULT: [ PASSED ] <<<\r\n\r\n");
    } else {
        uart_puts("\r\n>>> TEST RESULT: [ FAILED ] <<<\r\n\r\n");
    }

    return 0;
}

