#include "common.h"

.section .text.init
.globl _start
_start:
  la   t0, handler
  csrw mtvec, t0
  li   s2, 0
  li   s3, 0
  li   s4, 0
  li   s8, 0

  li   s1, TIMER_BASE
  sw   zero, TIMER_CTRL(s1)
  sw   zero, TIMER_VAL(s1)
  li   t0, 200
  sw   t0, TIMER_CMP(s1)
  li   t0, 0x80
  csrs mie, t0
  csrsi mstatus, 8
  li   t0, 1
  sw   t0, TIMER_CTRL(s1)
  WAIT_NZ s2, 5000, 1

  li   s9, TIMER1_BASE
  sw   zero, TIMER_CTRL(s9)
  sw   zero, TIMER_VAL(s9)
  li   t0, 150
  sw   t0, TIMER_CMP(s9)
  li   t0, 0x1000000
  csrs mie, t0
  li   t0, 1
  sw   t0, TIMER_CTRL(s9)
  WAIT_NZ s8, 5000, 2

  li   s1, GPIO_BASE
  li   t0, 1
  sw   t0, GPIO_CFG(s1)
  li   t0, -1
  sw   t0, GPIO_EN(s1)
  li   t0, 0x10000
  sw   t0, GPIO_RISE_EN(s1)
  li   t0, 0x10000
  csrs mie, t0
  PHASE 1
  WAIT_NZ s3, 20000, 3

  UART_INIT
  li   t0, 1
  sw   t0, UART_IER(s0)
  li   t0, 0x80000
  csrs mie, t0
  PHASE 2
  WAIT_NZ s4, 50000, 4
  CHECK s6, 0x5A, 5

  csrci mstatus, 8
  PASS

.align 2
handler:
  csrr t0, mcause
  li   t1, 0x80000007
  beq  t0, t1, h_timer0
  li   t1, 0x80000018
  beq  t0, t1, h_timer1
  li   t1, 0x80000010
  beq  t0, t1, h_gpio
  li   t1, 0x80000013
  beq  t0, t1, h_uart
  FAIL 9
h_timer0:
  addi s2, s2, 1
  li   t1, TIMER_BASE
  sw   zero, TIMER_CTRL(t1)
  mret
h_timer1:
  addi s8, s8, 1
  li   t1, TIMER1_BASE
  sw   zero, TIMER_CTRL(t1)
  mret
h_gpio:
  addi s3, s3, 1
  li   t1, GPIO_BASE
  li   t0, 0x10000
  sw   t0, GPIO_RISE_STS(t1)
  sw   t0, GPIO_INT_STS(t1)
  mret
h_uart:
  addi s4, s4, 1
  li   t1, UART_BASE
  lw   s6, UART_RBR(t1)
  andi s6, s6, 0xFF
  mret
