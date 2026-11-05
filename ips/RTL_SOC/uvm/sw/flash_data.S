#include "common.h"

.section .text.init
.globl _start
_start:
  li   s1, DSRAM_BASE
  lw   t2, 8(s1)
  CHECK t2, 0xFFFFFFFF, 1
  lw   t2, 12(s1)
  CHECK t2, 0x00000000, 2
  lw   t2, 16(s1)
  CHECK t2, 0xA5A5A5A5, 3
  lw   t2, 20(s1)
  CHECK t2, 0x5A5A5A5A, 4
  lw   t2, 24(s1)
  CHECK t2, 0x12345678, 5
  lw   t2, 28(s1)
  CHECK t2, 0xFFFF0000, 6
  UART_INIT
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
