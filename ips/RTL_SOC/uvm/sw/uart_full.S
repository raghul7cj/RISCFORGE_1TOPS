#include "common.h"

.section .text.init
.globl _start
_start:
  UART_INIT
  li   t1, 0x05
  sw   t1, UART_IER(s0)
  lw   t2, UART_IER(s0)
  andi t2, t2, 0x0F
  CHECK t2, 0x05, 1
  sw   zero, UART_IER(s0)
  li   t1, 0x03
  sw   t1, UART_MCR(s0)
  lw   t2, UART_MCR(s0)
  andi t2, t2, 0x1F
  CHECK t2, 0x03, 2
  sw   zero, UART_MCR(s0)
  lw   t2, UART_LCR(s0)
  andi t2, t2, 0xFF
  CHECK t2, 0x03, 3

  li   t1, 'A'
  li   t3, 'I'
tx_burst:
  sw   t1, UART_THR(s0)
  addi t1, t1, 1
  bne  t1, t3, tx_burst

  PHASE 1
  li   a7, 20000
wait_rx:
  addi a7, a7, -1
  bnez a7, wait_rx

  li   t3, '1'
  li   t4, '9'
rx_loop:
  lw   t2, UART_LSR(s0)
  andi t2, t2, 1
  beqz t2, bad_empty
  lw   t2, UART_RBR(s0)
  andi t2, t2, 0xFF
  bne  t2, t3, bad_data
  addi t3, t3, 1
  bne  t3, t4, rx_loop

  lw   t2, UART_LSR(s0)
  andi t2, t2, 1
  CHECK t2, 0, 6
  UART_FLUSH
  PASS

bad_empty:
  FAIL 4
bad_data:
  FAIL 5
