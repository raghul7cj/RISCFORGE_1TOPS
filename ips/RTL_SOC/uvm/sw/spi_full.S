#include "common.h"

.section .text.init
.globl _start
_start:
  li   s1, SPI_BASE
  li   t0, 1
  sw   t0, SPI_CLKDIV(s1)

  li   t0, 0x9F000000
  sw   t0, SPI_CMD(s1)
  li   t0, 0x12345600
  sw   t0, SPI_ADR(s1)
  li   t0, (32 << 16) | (24 << 8) | 8
  sw   t0, SPI_LEN(s1)
  sw   zero, SPI_DUM(s1)
  li   t0, 0xA5A5A5A5
  sw   t0, SPI_TXFIFO(s1)
  li   t0, SPI_CMD_WR
  sw   t0, SPI_STATUS(s1)
  SPI_WAIT_IDLE

  li   t0, 0x0B000000
  sw   t0, SPI_CMD(s1)
  li   t0, (16 << 16) | (24 << 8) | 8
  sw   t0, SPI_LEN(s1)
  li   t0, 8
  sw   t0, SPI_DUM(s1)
  li   t0, SPI_CMD_RD
  sw   t0, SPI_STATUS(s1)
  SPI_WAIT_IDLE
  lw   s2, SPI_RXFIFO(s1)

  sw   zero, SPI_DUM(s1)
  li   t0, (8 << 16)
  sw   t0, SPI_LEN(s1)
  sw   zero, SPI_CMD(s1)
  li   t0, 0x5A000000
  sw   t0, SPI_TXFIFO(s1)
  li   t0, SPI_CMD_WR
  sw   t0, SPI_STATUS(s1)
  SPI_WAIT_IDLE

  li   t0, 3
  sw   t0, SPI_CLKDIV(s1)
  li   t0, (32 << 16)
  sw   t0, SPI_LEN(s1)
  li   t0, SPI_CMD_RD
  sw   t0, SPI_STATUS(s1)
  SPI_WAIT_IDLE
  lw   s3, SPI_RXFIFO(s1)
  CHECK s3, 0xCAFEF00D, 2
  PASS
