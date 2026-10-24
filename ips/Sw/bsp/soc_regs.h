/* =============================================================================
 * RISCFORGE 1TOPS — SoC Memory Map & Register Definitions Header (soc_regs.h)
 * =============================================================================
 * Auto-generated & verified against RTL: RTL_SOC/riscforge_soc_subsystem.sv
 * Targets: FPGA Prototyping on Digilent Nexys4 DDR (xc7a100tcsg324-1)
 * ============================================================================= */

#ifndef SOC_REGS_H
#define SOC_REGS_H

#include <stdint.h>

#define REG32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))
#define REG8(addr)  (*(volatile uint8_t  *)(uintptr_t)(addr))

/* =============================================================================
 * 1. Global Address Map
 * ============================================================================= */
#define BOOTROM_BASE    0x00000000UL /* 64 Bytes BootROM stub */
#define ISRAM_BASE      0x00010000UL /* 32 KB Instruction SRAM */
#define DSRAM_BASE      0x00020000UL /* 32 KB Data SRAM */

#define APB_BASE        0x40000000UL /* APB Peripheral Window */
#define I2C_BASE        0x40000000UL /* APB[0] I2C Master */
#define TIMER0_BASE     0x40001000UL /* APB[1] APB Timer 0 */
#define UART_BASE       0x40002000UL /* APB[2] 16550-compatible UART */
#define GPIO_BASE       0x40003000UL /* APB[3] 32-bit GPIO Controller */
#define SPI_BASE        0x40004000UL /* APB[4] SPI Master / Bootloader APB */
#define TIMER1_BASE     0x40005000UL /* APB[5] APB Timer 1 */

/* =============================================================================
 * 2. APB[0] I2C Master Registers (4 KB Window)
 * ============================================================================= */
#define I2C_REG_PRE_LO  REG32(I2C_BASE + 0x00) /* Clock Prescaler Low Byte */
#define I2C_REG_PRE_HI  REG32(I2C_BASE + 0x04) /* Clock Prescaler High Byte */
#define I2C_REG_CTR     REG32(I2C_BASE + 0x08) /* Control Register (EN, IEN) */
#define I2C_REG_TXR     REG32(I2C_BASE + 0x0C) /* Transmit Register / Slave Addr (W) */
#define I2C_REG_RXR     REG32(I2C_BASE + 0x0C) /* Receive Register (R) */
#define I2C_REG_CR      REG32(I2C_BASE + 0x10) /* Command Register (STA, STO, RD, WR, ACK, IACK) */
#define I2C_REG_SR      REG32(I2C_BASE + 0x10) /* Status Register (RxACK, BUSY, AL, TIP, IF) */

/* =============================================================================
 * 3. APB[1] & APB[5] APB Timers (Timer 0 & Timer 1, 2 Channels Each)
 * ============================================================================= */
/* Channel 0 */
#define TIMER0_VAL      REG32(TIMER0_BASE + 0x00) /* Current Counter Value */
#define TIMER0_CTRL     REG32(TIMER0_BASE + 0x04) /* Control: [0]=EN, [3:1]=PRESCALER */
#define TIMER0_CMP      REG32(TIMER0_BASE + 0x08) /* Compare Value */

/* Channel 1 */
#define TIMER0_CH1_VAL  REG32(TIMER0_BASE + 0x0C)
#define TIMER0_CH1_CTRL REG32(TIMER0_BASE + 0x10)
#define TIMER0_CH1_CMP  REG32(TIMER0_BASE + 0x14)

/* Timer 1 Channel 0 & Channel 1 */
#define TIMER1_VAL      REG32(TIMER1_BASE + 0x00)
#define TIMER1_CTRL     REG32(TIMER1_BASE + 0x04)
#define TIMER1_CMP      REG32(TIMER1_BASE + 0x08)
#define TIMER1_CH1_VAL  REG32(TIMER1_BASE + 0x0C)
#define TIMER1_CH1_CTRL REG32(TIMER1_BASE + 0x10)
#define TIMER1_CH1_CMP  REG32(TIMER1_BASE + 0x14)

#define TIMER_CTRL_EN   (1UL << 0)

/* =============================================================================
 * 4. APB[2] 16550 UART Registers
 * ============================================================================= */
#define UART_RBR        REG32(UART_BASE + 0x00) /* RX Buffer (DLAB=0, Read) */
#define UART_THR        REG32(UART_BASE + 0x00) /* TX Holding (DLAB=0, Write) */
#define UART_DLL        REG32(UART_BASE + 0x00) /* Baud Divisor LSB (DLAB=1) */
#define UART_IER        REG32(UART_BASE + 0x04) /* Interrupt Enable */
#define UART_DLM        REG32(UART_BASE + 0x04) /* Baud Divisor MSB (DLAB=1) */
#define UART_IIR        REG32(UART_BASE + 0x08) /* Interrupt Identification (Read) */
#define UART_FCR        REG32(UART_BASE + 0x08) /* FIFO Control (Write) */
#define UART_LCR        REG32(UART_BASE + 0x0C) /* Line Control */
#define UART_MCR        REG32(UART_BASE + 0x10) /* Modem Control */
#define UART_LSR        REG32(UART_BASE + 0x14) /* Line Status */
#define UART_MSR        REG32(UART_BASE + 0x18) /* Modem Status */
#define UART_SCR        REG32(UART_BASE + 0x1C) /* Scratch Register */

#define UART_LSR_DR     (1UL << 0)
#define UART_LSR_THRE   (1UL << 5)
#define UART_LSR_TEMT   (1UL << 6)

/* =============================================================================
 * 5. APB[3] GPIO Controller Registers (OpenTitan Style, 32-bit Pins)
 * ============================================================================= */
#define GPIO_IN         REG32(GPIO_BASE + 0x14) /* Input Data Read */
#define GPIO_OUT        REG32(GPIO_BASE + 0x18) /* Direct Output Write */
#define GPIO_SET        REG32(GPIO_BASE + 0x1C) /* Atomic Bit Set */
#define GPIO_CLEAR      REG32(GPIO_BASE + 0x20) /* Atomic Bit Clear */
#define GPIO_TOGGLE     REG32(GPIO_BASE + 0x24) /* Atomic Bit Toggle */
#define GPIO_EN         REG32(GPIO_BASE + 0x10) /* Output Enable Mask */
#define GPIO_INTR_STAT  REG32(GPIO_BASE + 0x38) /* Interrupt Status */

/* =============================================================================
 * 6. APB[4] SPI Master Controller Registers
 * ============================================================================= */
#define SPI_STATUS      REG32(SPI_BASE + 0x00) /* Status (BUSY, RX_EMPTY, TX_FULL) */
#define SPI_CLKDIV      REG32(SPI_BASE + 0x04) /* Clock Divider */
#define SPI_TXDATA      REG32(SPI_BASE + 0x08) /* TX FIFO Data */
#define SPI_RXDATA      REG32(SPI_BASE + 0x0C) /* RX FIFO Data */
#define SPI_CTRL        REG32(SPI_BASE + 0x10) /* Control (CS, Mode) */

/* =============================================================================
 * 7. Verification Mailbox Protocol Signatures (Anti-Vacuity Handshake)
 * ============================================================================= */
#define MAILBOX_ADDR    0x00020008UL /* DSRAM Dedicated Mailbox Address */
#define CMD_PASS        0xC0DEC0DEUL /* Dual-sided Test Pass Token */
#define CMD_FAIL        0xBAADF00DUL /* Test Failure Token */
#define CMD_HALT        0xDEADBEEFUL /* Test Complete / Halt */

#endif /* SOC_REGS_H */

