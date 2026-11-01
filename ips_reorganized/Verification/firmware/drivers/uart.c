/* =============================================================================
 * RISCFORGE 1TOPS — 16550 UART Peripheral Driver Implementation (uart.c)
 * ============================================================================= */

#include "uart.h"

void uart_init(uint32_t baud_divisor) {
    /* 1. Disable all interrupts */
    UART_IER = 0x00;

    /* 2. Enable Divisor Latch Access (DLAB = 1) in LCR */
    UART_LCR = 0x80;

    /* 3. Program divisor */
    UART_DLL = (baud_divisor & 0xFF);
    UART_DLM = ((baud_divisor >> 8) & 0xFF);

    /* 4. Configure: 8 data bits, 1 stop bit, no parity (DLAB = 0) */
    UART_LCR = 0x03;

    /* 5. Enable and clear FIFOs */
    UART_FCR = 0x07;
}

void uart_putc(char c) {
    /* Poll until Transmitter Holding Register Empty (THRE = 1) */
    while (!(UART_LSR & UART_LSR_THRE));
    UART_THR = (uint32_t)c;
}

void uart_puts(const char *str) {
    while (*str) {
        if (*str == '\n') {
            uart_putc('\r');
        }
        uart_putc(*str++);
    }
}

int uart_getc_nonblocking(void) {
    if (UART_LSR & UART_LSR_DR) {
        return (int)(UART_RBR & 0xFF);
    }
    return -1;
}

char uart_getc_blocking(void) {
    while (!(UART_LSR & UART_LSR_DR));
    return (char)(UART_RBR & 0xFF);
}
