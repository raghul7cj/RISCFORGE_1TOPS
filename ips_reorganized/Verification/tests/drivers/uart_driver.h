/* =============================================================================
 * RISCFORGE 1TOPS — 16550 APB UART Driver (uart_driver.h)
 * Direct Register Model for National 16550 compatible UART
 * ============================================================================= */

#ifndef RISCFORGE_UART_DRIVER_H_
#define RISCFORGE_UART_DRIVER_H_

#include <stdint.h>
#include "soc_regs.h"

/* Register Offsets (Direct Hardware Model) */
#define UART_RBR_OFFSET 0x00  /* Receiver Buffer (Read-only, DLAB=0) */
#define UART_THR_OFFSET 0x00  /* Transmitter Holding (Write-only, DLAB=0) */
#define UART_DLL_OFFSET 0x00  /* Divisor Latch LSB (DLAB=1) */
#define UART_IER_OFFSET 0x04  /* Interrupt Enable (DLAB=0) */
#define UART_DLM_OFFSET 0x04  /* Divisor Latch MSB (DLAB=1) */
#define UART_IIR_OFFSET 0x08  /* Interrupt Identification (Read-only) */
#define UART_FCR_OFFSET 0x08  /* FIFO Control (Write-only) */
#define UART_LCR_OFFSET 0x0C  /* Line Control */
#define UART_MCR_OFFSET 0x10  /* Modem Control */
#define UART_LSR_OFFSET 0x14  /* Line Status */

/* Bitfields */
#define UART_LCR_DLAB   (1 << 7)
#define UART_LCR_8N1    (3 << 0)
#define UART_LSR_DR     (1 << 0)  /* Data Ready */
#define UART_LSR_OE     (1 << 1)  /* Overrun Error */
#define UART_LSR_PE     (1 << 2)  /* Parity Error */
#define UART_LSR_FE     (1 << 3)  /* Framing Error */
#define UART_LSR_BI     (1 << 4)  /* Break Interrupt */
#define UART_LSR_THRE   (1 << 5)  /* TX Holding Reg Empty */
#define UART_LSR_TEMT   (1 << 6)  /* Transmitter Empty */
#define UART_MCR_LOOP   (1 << 4)  /* Loopback Mode */

/* Standard API */
void     uart_init(uint32_t baud_divisor);
void     uart_enable_loopback(int enable);
int      uart_putc(char c);                          /* Returns 0 on success, -1 on timeout */
int      uart_getc_nonblocking(char *c);
int      uart_getc_blocking(char *c, uint32_t timeout_cycles); /* Returns 0 on success, -1 on timeout */
void     uart_puts(const char *s);

/* Error & Illegal State Recovery */
void     uart_recover(uint32_t baud_divisor);

#endif /* RISCFORGE_UART_DRIVER_H_ */
