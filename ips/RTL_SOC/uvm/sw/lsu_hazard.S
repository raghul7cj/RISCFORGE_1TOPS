#include "common.h"

.section .text.init
.globl _start
_start:
  li   s0, UART_BASE
  li   s1, DSRAM_BASE + 0x200

  li   t1, 0x5A
  sw   t1, UART_SCR(s0)
  lw   t2, UART_SCR(s0)
  andi t2, t2, 0xFF
  CHECK t2, 0x5A, 1

  li   t1, 0xA5
  sw   t1, UART_SCR(s0)
  lw   t2, UART_SCR(s0)
  andi t2, t2, 0xFF
  CHECK t2, 0xA5, 2

  li   t1, 0x11223344
  sw   t1, 0(s1)
  lw   t2, 0(s1)
  CHECK t2, 0x11223344, 3

  li   t1, 0x3C
  sw   t1, UART_SCR(s0)
  addi t3, zero, 7
  CHECK t3, 7, 4
  PASS
