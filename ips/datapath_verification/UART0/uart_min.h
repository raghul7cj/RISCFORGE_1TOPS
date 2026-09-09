#ifndef UART_MIN_H
#define UART_MIN_H

#include <stdint.h>

#define UART_BASE         0x40002000UL

#define UART_RBR          (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_THR          (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_DLL          (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_IER          (*(volatile uint32_t *)(UART_BASE + 0x04))
#define UART_DLM          (*(volatile uint32_t *)(UART_BASE + 0x04))
#define UART_IIR          (*(volatile uint32_t *)(UART_BASE + 0x08))
#define UART_FCR          (*(volatile uint32_t *)(UART_BASE + 0x08))
#define UART_LCR          (*(volatile uint32_t *)(UART_BASE + 0x0C))
#define UART_MCR          (*(volatile uint32_t *)(UART_BASE + 0x10))
#define UART_LSR          (*(volatile uint32_t *)(UART_BASE + 0x14))
#define UART_MSR          (*(volatile uint32_t *)(UART_BASE + 0x18))
#define UART_SCR          (*(volatile uint32_t *)(UART_BASE + 0x1C))

#define UART_LSR_DR       (1 << 0)
#define UART_LSR_THRE     (1 << 5)
#define UART_LSR_TEMT     (1 << 6)

#define UART_LCR_8BIT     (3 << 0)
#define UART_LCR_DLAB     (1 << 7)

static inline void uart_init(void) {
    /* 1. Set DLAB=1 to access Baud Rate Divisor Latches */
    UART_LCR = UART_LCR_DLAB | UART_LCR_8BIT;
    /* 2. Configure Divisor = 1 (16 clocks per bit for simulation) */
    UART_DLL = 0x01;
    UART_DLM = 0x00;
    /* 3. Clear DLAB and set 8-bit word format (8N1) */
    UART_LCR = UART_LCR_8BIT;
    /* 4. Disable interrupts */
    UART_IER = 0x00;
    /* 5. Enable & clear FIFOs */
    UART_FCR = 0x07;
}

static inline void uart_putc(char c) {
    while (!(UART_LSR & UART_LSR_THRE)) {
        /* Busy wait polling */
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

