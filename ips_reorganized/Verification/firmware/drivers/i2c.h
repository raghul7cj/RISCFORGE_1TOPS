/* =============================================================================
 * RISCFORGE 1TOPS — APB I2C Driver Header (i2c.h)
 * ============================================================================= */

#ifndef RISCFORGE_I2C_H
#define RISCFORGE_I2C_H

#include <stdint.h>
#include "../bsp/soc_regs.h"

void i2c_init(uint16_t prescaler);
int  i2c_write(uint8_t dev_addr, uint8_t reg_addr, uint8_t data);
int  i2c_read(uint8_t dev_addr, uint8_t reg_addr, uint8_t *data);

#endif /* RISCFORGE_I2C_H */
