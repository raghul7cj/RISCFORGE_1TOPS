#include "common.h"

.macro I2C_WAIT
1:
  lw   t0, I2C_STATUS(s1)
  andi t0, t0, 2
  bnez t0, 1b
.endm

.macro I2C_ACK code
  lw   t1, I2C_STATUS(s1)
  andi t1, t1, 0x80
  CHECK t1, 0, \code
.endm

.section .text.init
.globl _start
_start:
  li   s1, I2C_BASE
  li   t0, 4
  sw   t0, I2C_PRE(s1)
  li   t0, 0x80
  sw   t0, I2C_CTRL(s1)

  li   t0, (0x50 << 1)
  sw   t0, I2C_TX(s1)
  li   t0, I2C_STA | I2C_WR
  sw   t0, I2C_CMD(s1)
  I2C_WAIT
  I2C_ACK 1

  li   t0, 0x3C
  sw   t0, I2C_TX(s1)
  li   t0, I2C_STO | I2C_WR
  sw   t0, I2C_CMD(s1)
  I2C_WAIT
  I2C_ACK 2

  li   t0, (0x50 << 1) | 1
  sw   t0, I2C_TX(s1)
  li   t0, I2C_STA | I2C_WR
  sw   t0, I2C_CMD(s1)
  I2C_WAIT
  I2C_ACK 3

  li   t0, I2C_STO | I2C_RD | I2C_NACK
  sw   t0, I2C_CMD(s1)
  I2C_WAIT
  lw   t1, I2C_RX(s1)
  andi t1, t1, 0xFF
  CHECK t1, 0x96, 4
  PASS
