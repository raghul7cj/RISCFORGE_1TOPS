#include "common.h"

.section .text.init
.globl _start
_start:
  UART_INIT
  li   s1, 4
loop:
  GETC a0
  PUTC a0
  addi s1, s1, -1
  bnez s1, loop
  UART_FLUSH
  PASS
