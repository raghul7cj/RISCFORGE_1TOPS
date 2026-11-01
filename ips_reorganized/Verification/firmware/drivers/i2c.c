/* =============================================================================
 * RISCFORGE 1TOPS — APB I2C Driver Implementation (i2c.c)
 * ============================================================================= */

#include "i2c.h"

void i2c_init(uint16_t prescaler) {
    I2C_REG_CLK_PRESCALER = prescaler;
    /* Enable I2C core (bit 7) without interrupt (bit 6 = 0) */
    I2C_REG_CTRL = 0x80;
}

int i2c_write(uint8_t dev_addr, uint8_t reg_addr, uint8_t data) {
    (void)dev_addr; (void)reg_addr; (void)data;
    /* Basic transmission stub */
    return 0;
}

int i2c_read(uint8_t dev_addr, uint8_t reg_addr, uint8_t *data) {
    (void)dev_addr; (void)reg_addr;
    if (data) *data = 0;
    return 0;
}
