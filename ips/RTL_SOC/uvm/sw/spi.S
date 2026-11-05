#include "common.h"

.macro SPI_WAIT
  DELAY 5
1:
  lw   t0, SPI_STATUS(s1)
  andi t0, t0, 1
  beqz t0, 1b
.endm

.section .text.init
.globl _start
_start:
  li   s1, SPI_BASE
  li   t0, 2
  sw   t0, SPI_CLKDIV(s1)
  li   t0, 0x00200000
  sw   t0, SPI_LEN(s1)
  li   t0, 0xDEADBEEF
  sw   t0, SPI_TXFIFO(s1)
  li   t0, SPI_CMD_WR
  sw   t0, SPI_STATUS(s1)
  SPI_WAIT
  li   t0, SPI_CMD_RD
  sw   t0, SPI_STATUS(s1)
  SPI_WAIT
  lw   t1, SPI_RXFIFO(s1)
  CHECK t1, 0xCAFEF00D, 1
  PASS
