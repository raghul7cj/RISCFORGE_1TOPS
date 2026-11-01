#ifndef UART_MIN_H
#define UART_MIN_H

#include <stdint.h>

/* =============================================================================
 * RISCFORGE 1TOPS — Minimal 16550 UART Driver
 * Base Address: 0x4000_2000 (APB[2])
 * ============================================================================= */

#define UART_BASE         0x40002000UL

/* Register byte offsets (matching apb_uart 3-bit word addressing PADDR[4:2]) */
#define UART_RBR          (*(volatile uint32_t *)(UART_BASE + 0x00)) /* RX Buffer (Read) */
#define UART_THR          (*(volatile uint32_t *)(UART_BASE + 0x00)) /* TX Holding Register (Write) */
#define UART_DLL          (*(volatile uint32_t *)(UART_BASE + 0x00)) /* Divisor Latch LSB (DLAB=1) */
#define UART_IER          (*(volatile uint32_t *)(UART_BASE + 0x04)) /* Interrupt Enable */
#define UART_DLM          (*(volatile uint32_t *)(UART_BASE + 0x04)) /* Divisor Latch MSB (DLAB=1) */
#define UART_IIR          (*(volatile uint32_t *)(UART_BASE + 0x08)) /* Interrupt Ident (Read) */
#define UART_FCR          (*(volatile uint32_t *)(UART_BASE + 0x08)) /* FIFO Control (Write) */
#define UART_LCR          (*(volatile uint32_t *)(UART_BASE + 0x0C)) /* Line Control Register */
#define UART_MCR          (*(volatile uint32_t *)(UART_BASE + 0x10)) /* Modem Control Register */
#define UART_LSR          (*(volatile uint32_t *)(UART_BASE + 0x14)) /* Line Status Register */
#define UART_MSR          (*(volatile uint32_t *)(UART_BASE + 0x18)) /* Modem Status Register */
#define UART_SCR          (*(volatile uint32_t *)(UART_BASE + 0x1C)) /* Scratchpad Register */

/* LSR Status Bits */
#define UART_LSR_DR       (1 << 0)  /* Data Ready */
#define UART_LSR_THRE     (1 << 5)  /* Transmitter Holding Register Empty */
#define UART_LSR_TEMT     (1 << 6)  /* Transmitter Empty */

/* LCR Bits */
#define UART_LCR_8BIT     (3 << 0)  /* 8 data bits, 1 stop bit, no parity */
#define UART_LCR_DLAB     (1 << 7)  /* Divisor Latch Access Bit */

static inline void uart_init(void) {
    /* 1. Disable all interrupts */
    UART_IER = 0x00;

    /* 2. Set 8-bit word length (8N1) */
    UART_LCR = UART_LCR_8BIT;

    /* 3. Enable and reset FIFOs */
    UART_FCR = 0x07;
}

static inline void uart_putc(char c) {
    /* Wait until TX Holding Register is empty */
    while (!(UART_LSR & UART_LSR_THRE)) {
        /* Busy wait */
    }
    UART_THR = (uint32_t)(uint8_t)c;
}

static inline void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') {
            uart_putc('\r');
        }
        uart_putc(*s++);
    }
}

static inline void uart_puthex(uint32_t val) {
    const char hex_chars[] = "0123456789ABCDEF";
    uart_puts("0x");
    for (int i = 7; i >= 0; i--) {
        uint8_t nibble = (val >> (i * 4)) & 0xF;
        uart_putc(hex_chars[nibble]);
    }
}

#endif /* UART_MIN_H */

