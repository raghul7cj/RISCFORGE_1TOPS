#include "common.h"

.macro MODE n, lcr, div, tx0, tx1, rx, mask
  li   t0, 0x80 | \lcr
  sw   t0, UART_LCR(s0)
  li   t0, \div
  sw   t0, UART_DLL(s0)
  sw   zero, UART_DLM(s0)
  li   t0, \lcr
  sw   t0, UART_LCR(s0)
  li   t0, 0x07
  sw   t0, UART_FCR(s0)
  PHASE \n
  DELAY 100
  li   t0, \tx0
  sw   t0, UART_THR(s0)
  li   t0, \tx1
  sw   t0, UART_THR(s0)
  UART_FLUSH
  WAIT_DR (\n * 10 + 1)
  lw   t2, UART_LSR(s0)
  andi t2, t2, 0x1E
  CHECK t2, 0, (\n * 10 + 2)
  lw   t2, UART_RBR(s0)
  andi t2, t2, \mask
  CHECK t2, \rx, (\n * 10 + 3)
.endm

.section .text.init
.globl _start
_start:
  li   s0, UART_BASE
  MODE 1, 0x03, 2, 0x41, 0x42, 0x5A, 0xFF
  MODE 2, 0x1A, 2, 0x63, 0x64, 0x35, 0x7F
  MODE 3, 0x0D, 2, 0x2A, 0x15, 0x1C, 0x3F
  MODE 4, 0x00, 2, 0x11, 0x0E, 0x09, 0x1F
  MODE 5, 0x2B, 3, 0x4D, 0x4E, 0xA3, 0xFF
  MODE 6, 0x3F, 2, 0x53, 0x54, 0x6B, 0xFF
  PASS
