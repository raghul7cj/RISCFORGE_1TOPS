/* =============================================================================
 * RISCFORGE 1TOPS — APB I2C Master Driver (i2c_driver.h)
 * Direct Register Model for OpenCores / ETH Zurich APB I2C Master
 * ============================================================================= */

#ifndef RISCFORGE_I2C_DRIVER_H_
#define RISCFORGE_I2C_DRIVER_H_

#include <stdint.h>
#include "soc_regs.h"

/* Register Offsets (Direct Hardware Model) */
#define I2C_PRER_LO_OFFSET 0x00  /* Clock Prescaler LSB */
#define I2C_PRER_HI_OFFSET 0x04  /* Clock Prescaler MSB */
#define I2C_CTR_OFFSET     0x08  /* Control Register */
#define I2C_RXR_OFFSET     0x0C  /* Receive Data (Read-only) */
#define I2C_TXR_OFFSET     0x0C  /* Transmit Data (Write-only) */
#define I2C_CR_OFFSET      0x10  /* Command Register (Write-only) */
#define I2C_SR_OFFSET      0x10  /* Status Register (Read-only) */

/* CTR Bits */
#define I2C_CTR_EN         (1 << 7)  /* Core Enable */
#define I2C_CTR_IEN        (1 << 6)  /* Interrupt Enable */

/* CR Bits */
#define I2C_CR_STA         (1 << 7)  /* Generate (Repeated) START */
#define I2C_CR_STO         (1 << 6)  /* Generate STOP */
#define I2C_CR_RD          (1 << 5)  /* Read from slave */
#define I2C_CR_WR          (1 << 4)  /* Write to slave */
#define I2C_CR_ACK         (1 << 3)  /* ACK value to send (0=ACK, 1=NACK) */
#define I2C_CR_IACK        (1 << 0)  /* Interrupt Acknowledge (Clear IF) */

/* SR Bits */
#define I2C_SR_RXACK       (1 << 7)  /* Received ACK from slave (0=ACK, 1=NACK) */
#define I2C_SR_BUSY        (1 << 6)  /* Bus Busy (1=Bus busy, 0=Bus free) */
#define I2C_SR_AL          (1 << 5)  /* Arbitration Lost */
#define I2C_SR_TIP         (1 << 1)  /* Transfer in Progress (1=Transferring) */
#define I2C_SR_IF          (1 << 0)  /* Interrupt Flag (Transfer complete) */

/* Standard API */
void i2c_init(uint16_t prescaler);
int  i2c_start_addr(uint8_t addr_7bit, int is_read);
int  i2c_write_byte(uint8_t data, int send_stop);
int  i2c_read_byte(uint8_t *data, int send_ack, int send_stop);

/* Error & Illegal State Recovery */
int  i2c_recover(uint16_t prescaler);

#endif /* RISCFORGE_I2C_DRIVER_H_ */
