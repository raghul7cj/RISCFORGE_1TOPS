#include "common.h"

.macro I2C_CMD val
  li   t0, \val
  sw   t0, I2C_CMD(s1)
  I2C_WAIT_TIP
.endm

.macro I2C_TX val
  li   t0, \val
  sw   t0, I2C_TX(s1)
.endm

.macro EXPECT_ACK code
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
  lw   t1, I2C_PRE(s1)
  CHECK t1, 4, 1
  li   t0, 0xC0
  sw   t0, I2C_CTRL(s1)

  I2C_TX (0x50 << 1)
  I2C_CMD I2C_STA | I2C_WR
  EXPECT_ACK 2
  lw   t1, I2C_STATUS(s1)
  andi t1, t1, 1
  CHECK t1, 1, 3
  I2C_CMD I2C_IACK
  lw   t1, I2C_STATUS(s1)
  andi t1, t1, 1
  CHECK t1, 0, 4

  I2C_TX 0x11
  I2C_CMD I2C_WR
  EXPECT_ACK 5
  I2C_TX 0x22
  I2C_CMD I2C_WR
  EXPECT_ACK 6
  I2C_TX 0x33
  I2C_CMD I2C_STO | I2C_WR
  EXPECT_ACK 7

  I2C_TX (0x50 << 1) | 1
  I2C_CMD I2C_STA | I2C_WR
  EXPECT_ACK 8
  I2C_CMD I2C_RD
  lw   t1, I2C_RX(s1)
  andi t1, t1, 0xFF
  CHECK t1, 0x96, 9
  I2C_CMD I2C_RD
  lw   t1, I2C_RX(s1)
  andi t1, t1, 0xFF
  CHECK t1, 0x96, 10
  I2C_CMD I2C_STO | I2C_RD | I2C_NACK
  lw   t1, I2C_RX(s1)
  andi t1, t1, 0xFF
  CHECK t1, 0x96, 11

  I2C_TX (0x51 << 1)
  I2C_CMD I2C_STA | I2C_WR
  lw   t1, I2C_STATUS(s1)
  andi t1, t1, 0x80
  CHECK t1, 0x80, 12
  I2C_CMD I2C_STO
  I2C_CMD I2C_IACK
  sw   zero, I2C_CTRL(s1)
  PASS
