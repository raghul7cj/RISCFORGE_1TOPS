/* =============================================================================
 * RISCFORGE 1TOPS — APB I2C Master Driver (i2c_driver.c)
 * Direct Register Model for OpenCores / ETH Zurich APB I2C Master
 * ============================================================================= */

#include "i2c_driver.h"

#define I2C_DEFAULT_TIMEOUT_CYCLES 500000UL

static int i2c_wait_tip(void) {
    uint32_t start_cycle = csr_read_mcycle();
    while (REG32_READ(APB_I2C_BASE + I2C_SR_OFFSET) & I2C_SR_TIP) {
        if ((csr_read_mcycle() - start_cycle) > I2C_DEFAULT_TIMEOUT_CYCLES) {
            return -1; /* Hardware TIP timeout */
        }
    }
    return 0;
}

void i2c_init(uint16_t prescaler) {
    /* Disable I2C core while configuring */
    REG32_WRITE(APB_I2C_BASE + I2C_CTR_OFFSET, 0x00);
    
    REG32_WRITE(APB_I2C_BASE + I2C_PRER_LO_OFFSET, prescaler & 0xFF);
    REG32_WRITE(APB_I2C_BASE + I2C_PRER_HI_OFFSET, (prescaler >> 8) & 0xFF);
    
    /* Enable I2C Core */
    REG32_WRITE(APB_I2C_BASE + I2C_CTR_OFFSET, I2C_CTR_EN);
}

int i2c_start_addr(uint8_t addr_7bit, int is_read) {
    uint8_t addr_byte = (addr_7bit << 1) | (is_read ? 1 : 0);
    REG32_WRITE(APB_I2C_BASE + I2C_TXR_OFFSET, addr_byte);
    REG32_WRITE(APB_I2C_BASE + I2C_CR_OFFSET, I2C_CR_STA | I2C_CR_WR);
    
    if (i2c_wait_tip() != 0) {
        return -2; /* Timeout */
    }
    
    /* Check RXACK (0 = ACK received, 1 = NACK) */
    uint32_t sr = REG32_READ(APB_I2C_BASE + I2C_SR_OFFSET);
    if (sr & I2C_SR_RXACK) {
        /* NACK received — issue STOP to release bus */
        REG32_WRITE(APB_I2C_BASE + I2C_CR_OFFSET, I2C_CR_STO | I2C_CR_IACK);
        i2c_wait_tip();
        return -1; /* NACK */
    }
    return 0; /* ACK */
}

int i2c_write_byte(uint8_t data, int send_stop) {
    REG32_WRITE(APB_I2C_BASE + I2C_TXR_OFFSET, data);
    uint32_t cr = I2C_CR_WR;
    if (send_stop) cr |= I2C_CR_STO;
    REG32_WRITE(APB_I2C_BASE + I2C_CR_OFFSET, cr);
    
    if (i2c_wait_tip() != 0) {
        return -2; /* Timeout */
    }
    
    uint32_t sr = REG32_READ(APB_I2C_BASE + I2C_SR_OFFSET);
    if (sr & I2C_SR_RXACK) {
        if (!send_stop) {
            /* If we didn't send stop on NACK, force STOP now */
            REG32_WRITE(APB_I2C_BASE + I2C_CR_OFFSET, I2C_CR_STO | I2C_CR_IACK);
            i2c_wait_tip();
        }
        return -1; /* NACK */
    }
    return 0;
}

int i2c_read_byte(uint8_t *data, int send_ack, int send_stop) {
    uint32_t cr = I2C_CR_RD;
    if (!send_ack) cr |= I2C_CR_ACK; /* NACK to slave */
    if (send_stop) cr |= I2C_CR_STO;
    REG32_WRITE(APB_I2C_BASE + I2C_CR_OFFSET, cr);
    
    if (i2c_wait_tip() != 0) {
        return -2; /* Timeout */
    }
    
    *data = (uint8_t)(REG32_READ(APB_I2C_BASE + I2C_RXR_OFFSET) & 0xFF);
    return 0;
}

/* Recover from stuck SDA / BUSY state / transfer timeout */
int i2c_recover(uint16_t prescaler) {
    /* 1. Disable the I2C Master controller */
    REG32_WRITE(APB_I2C_BASE + I2C_CTR_OFFSET, 0x00);
    
    /* 2. Clear command register and acknowledge any pending interrupt */
    REG32_WRITE(APB_I2C_BASE + I2C_CR_OFFSET, I2C_CR_IACK);
    
    /* 3. Re-initialize prescaler */
    REG32_WRITE(APB_I2C_BASE + I2C_PRER_LO_OFFSET, prescaler & 0xFF);
    REG32_WRITE(APB_I2C_BASE + I2C_PRER_HI_OFFSET, (prescaler >> 8) & 0xFF);
    
    /* 4. Re-enable I2C Master */
    REG32_WRITE(APB_I2C_BASE + I2C_CTR_OFFSET, I2C_CTR_EN);
    
    /* 5. Issue emergency STOP command to release bus lines */
    REG32_WRITE(APB_I2C_BASE + I2C_CR_OFFSET, I2C_CR_STO | I2C_CR_IACK);
    i2c_wait_tip();
    
    /* Check if bus is free (BUSY == 0) */
    uint32_t sr = REG32_READ(APB_I2C_BASE + I2C_SR_OFFSET);
    return (sr & I2C_SR_BUSY) ? -1 : 0;
}
