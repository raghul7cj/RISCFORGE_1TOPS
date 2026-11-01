/* =============================================================================
 * APB I2C Master Verification Example (AT24C02 EEPROM Write & Read)
 * ============================================================================= */

#include "apb_i2c_drv.h"

#define SOC_I2C_BASE 0x40000000UL
#define EEPROM_ADDR  0x50 /* 7-bit I2C address */

bool test_i2c_eeprom_roundtrip(uint8_t mem_addr, uint8_t data_val) {
    /* 50MHz clk, 100kHz I2C: prescaler = (50000000 / (5 * 100000)) - 1 = 99 */
    i2c_init(SOC_I2C_BASE, 99);
    
    /* 1. Write byte to EEPROM */
    if (!i2c_write_byte(SOC_I2C_BASE, (EEPROM_ADDR << 1) | 0, true, false)) return false;
    if (!i2c_write_byte(SOC_I2C_BASE, mem_addr, false, false)) return false;
    if (!i2c_write_byte(SOC_I2C_BASE, data_val, false, true)) return false;
    
    /* Simple delay for EEPROM internal write cycle */
    for (volatile int i = 0; i < 50000; i++);
    
    /* 2. Read byte back */
    if (!i2c_write_byte(SOC_I2C_BASE, (EEPROM_ADDR << 1) | 0, true, false)) return false;
    if (!i2c_write_byte(SOC_I2C_BASE, mem_addr, false, false)) return false;
    if (!i2c_write_byte(SOC_I2C_BASE, (EEPROM_ADDR << 1) | 1, true, false)) return false;
    uint8_t readback = i2c_read_byte(SOC_I2C_BASE, true, true);
    
    return (readback == data_val);
}
