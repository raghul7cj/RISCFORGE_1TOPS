#include "common.h"

.macro RO base, off, val, code
  lw   t2, \off(\base)
  CHECK t2, \val, \code
.endm

.macro WRCHK base, off, pat, rst, mask, safe, code
  li   t1, (\pat & \safe)
  sw   t1, \off(\base)
  lw   t2, \off(\base)
  CHECK t2, ((\pat & \safe & \mask) | (\rst & ~\mask)), \code
.endm

.macro RW base, off, rst, mask, safe, code
  RO    \base, \off, \rst, \code
  WRCHK \base, \off, 0xFFFFFFFF, \rst, \mask, \safe, \code
  WRCHK \base, \off, 0x00000000, \rst, \mask, \safe, \code
  WRCHK \base, \off, 0xA5A5A5A5, \rst, \mask, \safe, \code
  WRCHK \base, \off, 0x5A5A5A5A, \rst, \mask, \safe, \code
  li   t1, (\rst & \mask)
  sw   t1, \off(\base)
.endm

.section .text.init
.globl _start
_start:
  li   s1, GPIO_BASE
  RO   s1, GPIO_INFO,     0x00000820, 1
  RO   s1, GPIO_INT_STS,  0, 2
  RO   s1, GPIO_RISE_STS, 0, 3
  RO   s1, GPIO_FALL_STS, 0, 4
  RO   s1, GPIO_LVLH_STS, 0, 5
  RO   s1, GPIO_LVLL_STS, 0, 6
  RW   s1, GPIO_CFG,      0, 0x00000003, 0xFFFFFFFF, 7
  RW   s1, GPIO_MODE0,    0, 0xFFFFFFFF, 0xFFFFFFFF, 8
  RW   s1, GPIO_MODE1,    0, 0xFFFFFFFF, 0xFFFFFFFF, 9
  RW   s1, GPIO_EN,       0, 0xFFFFFFFF, 0xFFFFFFFF, 10
  RW   s1, GPIO_OUT,      0, 0xFFFFFFFF, 0xFFFFFFFF, 11
  RW   s1, GPIO_RISE_EN,  0, 0xFFFFFFFF, 0xFFFFFFFF, 12
  RW   s1, GPIO_FALL_EN,  0, 0xFFFFFFFF, 0xFFFFFFFF, 13
  RW   s1, GPIO_LVLH_EN,  0, 0xFFFFFFFF, 0xFFFFFFFF, 14
  RW   s1, GPIO_LVLL_EN,  0, 0xFFFFFFFF, 0xFFFFFFFF, 15

  li   s1, UART_BASE
  RO   s1, UART_LSR,      0x60, 20
  RO   s1, UART_IIR,      0x01, 21
  RW   s1, UART_IER,      0, 0x0F, 0xFFFFFFFF, 22
  RW   s1, UART_LCR,      0, 0xFF, 0x7F, 23
  RW   s1, UART_MCR,      0, 0x1F, 0xFFFFFFFF, 24
  li   t1, 0x80
  sw   t1, UART_LCR(s1)
  RW   s1, UART_DLL,      0x01, 0xFF, 0xFFFFFFFF, 25
  RW   s1, UART_DLM,      0x00, 0xFF, 0xFFFFFFFF, 26
  RO   s1, UART_LCR,      0x80, 27
  sw   zero, UART_LCR(s1)

  li   s1, SPI_BASE
  RO   s1, 0x00,          0x00000001, 30
  RW   s1, 0x04,          0, 0x000000FF, 0xFFFFFFFF, 31
  RW   s1, 0x08,          0, 0xFFFFFFFF, 0xFFFFFFFF, 32
  RW   s1, 0x0C,          0, 0xFFFFFFFF, 0xFFFFFFFF, 33
  RW   s1, 0x10,          0, 0xFFFF3F3F, 0xFFFFFFFF, 34
  RW   s1, 0x14,          0, 0xFFFFFFFF, 0xFFFFFFFF, 35
  RW   s1, 0x24,          0, 0xDF1F1F1F, 0x3FFFFFFF, 36

  li   s1, I2C_BASE
  RO   s1, 0x08,          0, 40
  RO   s1, 0x0C,          0, 41
  RW   s1, 0x00,          0, 0x0000FFFF, 0xFFFFFFFF, 42
  RW   s1, 0x04,          0, 0x000000FF, 0xFFFFFFFF, 43
  RW   s1, 0x10,          0, 0x000000FF, 0xFFFFFFFF, 44

  li   s1, TIMER_BASE
  RW   s1, 0x04,          0, 0xFFFFFFFF, 0xFFFFFFFE, 50
  RW   s1, 0x08,          0, 0xFFFFFFFF, 0xFFFFFFFF, 51
  RW   s1, 0x00,          0, 0xFFFFFFFF, 0xFFFFFFFF, 52
  RW   s1, 0x14,          0, 0xFFFFFFFF, 0xFFFFFFFE, 53
  RW   s1, 0x18,          0, 0xFFFFFFFF, 0xFFFFFFFF, 54
  RW   s1, 0x10,          0, 0xFFFFFFFF, 0xFFFFFFFF, 55

  li   s1, TIMER1_BASE
  RW   s1, 0x04,          0, 0xFFFFFFFF, 0xFFFFFFFE, 60
  RW   s1, 0x08,          0, 0xFFFFFFFF, 0xFFFFFFFF, 61
  RW   s1, 0x00,          0, 0xFFFFFFFF, 0xFFFFFFFF, 62
  RW   s1, 0x14,          0, 0xFFFFFFFF, 0xFFFFFFFE, 63
  RW   s1, 0x18,          0, 0xFFFFFFFF, 0xFFFFFFFF, 64
  RW   s1, 0x10,          0, 0xFFFFFFFF, 0xFFFFFFFF, 65

  li   s1, GPIO_BASE
  li   t1, -1
  sw   zero, GPIO_SET(s1)
  sw   t1, GPIO_SET(s1)
  sw   zero, GPIO_TOGGLE(s1)
  sw   t1, GPIO_TOGGLE(s1)
  sw   zero, GPIO_CLEAR(s1)
  sw   t1, GPIO_CLEAR(s1)
  RO   s1, GPIO_OUT,      0, 70

  li   s1, SPI_BASE
  li   t1, 0x00000F00
  sw   t1, 0x00(s1)
  sw   zero, 0x00(s1)
  li   t1, -1
  sw   zero, 0x18(s1)
  sw   t1, 0x18(s1)
  li   t1, 0x10
  sw   t1, 0x00(s1)
  RO   s1, 0x00,          0x00000001, 71
  li   t0, 2
  sw   t0, SPI_CLKDIV(s1)
  li   t0, 0x00100000
  sw   t0, SPI_LEN(s1)
  li   t0, 0xBEEF0000
  sw   t0, SPI_TXFIFO(s1)
  li   t0, SPI_CMD_WR
  sw   t0, SPI_STATUS(s1)
  SPI_WAIT_IDLE

  UART_INIT
  sw   zero, UART_THR(s0)
  li   t1, 0xFF
  sw   t1, UART_THR(s0)
  UART_FLUSH
  PASS
