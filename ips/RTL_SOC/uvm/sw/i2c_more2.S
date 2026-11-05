#include "common.h"

.macro I2C_CMD val
  li   t0, \val
  sw   t0, I2C_CMD(s1)
  I2C_WAIT_TIP
.endm

.section .text.init
.globl _start
_start:
  li   s1, I2C_BASE
  li   t0, 4
  sw   t0, I2C_PRE(s1)
  sw   zero, I2C_CTRL(s1)
  li   t0, I2C_STA | I2C_WR
  sw   t0, I2C_CMD(s1)
  lw   t1, I2C_CMD(s1)
  andi t1, t1, 0xF0
  CHECK t1, 0, 1
  li   t0, 0xC0
  sw   t0, I2C_CTRL(s1)

  I2C_CMD I2C_STA | I2C_RD
  lw   t1, I2C_RX(s1)
  andi t1, t1, 0xFF
  CHECK t1, 0xFF, 2
  I2C_CMD I2C_STO
  I2C_CMD I2C_IACK

  PHASE 1
  DELAY 50
  li   t0, (0x50 << 1)
  sw   t0, I2C_TX(s1)
  li   t0, I2C_STA | I2C_WR
  sw   t0, I2C_CMD(s1)
  li   a7, 20000
al_wait:
  lw   t1, I2C_STATUS(s1)
  andi t1, t1, 0x20
  bnez t1, al_seen
  addi a7, a7, -1
  bnez a7, al_wait
  FAIL 3
al_seen:
  lw   t1, I2C_STATUS(s1)
  andi t1, t1, 0x01
  CHECK t1, 1, 4
  I2C_CMD I2C_IACK
  li   a7, 20000
busy_wait:
  lw   t1, I2C_STATUS(s1)
  andi t1, t1, 0x40
  beqz t1, bus_free
  addi a7, a7, -1
  bnez a7, busy_wait
  FAIL 5
bus_free:
  li   t0, (0x50 << 1)
  sw   t0, I2C_TX(s1)
  I2C_CMD I2C_STA | I2C_WR
  lw   t1, I2C_STATUS(s1)
  andi t1, t1, 0x80
  CHECK t1, 0, 6
  li   t0, 0x42
  sw   t0, I2C_TX(s1)
  I2C_CMD I2C_STO | I2C_WR
  lw   t1, I2C_STATUS(s1)
  andi t1, t1, 0x80
  CHECK t1, 0, 7
  sw   zero, I2C_CTRL(s1)
  PASS
