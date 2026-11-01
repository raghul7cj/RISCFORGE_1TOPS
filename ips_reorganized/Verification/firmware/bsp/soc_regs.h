/* =============================================================================
 * RISCFORGE 1TOPS — Authoritative SoC Memory Map & Registers (soc_regs.h)
 * =============================================================================
 * Hardware source of truth:
 *   - RTL_SOC/riscforge_soc_subsystem.sv
 *   - RTL_SOC/boot_rom.sv
 *   - apb_timer-master/rtl/timer.sv (REG_TIMER=0x00, REG_TIMER_CTRL=0x04, REG_CMP=0x08)
 * Memory Map:
 *   - BootROM : 0x0000_0000 (64 Bytes = 16 words, BOOTROM_NUM_WORDS=16)
 *   - ISRAM   : 0x0001_0000 (32 KiB)
 *   - DSRAM   : 0x0002_0000 (32 KiB)
 *   - APB Base: 0x4000_0000
 * ============================================================================= */

#ifndef RISCFORGE_SOC_REGS_H
#define RISCFORGE_SOC_REGS_H

#include <stdint.h>

#define REG32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))
#define REG8(addr)  (*(volatile uint8_t  *)(uintptr_t)(addr))

/* =============================================================================
 * 1. Global Memory Map
 * ============================================================================= */
#define BOOTROM_BASE          0x00000000UL /* 64 Bytes BootROM stub */
#define BOOTROM_SIZE_BYTES    64UL

#define ISRAM_BASE            0x00010000UL /* 32 KiB Instruction SRAM */
#define ISRAM_SIZE_BYTES      0x00008000UL

#define DSRAM_BASE            0x00020000UL /* 32 KiB Data SRAM */
#define DSRAM_SIZE_BYTES      0x00008000UL

#define APB_BASE              0x40000000UL /* APB Peripheral Window */
#define I2C_BASE              0x40000000UL /* APB[0] I2C Master */
#define TIMER0_BASE           0x40001000UL /* APB[1] APB Timer 0 */
#define UART_BASE             0x40002000UL /* APB[2] 16550 UART */
#define GPIO_BASE             0x40003000UL /* APB[3] 32-bit GPIO */
#define SPI_BASE              0x40004000UL /* APB[4] SPI Master / Bootloader APB */
#define TIMER1_BASE           0x40005000UL /* APB[5] APB Timer 1 */

/* =============================================================================
 * 2. APB[0] I2C Master Registers
 * ============================================================================= */
#define I2C_REG_CLK_PRESCALER REG32(I2C_BASE + 0x00)
#define I2C_REG_CTRL          REG32(I2C_BASE + 0x04)
#define I2C_REG_RX            REG32(I2C_BASE + 0x08)
#define I2C_REG_STATUS        REG32(I2C_BASE + 0x0C)
#define I2C_REG_TX            REG32(I2C_BASE + 0x10)
#define I2C_REG_CMD           REG32(I2C_BASE + 0x14)

/* =============================================================================
 * 3. APB[1] & APB[5] Timer Registers (Timer 0 & Timer 1)
 * According to timer.sv:
 *   PADDR[3:2] == 2'b00 (0x00) -> REG_TIMER (Value)
 *   PADDR[3:2] == 2'b01 (0x04) -> REG_TIMER_CTRL (Control)
 *   PADDR[3:2] == 2'b10 (0x08) -> REG_CMP (Compare)
 * Channel 1 is selected when PADDR[4] == 1 (+0x10)
 * ============================================================================= */
#define TIMER0_VAL_CH0        REG32(TIMER0_BASE + 0x00)
#define TIMER0_CTRL_CH0       REG32(TIMER0_BASE + 0x04)
#define TIMER0_CMP_CH0        REG32(TIMER0_BASE + 0x08)
#define TIMER0_VAL_CH1        REG32(TIMER0_BASE + 0x10)
#define TIMER0_CTRL_CH1       REG32(TIMER0_BASE + 0x14)
#define TIMER0_CMP_CH1        REG32(TIMER0_BASE + 0x18)

#define TIMER1_VAL_CH0        REG32(TIMER1_BASE + 0x00)
#define TIMER1_CTRL_CH0       REG32(TIMER1_BASE + 0x04)
#define TIMER1_CMP_CH0        REG32(TIMER1_BASE + 0x08)
#define TIMER1_VAL_CH1        REG32(TIMER1_BASE + 0x10)
#define TIMER1_CTRL_CH1       REG32(TIMER1_BASE + 0x14)
#define TIMER1_CMP_CH1        REG32(TIMER1_BASE + 0x18)

/* Timer control bitfields */
#define TIMER_CTRL_EN         (1UL << 0)

/* =============================================================================
 * 4. APB[2] 16550 UART Registers
 * ============================================================================= */
#define UART_RBR              REG32(UART_BASE + 0x00) /* RX Buffer (DLAB=0, Read) */
#define UART_THR              REG32(UART_BASE + 0x00) /* TX Holding (DLAB=0, Write) */
#define UART_DLL              REG32(UART_BASE + 0x00) /* Baud Divisor LSB (DLAB=1) */
#define UART_IER              REG32(UART_BASE + 0x04) /* Interrupt Enable */
#define UART_DLM              REG32(UART_BASE + 0x04) /* Baud Divisor MSB (DLAB=1) */
#define UART_IIR              REG32(UART_BASE + 0x08) /* Interrupt ID (Read) */
#define UART_FCR              REG32(UART_BASE + 0x08) /* FIFO Control (Write) */
#define UART_LCR              REG32(UART_BASE + 0x0C) /* Line Control */
#define UART_MCR              REG32(UART_BASE + 0x10) /* Modem Control */
#define UART_LSR              REG32(UART_BASE + 0x14) /* Line Status */
#define UART_MSR              REG32(UART_BASE + 0x18) /* Modem Status */
#define UART_SCR              REG32(UART_BASE + 0x1C) /* Scratch Register */

#define UART_LSR_DR           (1UL << 0) /* Data Ready */
#define UART_LSR_THRE         (1UL << 5) /* TX Holding Register Empty */
#define UART_LSR_TEMT         (1UL << 6) /* Transmitter Empty */

/* =============================================================================
 * 5. APB[3] GPIO Registers
 * ============================================================================= */
#define GPIO_INTR_STATE       REG32(GPIO_BASE + 0x00)
#define GPIO_INTR_ENABLE      REG32(GPIO_BASE + 0x04)
#define GPIO_INTR_TEST        REG32(GPIO_BASE + 0x08)
#define GPIO_DATA_IN          REG32(GPIO_BASE + 0x0C)
#define GPIO_DIRECT_OUT       REG32(GPIO_BASE + 0x10)
#define GPIO_DIRECT_OE        REG32(GPIO_BASE + 0x18)

/* =============================================================================
 * 6. APB[4] SPI Master Registers
 * ============================================================================= */
#define SPI_REG_STATUS        REG32(SPI_BASE + 0x00)
#define SPI_REG_CLKDIV        REG32(SPI_BASE + 0x04)
#define SPI_REG_SPICMD        REG32(SPI_BASE + 0x08)
#define SPI_REG_SPIADR        REG32(SPI_BASE + 0x0C)
#define SPI_REG_SPILEN        REG32(SPI_BASE + 0x10)
#define SPI_REG_SPIDUM        REG32(SPI_BASE + 0x14)
#define SPI_REG_TXFIFO        REG32(SPI_BASE + 0x18)
#define SPI_REG_RXFIFO        REG32(SPI_BASE + 0x20)
#define SPI_REG_INTCFG        REG32(SPI_BASE + 0x24)
#define SPI_REG_INTSTA        REG32(SPI_BASE + 0x28)

#endif /* RISCFORGE_SOC_REGS_H */
