#include "common.h"

.section .text.init
.globl _start
_start:
  UART_INIT
  li   t0, 0x83
  sw   t0, UART_LCR(s0)
  lw   t2, UART_DLL(s0)
  andi t2, t2, 0xFF
  CHECK t2, 2, 1
  lw   t2, UART_DLM(s0)
  andi t2, t2, 0xFF
  CHECK t2, 0, 2
  li   t0, 0x07
  sw   t0, UART_FCR(s0)
  li   t0, 0x01
  sw   t0, UART_MCR(s0)
  sw   t0, UART_SCR(s0)
  lw   t2, UART_IIR(s0)
  lw   t2, UART_LSR(s0)
  lw   t2, UART_MSR(s0)
  lw   t2, UART_SCR(s0)
  lw   t2, UART_MCR(s0)
  lw   t2, UART_LCR(s0)
  andi t2, t2, 0xFF
  CHECK t2, 0x83, 3
  sw   zero, UART_MCR(s0)

  li   t0, 0x04
  sw   t0, UART_LCR(s0)
  PHASE 1
  DELAY 50
  li   t0, 0x15
  sw   t0, UART_THR(s0)
  li   t0, 0x0A
  sw   t0, UART_THR(s0)
  UART_FLUSH

  li   t0, 0x03
  sw   t0, UART_LCR(s0)
  li   t0, 0x87
  sw   t0, UART_FCR(s0)
  li   t0, 0x01
  sw   t0, UART_IER(s0)
  PHASE 2
  WAIT_IIR 0x04, 4
  UART_DRAIN

  li   t0, 0xC7
  sw   t0, UART_FCR(s0)
  PHASE 3
  WAIT_IIR 0x04, 5
  UART_DRAIN
  sw   zero, UART_IER(s0)

  li   t0, 0x07
  sw   t0, UART_FCR(s0)
  li   t0, 0x1B
  sw   t0, UART_LCR(s0)
  PHASE 4
  DELAY 3000
  lw   t2, UART_LSR(s0)
  andi t2, t2, 0x84
  CHECK t2, 0x84, 6
  lw   t2, UART_RBR(s0)
  lw   t2, UART_LSR(s0)
  lw   t2, UART_RBR(s0)
  lw   t2, UART_LSR(s0)
  lw   t2, UART_RBR(s0)
  DELAY 50
  lw   t2, UART_LSR(s0)
  andi t2, t2, 0x81
  CHECK t2, 0, 7

  li   t0, 0x03
  sw   t0, UART_LCR(s0)
  PHASE 5
  DELAY 3000
  UART_DRAIN
  lw   t2, UART_LSR(s0)

  sw   zero, UART_FCR(s0)
  PHASE 6
  DELAY 3000
  lw   t2, UART_LSR(s0)
  andi t2, t2, 0x02
  CHECK t2, 0x02, 8
  lw   t2, UART_RBR(s0)
  lw   t2, UART_LSR(s0)
  PASS
