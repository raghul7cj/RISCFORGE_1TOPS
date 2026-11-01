/* =============================================================================
 * RISCFORGE APB UART Driver & 16550 Register Definitions
 * Base Address: UART_BASE = 0x40002000
 * ============================================================================= */

#ifndef APB_UART_DRV_H
#define APB_UART_DRV_H

#include <stdint.h>

#define UART_REG32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))

#define UART_RBR(base)   UART_REG32((base) + 0x00) /* RX Buffer (DLAB=0, Read) */
#define UART_THR(base)   UART_REG32((base) + 0x00) /* TX Holding (DLAB=0, Write) */
#define UART_DLL(base)   UART_REG32((base) + 0x00) /* Baud Divisor LSB (DLAB=1) */
#define UART_IER(base)   UART_REG32((base) + 0x04) /* Interrupt Enable */
#define UART_DLM(base)   UART_REG32((base) + 0x04) /* Baud Divisor MSB (DLAB=1) */
#define UART_IIR(base)   UART_REG32((base) + 0x08) /* Interrupt Identification */
#define UART_FCR(base)   UART_REG32((base) + 0x08) /* FIFO Control (Write) */
#define UART_LCR(base)   UART_REG32((base) + 0x0C) /* Line Control */
#define UART_MCR(base)   UART_REG32((base) + 0x10) /* Modem Control */
#define UART_LSR(base)   UART_REG32((base) + 0x14) /* Line Status */
#define UART_MSR(base)   UART_REG32((base) + 0x18) /* Modem Status */
#define UART_SCR(base)   UART_REG32((base) + 0x1C) /* Scratch Register */

#define UART_LSR_DR      (1U << 0) /* Data Ready */
#define UART_LSR_THRE    (1U << 5) /* Transmitter Holding Register Empty */
#define UART_LSR_TEMT    (1U << 6) /* Transmitter Empty */

#define UART_LCR_DLAB    (1U << 7) /* Divisor Latch Access Bit */
#define UART_LCR_8N1     (0x03U)   /* 8 bits, no parity, 1 stop bit */

static inline void uart_init(uintptr_t base, uint32_t baud_divisor) {
    /* Enable DLAB to access divisor latch */
    UART_LCR(base) = UART_LCR_DLAB | UART_LCR_8N1;
    UART_DLL(base) = baud_divisor & 0xFF;
    UART_DLM(base) = (baud_divisor >> 8) & 0xFF;
    /* Clear DLAB, set 8N1 */
    UART_LCR(base) = UART_LCR_8N1;
    /* Enable FIFO, reset RX and TX FIFOs */
    UART_FCR(base) = 0x07;
    /* Disable interrupts by default */
    UART_IER(base) = 0x00;
}

static inline void uart_putc(uintptr_t base, char c) {
    while (!(UART_LSR(base) & UART_LSR_THRE));
    UART_THR(base) = (uint32_t)(uint8_t)c;
}

static inline char uart_getc(uintptr_t base) {
    while (!(UART_LSR(base) & UART_LSR_DR));
    return (char)(UART_RBR(base) & 0xFF);
}

static inline void uart_puts(uintptr_t base, const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc(base, '\r');
        uart_putc(base, *s++);
    }
}

#endif /* APB_UART_DRV_H */
