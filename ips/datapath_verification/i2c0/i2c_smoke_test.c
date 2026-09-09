/* =============================================================================
 * RISCFORGE 1TOPS — I2C Master & AT24C02 EEPROM Verification Test Program
 * ============================================================================= */

#include "i2c_min.h"

// Simple busy delay loop
static inline void delay_cycles(volatile uint32_t count) {
    while (count--) {
        __asm__ volatile("nop");
    }
}

int main(void) {
    int test_fail = 0;
    uint8_t read_val = 0;
    int err = 0;

    // 1. Initialize UART for live diagnostic console output
    uart_init();
    uart_puts("\n=======================================================\n");
    uart_puts("   RISCFORGE 1TOPS - I2C Master & AT24C02 Smoke Test   \n");
    uart_puts("=======================================================\n");

    // 2. Initialize I2C Master Controller (Prescaler = 20 for fast simulation clock)
    uart_puts("[INFO] Initializing I2C Master Controller (Prescaler=20)...\n");
    i2c_init(20);
    uart_puts("[INFO] I2C Master Initialized.\n\n");

    // -------------------------------------------------------------------------
    // TEST 1: Single Byte Write to EEPROM (Addr 0x10 = 0xA5)
    // -------------------------------------------------------------------------
    uint8_t target_mem_addr1 = 0x10;
    uint8_t write_val1       = 0xA5;

    uart_puts("[TEST 1] EEPROM Byte Write...\n");
    uart_puts("  Slave Addr : 0x50\n");
    uart_puts("  Mem Offset : ");
    uart_puthex(target_mem_addr1);
    uart_puts("\n  Write Data : ");
    uart_puthex(write_val1);
    uart_puts("\n");

    err = i2c_eeprom_write_byte(EEPROM_I2C_ADDR, target_mem_addr1, write_val1);
    if (err == 0) {
        uart_puts("  --> [TEST 1 PASSED: Byte Write ACKed by Slave]\n\n");
    } else {
        uart_puts("  --> [TEST 1 FAILED: NACK received on Write]\n\n");
        test_fail++;
    }

    // Wait for AT24C02 internal write cycle completion (WRITE_CYCLE_CLKS = 64)
    delay_cycles(200);

    // -------------------------------------------------------------------------
    // TEST 2: Single Byte Random Read & Validation (Addr 0x10)
    // -------------------------------------------------------------------------
    uart_puts("[TEST 2] EEPROM Byte Read & Compare...\n");
    err = i2c_eeprom_read_byte(EEPROM_I2C_ADDR, target_mem_addr1, &read_val);
    uart_puts("  Read Data  : ");
    uart_puthex(read_val);
    uart_puts("\n");

    if (err == 0 && read_val == write_val1) {
        uart_puts("  --> [TEST 2 PASSED: Read data matches written data 0xA5]\n\n");
    } else {
        uart_puts("  --> [TEST 2 FAILED: Data mismatch or NACK]\n\n");
        test_fail++;
    }

    // -------------------------------------------------------------------------
    // TEST 3: Multi-Location Verification (Addr 0x20 = 0x5A, Addr 0x30 = 0x3C)
    // -------------------------------------------------------------------------
    uart_puts("[TEST 3] Multi-Location Write & Read Verification...\n");
    uint8_t addr2 = 0x20, val2 = 0x5A;
    uint8_t addr3 = 0x30, val3 = 0x3C;
    uint8_t rval2 = 0, rval3 = 0;

    // Write location 2
    i2c_eeprom_write_byte(EEPROM_I2C_ADDR, addr2, val2);
    delay_cycles(200);

    // Write location 3
    i2c_eeprom_write_byte(EEPROM_I2C_ADDR, addr3, val3);
    delay_cycles(200);

    // Read back location 2
    i2c_eeprom_read_byte(EEPROM_I2C_ADDR, addr2, &rval2);
    // Read back location 3
    i2c_eeprom_read_byte(EEPROM_I2C_ADDR, addr3, &rval3);

    uart_puts("  Addr 0x20 -> Exp: 0x5A, Got: ");
    uart_puthex(rval2);
    uart_puts("\n  Addr 0x30 -> Exp: 0x3C, Got: ");
    uart_puthex(rval3);
    uart_puts("\n");

    if (rval2 == val2 && rval3 == val3) {
        uart_puts("  --> [TEST 3 PASSED: Both locations verified successfully]\n\n");
    } else {
        uart_puts("  --> [TEST 3 FAILED: Data mismatch in multi-location test]\n\n");
        test_fail++;
    }

    // -------------------------------------------------------------------------
    // Final Test Summary
    // -------------------------------------------------------------------------
    uart_puts("=======================================================\n");
    if (test_fail == 0) {
        uart_puts(">>> TEST RESULT: [ PASSED ] <<<\n");
    } else {
        uart_puts(">>> TEST RESULT: [ FAILED ] <<<\n");
    }
    uart_puts("=======================================================\n\n");

    return test_fail;
}
