/* =============================================================================
 * RISCFORGE 1TOPS — 16550 UART Peripheral Driver Header (uart.h)
 * ============================================================================= */

#ifndef RISCFORGE_UART_H
#define RISCFORGE_UART_H

#include <stdint.h>
#include "../bsp/soc_regs.h"

void uart_init(uint32_t baud_divisor);
void uart_putc(char c);
void uart_puts(const char *str);
int  uart_getc_nonblocking(void);
char uart_getc_blocking(void);

#endif /* RISCFORGE_UART_H */
