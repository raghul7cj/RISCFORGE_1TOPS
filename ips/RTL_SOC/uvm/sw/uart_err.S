#include "common.h"

.section .text.init
.globl _start
_start:
  UART_INIT
  li   t0, 0x0F
  sw   t0, UART_IER(s0)
  DELAY 20
  lw   t2, UART_IIR(s0)
  andi t2, t2, 0x0F
  CHECK t2, 0x02, 1
  li   t0, 0x0D
  sw   t0, UART_IER(s0)

  li   t0, 0x1B
  sw   t0, UART_LCR(s0)
  PHASE 1
  WAIT_IIR 0x06, 3
  lw   t2, UART_LSR(s0)
  andi t2, t2, 0x04
  CHECK t2, 0x04, 4
  lw   t2, UART_RBR(s0)

  PHASE 2
  WAIT_DR 5
  lw   t2, UART_LSR(s0)
  andi t2, t2, 0x08
  CHECK t2, 0x08, 6
  lw   t2, UART_RBR(s0)

  li   t0, 0x03
  sw   t0, UART_LCR(s0)
  PHASE 3
  WAIT_DR 7
  lw   t2, UART_LSR(s0)
  andi t2, t2, 0x10
  CHECK t2, 0x10, 8
  DELAY 1500
  UART_DRAIN
  lw   t2, UART_LSR(s0)

  li   t0, 0x07
  sw   t0, UART_FCR(s0)
  PHASE 4
  DELAY 6000
  lw   t2, UART_LSR(s0)
  andi t2, t2, 0x02
  CHECK t2, 0x02, 9
  li   t0, 0x07
  sw   t0, UART_FCR(s0)
  lw   t2, UART_LSR(s0)
  UART_DRAIN

  li   t0, 0x47
  sw   t0, UART_FCR(s0)
  li   t0, 0x01
  sw   t0, UART_IER(s0)
  PHASE 5
  WAIT_IIR 0x04, 10
  UART_DRAIN

  PHASE 6
  WAIT_IIR 0x0C, 11
  UART_DRAIN
  lw   t2, UART_IIR(s0)
  andi t2, t2, 0x0F
  CHECK t2, 0x01, 12

  li   t0, 0x08
  sw   t0, UART_IER(s0)
  li   t0, 0x1F
  sw   t0, UART_MCR(s0)
  DELAY 20
  lw   t2, UART_IIR(s0)
  andi t2, t2, 0x0F
  CHECK t2, 0x00, 13
  lw   t2, UART_MSR(s0)
  andi t2, t2, 0xF0
  CHECK t2, 0xF0, 14
  sw   zero, UART_IER(s0)
  li   t0, 0x07
  sw   t0, UART_FCR(s0)
  li   t0, 0xA5
  sw   t0, UART_THR(s0)
  WAIT_DR 15
  lw   t2, UART_RBR(s0)
  andi t2, t2, 0xFF
  CHECK t2, 0xA5, 16
  sw   zero, UART_MCR(s0)

  sw   zero, UART_FCR(s0)
  UART_DRAIN
  lw   t2, UART_LSR(s0)
  PHASE 7
  WAIT_DR 17
  lw   t2, UART_LSR(s0)
  andi t2, t2, 0x1E
  CHECK t2, 0, 18
  lw   t2, UART_RBR(s0)
  andi t2, t2, 0xFF
  CHECK t2, 0x4B, 19
  PASS
