#include "common.h"

.macro I2C_CMD val
  li   t0, \val
  sw   t0, I2C_CMD(s1)
  I2C_WAIT_TIP
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
  li   t0, 0x80
  sw   t0, I2C_CTRL(s1)
  lw   t1, I2C_CTRL(s1)
  andi t1, t1, 0xFF
  CHECK t1, 0x80, 1
  li   t0, 0x5C
  sw   t0, I2C_TX(s1)
  lw   t1, I2C_TX(s1)
  andi t1, t1, 0xFF
  CHECK t1, 0x5C, 2

  li   t0, (0x50 << 1)
  sw   t0, I2C_TX(s1)
  I2C_CMD I2C_STA | I2C_WR
  EXPECT_ACK 3
  li   t0, 0x10
  sw   t0, I2C_TX(s1)
  I2C_CMD I2C_WR
  EXPECT_ACK 4
  li   t0, (0x50 << 1) | 1
  sw   t0, I2C_TX(s1)
  I2C_CMD I2C_STA | I2C_WR
  EXPECT_ACK 5
  I2C_CMD I2C_STO | I2C_RD | I2C_NACK
  lw   t1, I2C_RX(s1)
  andi t1, t1, 0xFF
  CHECK t1, 0x96, 6
  lw   t1, I2C_STATUS(s1)
  andi t1, t1, 0x40
  DELAY 200
  lw   t1, I2C_STATUS(s1)
  andi t1, t1, 0x40
  CHECK t1, 0, 7
  PASS
