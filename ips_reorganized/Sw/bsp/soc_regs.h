/* =============================================================================
 * RISCFORGE 1TOPS - SoC Memory Map & Register Definitions Header (soc_regs.h)
 * =============================================================================
 * Verified against hardware RTL:
 *   - RTL_SOC/riscforge_soc_subsystem.sv
 *   - apb_i2c-master/apb_i2c.sv
 *   - apb_timer-master/rtl/apb_timer.sv & timer.sv
 *   - apb_uart-main/rtl/apb_uart.sv
 *   - gpio-master/gpio_reg_pkg.sv
 *   - spi_master_ip/spi_master/spi_master_apb_if.sv
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

/* Mailbox for test bench status reporting */
#define MAILBOX_ADDR    0x00028000UL
#define CMD_PASS        0x00000001UL
#define CMD_FAIL        0xDEADBEEFUL

/* =============================================================================
 * 2. APB[0] I2C Master Registers (apb_i2c.sv decoder: PADDR[5:2])
 * ============================================================================= */
#define I2C_REG_CLK_PRESCALER REG32(I2C_BASE + 0x00) /* 16-bit Prescaler (R/W) */
#define I2C_REG_CTRL          REG32(I2C_BASE + 0x04) /* Control (EN=bit 7, IEN=bit 6) */
#define I2C_REG_RX            REG32(I2C_BASE + 0x08) /* Receive Data (Read) */
#define I2C_REG_STATUS        REG32(I2C_BASE + 0x0C) /* Status Register (Read) */
#define I2C_REG_TX            REG32(I2C_BASE + 0x10) /* Transmit Data (Write) */
#define I2C_REG_CMD           REG32(I2C_BASE + 0x14) /* Command Register (Write) */

/* =============================================================================
 * 3. APB[1] & APB[5] APB Timers (Timer 0 & Timer 1, 2 Channels Each)
 * Channel 0 selected when PADDR[4]=0; Channel 1 selected when PADDR[4]=1
 * Register Offsets from timer.sv:
 *   PADDR[3:2] == 2'b00 (0x00) -> REG_TIMER (Value)
 *   PADDR[3:2] == 2'b01 (0x04) -> REG_TIMER_CTRL (Control)
 *   PADDR[3:2] == 2'b10 (0x08) -> REG_CMP (Compare)
 * ============================================================================= */
/* Timer 0 Channel 0 */
#define TIMER0_VAL            REG32(TIMER0_BASE + 0x00) /* Current Counter Value */
#define TIMER0_CTRL           REG32(TIMER0_BASE + 0x04) /* Control: [0]=EN, [5:3]=PRESCALER */
#define TIMER0_CMP            REG32(TIMER0_BASE + 0x08) /* Compare Value */

/* Timer 0 Channel 1 */
#define TIMER0_CH1_VAL        REG32(TIMER0_BASE + 0x10)
#define TIMER0_CH1_CTRL       REG32(TIMER0_BASE + 0x14)
#define TIMER0_CH1_CMP        REG32(TIMER0_BASE + 0x18)

/* Timer 1 Channel 0 */
#define TIMER1_VAL            REG32(TIMER1_BASE + 0x00)
#define TIMER1_CTRL           REG32(TIMER1_BASE + 0x04)
#define TIMER1_CMP            REG32(TIMER1_BASE + 0x08)

/* Timer 1 Channel 1 */
#define TIMER1_CH1_VAL        REG32(TIMER1_BASE + 0x10)
#define TIMER1_CH1_CTRL       REG32(TIMER1_BASE + 0x14)
#define TIMER1_CH1_CMP        REG32(TIMER1_BASE + 0x18)

/* Timer control bitfields */
#define TIMER_CTRL_EN               (1UL << 0)
#define TIMER_CTRL_PRESCALER_SHIFT  3
#define TIMER_CTRL_PRESCALER_MASK   (0x7UL << TIMER_CTRL_PRESCALER_SHIFT)
#define TIMER_CTRL_PRESCALER(val)   (((uint32_t)(val) & 0x7UL) << TIMER_CTRL_PRESCALER_SHIFT)

/* =============================================================================
 * 4. APB[2] 16550 UART Registers
 * ============================================================================= */
#define UART_RBR              REG32(UART_BASE + 0x00) /* RX Buffer (DLAB=0, Read) */
#define UART_THR              REG32(UART_BASE + 0x00) /* TX Holding (DLAB=0, Write) */
#define UART_DLL              REG32(UART_BASE + 0x00) /* Baud Divisor LSB (DLAB=1) */
#define UART_IER              REG32(UART_BASE + 0x04) /* Interrupt Enable */
#define UART_DLM              REG32(UART_BASE + 0x04) /* Baud Divisor MSB (DLAB=1) */
#define UART_IIR              REG32(UART_BASE + 0x08) /* Interrupt Identification (Read) */
#define UART_FCR              REG32(UART_BASE + 0x08) /* FIFO Control (Write) */
#define UART_LCR              REG32(UART_BASE + 0x0C) /* Line Control */
#define UART_MCR              REG32(UART_BASE + 0x10) /* Modem Control */
#define UART_LSR              REG32(UART_BASE + 0x14) /* Line Status */
#define UART_MSR              REG32(UART_BASE + 0x18) /* Modem Status */
#define UART_SCR              REG32(UART_BASE + 0x1C) /* Scratch Register */

#define UART_LSR_DR           (1UL << 0)
#define UART_LSR_THRE         (1UL << 5)
#define UART_LSR_TEMT         (1UL << 6)

/* =============================================================================
 * 5. APB[3] GPIO Controller Registers (PULP Parametric GPIO, gpio_reg_pkg.sv)
 * ============================================================================= */
#define GPIO_INFO             REG32(GPIO_BASE + 0x000) /* IP Information */
#define GPIO_CFG              REG32(GPIO_BASE + 0x004) /* Configuration */
#define GPIO_EN               REG32(GPIO_BASE + 0x080) /* Output Enable Mask */
#define GPIO_IN               REG32(GPIO_BASE + 0x100) /* Input Data Read */
#define GPIO_OUT              REG32(GPIO_BASE + 0x180) /* Direct Output Write */
#define GPIO_SET              REG32(GPIO_BASE + 0x200) /* Atomic Bit Set */
#define GPIO_CLEAR            REG32(GPIO_BASE + 0x280) /* Atomic Bit Clear */
#define GPIO_TOGGLE           REG32(GPIO_BASE + 0x300) /* Atomic Bit Toggle */
#define GPIO_INTR_RISE_EN     REG32(GPIO_BASE + 0x380) /* Rising-edge Interrupt Enable */
#define GPIO_INTR_FALL_EN     REG32(GPIO_BASE + 0x400) /* Falling-edge Interrupt Enable */
#define GPIO_INTR_STAT        REG32(GPIO_BASE + 0x580) /* Interrupt Status (W1C Clear) */

/* =============================================================================
 * 6. APB[4] SPI Master Controller Registers (spi_master_apb_if.sv)
 * ============================================================================= */
#define SPI_STATUS            REG32(SPI_BASE + 0x00) /* Status Register */
#define SPI_CLKDIV            REG32(SPI_BASE + 0x04) /* Clock Divider */
#define SPI_SPICMD            REG32(SPI_BASE + 0x08) /* Command Register */
#define SPI_SPIADR            REG32(SPI_BASE + 0x0C) /* Address Register */
#define SPI_SPILEN            REG32(SPI_BASE + 0x10) /* Transfer Lengths */
#define SPI_SPIDUM            REG32(SPI_BASE + 0x14) /* Dummy Cycles */
#define SPI_TXFIFO            REG32(SPI_BASE + 0x18) /* TX FIFO Data */
#define SPI_RXFIFO            REG32(SPI_BASE + 0x20) /* RX FIFO Data */
#define SPI_INTCFG            REG32(SPI_BASE + 0x24) /* Interrupt Configuration */
#define SPI_INTSTA            REG32(SPI_BASE + 0x28) /* Interrupt Status */

#endif /* SOC_REGS_H */
