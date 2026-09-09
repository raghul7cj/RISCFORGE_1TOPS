/* =============================================================================
 * RISCFORGE 1TOPS — SPI Master & SPI Flash BFM Verification Test Program
 * ============================================================================= */

#include "spi_min.h"

int main(void) {
    int test_fail = 0;

    // 1. Initialize UART for live diagnostic console output
    uart_init();
    uart_puts("\n=======================================================\n");
    uart_puts("   RISCFORGE 1TOPS — SPI Master & Flash Smoke Test     \n");
    uart_puts("=======================================================\n");

    // 2. Initialize SPI Master (clk_div = 1 -> 25 MHz SPI clock @ 100 MHz SoC)
    uart_puts("[INFO] Initializing SPI Master Controller...\n");
    spi_init(1);
    uart_puts("[INFO] SPI Master Initialized.\n\n");

    // -------------------------------------------------------------------------
    // TEST 1: Read JEDEC ID (Opcode 0x9F)
    // -------------------------------------------------------------------------
    uart_puts("[TEST 1] Querying SPI Flash JEDEC ID (Opcode 0x9F)...\n");
    uint32_t jedec_id = spi_flash_read_id();
    uart_puts("  Expected ID : 0x00EF4018 / 0x00010219\n");
    uart_puts("  Received ID : ");
    uart_puthex(jedec_id);
    uart_puts("\n");

    // Check if ID matches standard JEDEC format (Winbond 0xEF4018 or Spansion 0x010219)
    if ((jedec_id & 0x00FFFFFF) == 0x00EF4018 || (jedec_id & 0x00FFFFFF) == 0x00010219) {
        uart_puts("  --> [TEST 1 PASSED]\n\n");
    } else {
        uart_puts("  --> [TEST 1 FAILED: Unexpected Flash ID]\n\n");
        test_fail++;
    }

    // -------------------------------------------------------------------------
    // TEST 2: Write Enable (0x06) & Read Status Register 1 (0x05)
    // -------------------------------------------------------------------------
    uart_puts("[TEST 2] Testing Write Enable (0x06) & Read Status (0x05)...\n");
    spi_flash_write_enable();
    uint8_t status = spi_flash_read_status();
    uart_puts("  Status Register : ");
    uart_puthex(status);
    uart_puts(" (WEL bit should be 1)\n");

    if (status & 0x02) {
        uart_puts("  --> [TEST 2 PASSED: WEL bit set]\n\n");
    } else {
        uart_puts("  --> [TEST 2 FAILED: WEL bit not set]\n\n");
        test_fail++;
    }

    // -------------------------------------------------------------------------
    // TEST 3 & 4: Page Program (0x02) & Standard Read Data (0x03)
    // -------------------------------------------------------------------------
    uint32_t test_addr = 0x001000;
    uint32_t test_data = 0x55AA1234;

    uart_puts("[TEST 3] Page Program (Opcode 0x02)...\n");
    uart_puts("  Target Addr : ");
    uart_puthex(test_addr);
    uart_puts("\n  Write Data  : ");
    uart_puthex(test_data);
    uart_puts("\n");

    spi_flash_page_program(test_addr, test_data);
    uart_puts("  Page program command issued.\n\n");

    uart_puts("[TEST 4] Standard Read Data (Opcode 0x03)...\n");
    uint32_t read_data = spi_flash_read_data(test_addr);
    uart_puts("  Read Data   : ");
    uart_puthex(read_data);
    uart_puts("\n");

    if (read_data == test_data) {
        uart_puts("  --> [TEST 4 PASSED: Read data matches written data]\n\n");
    } else {
        uart_puts("  --> [TEST 4 FAILED: Data mismatch]\n\n");
        test_fail++;
    }

    // -------------------------------------------------------------------------
    // TEST 5: Fast Read (Opcode 0x0B) with 8 Dummy Cycles
    // -------------------------------------------------------------------------
    uart_puts("[TEST 5] Fast Read Data (Opcode 0x0B, 8 Dummy Cycles)...\n");
    uint32_t fast_data = spi_flash_fast_read(test_addr, 8);
    uart_puts("  Fast Read   : ");
    uart_puthex(fast_data);
    uart_puts("\n");

    if (fast_data == test_data) {
        uart_puts("  --> [TEST 5 PASSED: Fast read data matches]\n\n");
    } else {
        uart_puts("  --> [TEST 5 FAILED: Fast read data mismatch]\n\n");
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

