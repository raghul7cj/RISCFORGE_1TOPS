#include "common.h"

.section .text.init
.globl _start
_start:
  li   s1, SPI_BASE
  li   t1, 5
  sw   t1, SPI_CLKDIV(s1)
  lw   t2, SPI_CLKDIV(s1)
  andi t2, t2, 0xFF
  CHECK t2, 5, 1
  li   t1, 0xA1B2C3D4
  sw   t1, SPI_CMD(s1)
  lw   t2, SPI_CMD(s1)
  CHECK t2, 0xA1B2C3D4, 2
  li   t1, 0x11223344
  sw   t1, SPI_ADR(s1)
  lw   t2, SPI_ADR(s1)
  CHECK t2, 0x11223344, 3
  li   t1, (16 << 16) | (24 << 8) | 8
  sw   t1, SPI_LEN(s1)
  lw   t2, SPI_LEN(s1)
  CHECK t2, (16 << 16) | (24 << 8) | 8, 4
  li   t1, 0x00050003
  sw   t1, SPI_DUM(s1)
  lw   t2, SPI_DUM(s1)
  CHECK t2, 0x00050003, 5
  li   t1, 0x01020304
  sw   t1, SPI_INTCFG(s1)
  lw   t2, SPI_INTCFG(s1)
  li   t1, 0x1F1F1F1F
  and  t2, t2, t1
  CHECK t2, 0x01020304, 6

  sw   zero, SPI_INTCFG(s1)
  sw   zero, SPI_CMD(s1)
  sw   zero, SPI_DUM(s1)
  li   t1, (32 << 16)
  sw   t1, SPI_LEN(s1)
  li   t1, 0x11111111
  sw   t1, SPI_TXFIFO(s1)
  li   t1, 0x22222222
  sw   t1, SPI_TXFIFO(s1)
  lw   t2, SPI_STATUS(s1)
  srli t2, t2, 24
  andi t2, t2, 0x1F
  CHECK t2, 2, 7
  li   t1, 0x10
  sw   t1, SPI_STATUS(s1)
  DELAY 10
  lw   t2, SPI_STATUS(s1)
  srli t2, t2, 24
  andi t2, t2, 0x1F
  CHECK t2, 0, 8

  sw   zero, SPI_CLKDIV(s1)
  li   t1, 0x13579BDF
  sw   t1, SPI_TXFIFO(s1)
  li   t1, SPI_CMD_WR
  sw   t1, SPI_STATUS(s1)
  SPI_WAIT_IDLE

  li   t1, 2
  sw   t1, SPI_CLKDIV(s1)
  li   t1, 0x80000100
  sw   t1, SPI_INTCFG(s1)
  li   t1, SPI_CMD_RD
  sw   t1, SPI_STATUS(s1)
  SPI_WAIT_IDLE
  DELAY 10
  lw   t2, SPI_INTSTA(s1)
  lw   t2, SPI_RXFIFO(s1)
  CHECK t2, 0xCAFEF00D, 10
  sw   zero, SPI_INTCFG(s1)

  li   t1, 0xF0F0F0F0
  sw   t1, SPI_TXFIFO(s1)
  li   t1, 0x208
  sw   t1, SPI_STATUS(s1)
  SPI_WAIT_IDLE
  li   t1, 0x204
  sw   t1, SPI_STATUS(s1)
  SPI_WAIT_IDLE
  lw   t2, SPI_RXFIFO(s1)

  li   t1, 2
  sw   t1, SPI_CLKDIV(s1)
  li   t1, SPI_CMD_RD
  sw   t1, SPI_STATUS(s1)
  SPI_WAIT_IDLE
  lw   t2, SPI_RXFIFO(s1)
  CHECK t2, 0xCAFEF00D, 9
  PASS
