#include "common.h"

.equ CH1, 0x10

.macro WAIT_BIT bit, code
  li   a7, 20000
1:
  li   t0, 1 << (\bit)
  and  t0, s10, t0
  bnez t0, 2f
  addi a7, a7, -1
  bnez a7, 1b
  FAIL \code
2:
.endm

.macro ENABLE bit
  li   t0, 1 << (\bit)
  csrs mie, t0
.endm

.section .text.init
.globl _start
_start:
  la   t0, handler
  csrw mtvec, t0
  li   s10, 0
  csrsi mstatus, 8

  ENABLE 3
  csrsi mip, 8
  WAIT_BIT 3, 1

  li   s1, TIMER_BASE
  ENABLE 20
  li   t0, 0xFFFFFFF0
  sw   t0, TIMER_VAL(s1)
  li   t0, 1
  sw   t0, TIMER_CTRL(s1)
  WAIT_BIT 20, 2
  sw   zero, TIMER_CTRL(s1)

  ENABLE 21
  li   t0, 0xFFFFFFF0
  sw   t0, CH1+TIMER_VAL(s1)
  li   t0, 1
  sw   t0, CH1+TIMER_CTRL(s1)
  WAIT_BIT 21, 3
  sw   zero, CH1+TIMER_CTRL(s1)

  ENABLE 22
  sw   zero, CH1+TIMER_VAL(s1)
  li   t0, 40
  sw   t0, CH1+TIMER_CMP(s1)
  li   t0, 1
  sw   t0, CH1+TIMER_CTRL(s1)
  WAIT_BIT 22, 4
  sw   zero, CH1+TIMER_CTRL(s1)

  li   s1, TIMER1_BASE
  ENABLE 23
  li   t0, 0xFFFFFFF0
  sw   t0, TIMER_VAL(s1)
  li   t0, 1
  sw   t0, TIMER_CTRL(s1)
  WAIT_BIT 23, 5
  sw   zero, TIMER_CTRL(s1)

  ENABLE 25
  li   t0, 0xFFFFFFF0
  sw   t0, CH1+TIMER_VAL(s1)
  li   t0, 1
  sw   t0, CH1+TIMER_CTRL(s1)
  WAIT_BIT 25, 6
  sw   zero, CH1+TIMER_CTRL(s1)

  ENABLE 26
  sw   zero, CH1+TIMER_VAL(s1)
  li   t0, 40
  sw   t0, CH1+TIMER_CMP(s1)
  li   t0, 1
  sw   t0, CH1+TIMER_CTRL(s1)
  WAIT_BIT 26, 7
  sw   zero, CH1+TIMER_CTRL(s1)

  li   s1, SPI_BASE
  li   t0, 2
  sw   t0, SPI_CLKDIV(s1)
  li   t0, (32 << 16)
  sw   t0, SPI_LEN(s1)
  ENABLE 27
  li   t0, 0x12345678
  sw   t0, SPI_TXFIFO(s1)
  li   t0, SPI_CMD_WR
  sw   t0, SPI_STATUS(s1)
  WAIT_BIT 27, 8
  SPI_WAIT_IDLE

  ENABLE 18
  li   t0, 0x80000100
  sw   t0, SPI_INTCFG(s1)
  lw   t0, SPI_INTSTA(s1)
  li   t0, SPI_CMD_RD
  sw   t0, SPI_STATUS(s1)
  WAIT_BIT 18, 9
  SPI_WAIT_IDLE
  lw   t0, SPI_INTSTA(s1)
  lw   t0, SPI_RXFIFO(s1)
  sw   zero, SPI_INTCFG(s1)

  li   s1, I2C_BASE
  li   t0, 4
  sw   t0, I2C_PRE(s1)
  li   t0, 0xC0
  sw   t0, I2C_CTRL(s1)
  ENABLE 17
  li   t0, (0x50 << 1)
  sw   t0, I2C_TX(s1)
  li   t0, I2C_STA | I2C_WR | I2C_STO
  sw   t0, I2C_CMD(s1)
  WAIT_BIT 17, 10
  sw   zero, I2C_CTRL(s1)

  csrci mstatus, 8
  csrw mie, zero
  PASS

.align 2
handler:
  csrr t5, mcause
  bgez t5, bad_trap
  andi t5, t5, 31
  li   t6, 1
  sll  t6, t6, t5
  or   s10, s10, t6
  csrc mie, t6
  li   t6, 3
  bne  t5, t6, 1f
  csrci mip, 8
1:
  li   t6, 17
  bne  t5, t6, 2f
  li   t6, I2C_BASE
  li   t4, I2C_IACK
  sw   t4, I2C_CMD(t6)
2:
  mret
bad_trap:
  FAIL 11
