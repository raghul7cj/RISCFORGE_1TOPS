.equ I2C_BASE,    0x40000000
.equ TIMER_BASE,  0x40001000
.equ UART_BASE,   0x40002000
.equ GPIO_BASE,   0x40003000
.equ SPI_BASE,    0x40004000
.equ DSRAM_BASE,  0x00020000
.equ TOHOST,      0x00020000

.equ UART_RBR,    0x00
.equ UART_THR,    0x00
.equ UART_DLL,    0x00
.equ UART_DLM,    0x04
.equ UART_FCR,    0x08
.equ UART_LCR,    0x0C
.equ UART_LSR,    0x14
.equ UART_SCR,    0x1C

.equ TIMER_VAL,   0x00
.equ TIMER_CTRL,  0x04
.equ TIMER_CMP,   0x08

.equ GPIO_MODE0,  0x008
.equ GPIO_MODE1,  0x00C
.equ GPIO_EN,     0x080
.equ GPIO_IN,     0x100
.equ GPIO_OUT,    0x180

.equ SPI_STATUS,  0x00
.equ SPI_CLKDIV,  0x04
.equ SPI_LEN,     0x10
.equ SPI_TXFIFO,  0x18
.equ SPI_RXFIFO,  0x20
.equ SPI_CMD_RD,  0x201
.equ SPI_CMD_WR,  0x202

.equ I2C_PRE,     0x00
.equ I2C_CTRL,    0x04
.equ I2C_RX,      0x08
.equ I2C_STATUS,  0x0C
.equ I2C_TX,      0x10
.equ I2C_CMD,     0x14
.equ I2C_STA,     0x80
.equ I2C_STO,     0x40
.equ I2C_RD,      0x20
.equ I2C_WR,      0x10
.equ I2C_NACK,    0x08

.macro UART_INIT
  li   s0, UART_BASE
  li   t0, 0x83
  sw   t0, UART_LCR(s0)
  li   t0, 2
  sw   t0, UART_DLL(s0)
  sw   zero, UART_DLM(s0)
  li   t0, 0x03
  sw   t0, UART_LCR(s0)
  li   t0, 0x07
  sw   t0, UART_FCR(s0)
.endm

.macro UART_INIT_NOFIFO
  li   s0, UART_BASE
  li   t0, 0x83
  sw   t0, UART_LCR(s0)
  li   t0, 2
  sw   t0, UART_DLL(s0)
  sw   zero, UART_DLM(s0)
  li   t0, 0x03
  sw   t0, UART_LCR(s0)
  sw   zero, UART_FCR(s0)
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

.macro DELAY n
  li   t0, \n
1:
  addi t0, t0, -1
  bnez t0, 1b
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

.macro CHECK reg, val, code
  li   t6, \val
  beq  \reg, t6, 2f
  FAIL \code
2:
.endm
