/* =============================================================================
 * RISCFORGE 1TOPS — 16550 APB UART Driver (uart_driver.c)
 * Direct Register Model for National 16550 compatible UART
 * ============================================================================= */

#include "uart_driver.h"

#define UART_DEFAULT_TIMEOUT_CYCLES 500000UL

void uart_init(uint32_t baud_divisor) {
    /* Set DLAB to access DLL and DLM */
    REG32_WRITE(APB_UART_BASE + UART_LCR_OFFSET, UART_LCR_DLAB);
    REG32_WRITE(APB_UART_BASE + UART_DLL_OFFSET, baud_divisor & 0xFF);
    REG32_WRITE(APB_UART_BASE + UART_DLM_OFFSET, (baud_divisor >> 8) & 0xFF);
    
    /* 8 data bits, 1 stop bit, no parity (8N1) */
    REG32_WRITE(APB_UART_BASE + UART_LCR_OFFSET, UART_LCR_8N1);
    
    /* Enable and reset TX/RX FIFOs (FCR: enable=1, clr_rx=2, clr_tx=4 -> 0x07) */
    REG32_WRITE(APB_UART_BASE + UART_FCR_OFFSET, 0x07);
    
    /* Disable interrupts by default */
    REG32_WRITE(APB_UART_BASE + UART_IER_OFFSET, 0x00);
}

void uart_enable_loopback(int enable) {
    uint32_t mcr = REG32_READ(APB_UART_BASE + UART_MCR_OFFSET);
    if (enable) {
        mcr |= UART_MCR_LOOP;
    } else {
        mcr &= ~UART_MCR_LOOP;
    }
    REG32_WRITE(APB_UART_BASE + UART_MCR_OFFSET, mcr);
}

int uart_putc(char c) {
    uint32_t start_cycle = csr_read_mcycle();
    
    /* Wait for Transmitter Holding Register Empty (THRE) with bounded timeout */
    while (!(REG32_READ(APB_UART_BASE + UART_LSR_OFFSET) & UART_LSR_THRE)) {
        if ((csr_read_mcycle() - start_cycle) > UART_DEFAULT_TIMEOUT_CYCLES) {
            return -1; /* Timeout failure */
        }
    }
    REG32_WRITE(APB_UART_BASE + UART_THR_OFFSET, (uint32_t)(uint8_t)c);
    return 0;
}

int uart_getc_nonblocking(char *c) {
    uint32_t lsr = REG32_READ(APB_UART_BASE + UART_LSR_OFFSET);
    if (lsr & UART_LSR_DR) {
        *c = (char)(REG32_READ(APB_UART_BASE + UART_RBR_OFFSET) & 0xFF);
        return 1; /* Success */
    }
    return 0; /* No data */
}

int uart_getc_blocking(char *c, uint32_t timeout_cycles) {
    uint32_t start_cycle = csr_read_mcycle();
    uint32_t limit = (timeout_cycles == 0) ? UART_DEFAULT_TIMEOUT_CYCLES : timeout_cycles;
    
    while (!(REG32_READ(APB_UART_BASE + UART_LSR_OFFSET) & UART_LSR_DR)) {
        if ((csr_read_mcycle() - start_cycle) > limit) {
            return -1; /* Timeout */
        }
    }
    *c = (char)(REG32_READ(APB_UART_BASE + UART_RBR_OFFSET) & 0xFF);
    return 0; /* Success */
}

void uart_puts(const char *s) {
    while (*s) {
        if (uart_putc(*s++) != 0) {
            break; /* Stop on hardware timeout */
        }
    }
}

/* Recover from Framing/Parity/Overrun errors, stuck FIFOs, or invalid line state */
void uart_recover(uint32_t baud_divisor) {
    /* 1. Flush Line Status Register errors by reading it */
    volatile uint32_t dummy_lsr = REG32_READ(APB_UART_BASE + UART_LSR_OFFSET);
    (void)dummy_lsr;
    
    /* 2. Flush Receive Buffer Register by reading until empty */
    while (REG32_READ(APB_UART_BASE + UART_LSR_OFFSET) & UART_LSR_DR) {
        volatile uint32_t dummy_rbr = REG32_READ(APB_UART_BASE + UART_RBR_OFFSET);
        (void)dummy_rbr;
    }
    
    /* 3. Force FIFO clear & reset */
    REG32_WRITE(APB_UART_BASE + UART_FCR_OFFSET, 0x07);
    
    /* 4. Re-apply Baud Divisor and 8N1 configuration */
    REG32_WRITE(APB_UART_BASE + UART_LCR_OFFSET, UART_LCR_DLAB);
    REG32_WRITE(APB_UART_BASE + UART_DLL_OFFSET, baud_divisor & 0xFF);
    REG32_WRITE(APB_UART_BASE + UART_DLM_OFFSET, (baud_divisor >> 8) & 0xFF);
    REG32_WRITE(APB_UART_BASE + UART_LCR_OFFSET, UART_LCR_8N1);
}
