#include "common.h"

.section .text.init
.globl _start
_start:
  UART_INIT_NOFIFO
  li   a0, 'h'
  PUTC a0
  li   a0, 'e'
  PUTC a0
  li   a0, 'l'
  PUTC a0
  PUTC a0
  li   a0, 'o'
  PUTC a0
  li   a0, 10
  PUTC a0
  UART_FLUSH
  PASS
