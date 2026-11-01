/* =============================================================================
 * RISCFORGE APB I2C Master Driver & Register Definitions
 * Base Address: I2C_BASE = 0x40000000
 * Verified directly against RTL: apb_i2c-master/apb_i2c.sv (s_apb_addr = PADDR[5:2])
 * ============================================================================= */

#ifndef APB_I2C_DRV_H
#define APB_I2C_DRV_H

#include <stdint.h>
#include <stdbool.h>

#define I2C_REG32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))

#define I2C_REG_CLK_PRESCALER(base) I2C_REG32((base) + 0x00) /* 16-bit Prescaler (R/W) */
#define I2C_REG_CTRL(base)          I2C_REG32((base) + 0x04) /* Control (EN=bit 7, IEN=bit 6) */
#define I2C_REG_RX(base)            I2C_REG32((base) + 0x08) /* Receive Data (Read) */
#define I2C_REG_STATUS(base)        I2C_REG32((base) + 0x0C) /* Status Register (Read) */
#define I2C_REG_TX(base)            I2C_REG32((base) + 0x10) /* Transmit Data (Write) */
#define I2C_REG_CMD(base)           I2C_REG32((base) + 0x14) /* Command Register (Write) */

/* Control register bits */
#define I2C_CTR_EN                  (1U << 7)
#define I2C_CTR_IEN                 (1U << 6)

/* Command register bits */
#define I2C_CR_STA                  (1U << 7) /* Generate START condition */
#define I2C_CR_STO                  (1U << 6) /* Generate STOP condition */
#define I2C_CR_RD                   (1U << 5) /* Read from slave */
#define I2C_CR_WR                   (1U << 4) /* Write to slave */
#define I2C_CR_ACK                  (1U << 3) /* Send ACK (0) or NACK (1) when reading */
#define I2C_CR_IACK                 (1U << 0) /* Interrupt acknowledge */

/* Status register bits */
#define I2C_SR_RXACK                (1U << 7) /* 0 = ACK received, 1 = NACK received */
#define I2C_SR_BUSY                 (1U << 6) /* I2C bus busy */
#define I2C_SR_AL                   (1U << 5) /* Arbitration lost */
#define I2C_SR_TIP                  (1U << 1) /* Transfer in progress */
#define I2C_SR_IF                   (1U << 0) /* Interrupt flag */

static inline void i2c_init(uintptr_t base, uint16_t prescaler) {
    I2C_REG_CTRL(base) = 0; /* Disable during config */
    I2C_REG_CLK_PRESCALER(base) = prescaler;
    I2C_REG_CTRL(base) = I2C_CTR_EN; /* Enable */
}

static inline void i2c_wait_tip(uintptr_t base) {
    while (I2C_REG_STATUS(base) & I2C_SR_TIP);
}

static inline bool i2c_write_byte(uintptr_t base, uint8_t byte, bool start, bool stop) {
    uint8_t cmd = I2C_CR_WR;
    if (start) cmd |= I2C_CR_STA;
    if (stop)  cmd |= I2C_CR_STO;
    
    I2C_REG_TX(base)  = byte;
    I2C_REG_CMD(base) = cmd;
    i2c_wait_tip(base);
    
    /* Return true if ACK was received (RXACK == 0) */
    return !(I2C_REG_STATUS(base) & I2C_SR_RXACK);
}

static inline uint8_t i2c_read_byte(uintptr_t base, bool stop, bool nack) {
    uint8_t cmd = I2C_CR_RD;
    if (stop) cmd |= I2C_CR_STO;
    if (nack) cmd |= I2C_CR_ACK; /* Send NACK */
    
    I2C_REG_CMD(base) = cmd;
    i2c_wait_tip(base);
    
    return (uint8_t)(I2C_REG_RX(base) & 0xFF);
}

#endif /* APB_I2C_DRV_H */
