#include "common.h"

.section .text.init
.globl _start
_start:
  li   s1, SPI_BASE
  li   t0, 2
  sw   t0, SPI_CLKDIV(s1)

  li   t0, 0xABCD0000
  sw   t0, SPI_ADR(s1)
  li   t0, (32 << 16) | (16 << 8)
  sw   t0, SPI_LEN(s1)
  li   t0, 0x5555AAAA
  sw   t0, SPI_TXFIFO(s1)
  li   t0, SPI_CMD_WR
  sw   t0, SPI_STATUS(s1)
  SPI_WAIT_IDLE

  li   t0, (32 << 16)
  sw   t0, SPI_LEN(s1)
  li   t0, 4
  sw   t0, SPI_DUM(s1)
  li   t0, SPI_CMD_RD
  sw   t0, SPI_STATUS(s1)
  SPI_WAIT_IDLE
  lw   t2, SPI_RXFIFO(s1)
  li   t0, 4 << 16
  sw   t0, SPI_DUM(s1)
  li   t0, 0x0F0F0F0F
  sw   t0, SPI_TXFIFO(s1)
  li   t0, SPI_CMD_WR
  sw   t0, SPI_STATUS(s1)
  SPI_WAIT_IDLE
  sw   zero, SPI_DUM(s1)

  li   t0, 0xC1010000
  sw   t0, SPI_INTCFG(s1)
  li   t0, 0x11111111
  sw   t0, SPI_TXFIFO(s1)
  li   t0, SPI_CMD_WR
  sw   t0, SPI_STATUS(s1)
  SPI_WAIT_IDLE
  li   t0, SPI_CMD_RD
  sw   t0, SPI_STATUS(s1)
  SPI_WAIT_IDLE
  lw   t2, SPI_INTSTA(s1)
  lw   t2, SPI_RXFIFO(s1)
  sw   zero, SPI_INTCFG(s1)

  li   t0, (384 << 16)
  sw   t0, SPI_LEN(s1)
  li   t0, SPI_CMD_RD
  sw   t0, SPI_STATUS(s1)
  DELAY 4000
  li   s2, 12
rx_loop:
  lw   t2, SPI_RXFIFO(s1)
  CHECK t2, 0xCAFEF00D, 2
  addi s2, s2, -1
  bnez s2, rx_loop
  SPI_WAIT_IDLE

  li   t0, 0x12340000
  sw   t0, SPI_ADR(s1)
  li   t0, (32 << 16) | (16 << 8)
  sw   t0, SPI_LEN(s1)
  li   t0, 4
  sw   t0, SPI_DUM(s1)
  li   t0, SPI_CMD_RD
  sw   t0, SPI_STATUS(s1)
  SPI_WAIT_IDLE
  lw   t2, SPI_RXFIFO(s1)
  sw   zero, SPI_DUM(s1)

  li   t0, (64 << 16)
  sw   t0, SPI_LEN(s1)
  li   t0, 0xA1A2A3A4
  sw   t0, SPI_TXFIFO(s1)
  li   t0, SPI_CMD_WR
  sw   t0, SPI_STATUS(s1)
  DELAY 300
  li   t0, 0xB1B2B3B4
  sw   t0, SPI_TXFIFO(s1)
  SPI_WAIT_IDLE
  PASS
