.equ UART_BASE, 0x40002000
.equ UART_RBR,  0x00
.equ UART_THR,  0x00
.equ UART_DLL,  0x00
.equ UART_DLM,  0x04
.equ UART_LCR,  0x0C
.equ UART_LSR,  0x14
.equ TOHOST,    0x00010FFC

.macro UART_INIT
  li   s0, UART_BASE
  li   t0, 0x83
  sw   t0, UART_LCR(s0)
  li   t0, 1
  sw   t0, UART_DLL(s0)
  sw   zero, UART_DLM(s0)
  li   t0, 0x03
  sw   t0, UART_LCR(s0)
.endm

.macro PUTC reg
1:
  lw   t0, UART_LSR(s0)
  andi t0, t0, 0x20
  beqz t0, 1b
  sw   \reg, UART_THR(s0)
.endm

.macro GETC reg
1:
  lw   t0, UART_LSR(s0)
  andi t0, t0, 0x01
  beqz t0, 1b
  lw   \reg, UART_RBR(s0)
  andi \reg, \reg, 0xFF
.endm

.macro UART_FLUSH
1:
  lw   t0, UART_LSR(s0)
  andi t0, t0, 0x40
  beqz t0, 1b
.endm

.macro PASS
  li   t0, TOHOST
  li   t1, 1
  sw   t1, 0(t0)
1:
  j    1b
.endm

.macro FAIL code
  li   t0, TOHOST
  li   t1, (\code << 1) | 1
  sw   t1, 0(t0)
1:
  j    1b
.endm
