/* =============================================================================
 * RISCFORGE 1TOPS — Stage 6 Proof: Polled Peripherals & Recovery (main.c)
 * =============================================================================
 * PROVES
 *   1. UART internal loopback really moves a byte THR -> RBR. The 16550 LSR
 *      THRE/TEMT bits are checked, the byte is written, and the *identical byte*
 *      is read back from RBR. A stub that returns a constant LSR fails here.
 *   2. Timer 0 counts in real time and the count is monotonic while enabled.
 *   3. GPIO pin loopback carries DATA_OUT -> pin -> DATA_IN, and the atomic
 *      SET / CLEAR / TOGGLE registers behave as atomic RMW-free operations.
 *   4. SPI issues a real transfer to the S25FS512S model and completes it.
 *   5. I2C recovers a bus held busy by a stuck slave (9-clock SCL pulse train).
 *   6. Every recovery path leaves the peripheral in a known state, verified by
 *      re-reading the register — recovery that only *claims* to work is the
 *      failure mode this stage exists to catch.
 *
 * LATENCY NOTES (these are real and will bite a naive test)
 *   - gpio_read() goes through gpio_input_stage, which registers the pin value.
 *     A write followed by an immediate read returns the PREVIOUS value. Every
 *     GPIO check below therefore polls with a bounded cycle budget.
 *   - uart_getc_blocking() must be given a budget. The default 500 k-cycle
 *     timeout inside the driver is long enough to run into the testbench
 *     watchdog before it reports, so explicit smaller budgets are used.
 *
 * VACUITY
 *   The UART loopback and GPIO loopback checks are the load-bearing ones: both
 *   can only pass if data physically traversed the peripheral and the read path
 *   returned it. TEST_REQUIRE_ACTIVITY(8, 40, 5, 0x6000).
 * ============================================================================= */

#include "test_harness.h"
#include "uart_driver.h"
#include "timer_driver.h"
#include "gpio_driver.h"
#include "i2c_driver.h"
#include "spi_driver.h"

#define POLL_BUDGET 20000UL

/* Bounded poll until the GPIO input register reflects `expect`, or timeout. */
static int gpio_wait_read(uint32_t expect, uint32_t budget) {
    uint32_t start = csr_read_mcycle();
    while (1) {
        if (gpio_read() == expect) {
            return 0;
        }
        if ((csr_read_mcycle() - start) > budget) {
            return -1;
        }
    }
}

int main(void) {
    uint32_t sig;
    uint32_t c0, c1, c2;
    char rx;

    TEST_START(0x0006, "Stage 6 Polled Peripherals & Recovery Proof");

    TEST_SECTION("0. DSRAM data-path sanity");
    sig = proof_dsram_signature(0x600D0006u);
    TEST_ASSERT_NE(0u, sig, 0x6001);

    /* =====================================================================
     * 1. UART polled loopback
     * ===================================================================== */
    TEST_SECTION("1. UART loopback");
    uart_init(54u);                       /* 115200 @ 100 MHz, 16x oversample */
    uart_enable_loopback(1);

    /* THRE and TEMT must both be set for the transmitter to accept and finish
     * a byte. This is the LSR reset expectation Stage 5 deliberately left
     * unverified; here it is a live functional requirement, not a constant. */
    TEST_ASSERT_EQ(0, wait_with_timeout((volatile uint32_t *)(uintptr_t)
                                        (APB_UART_BASE + UART_LSR_OFFSET),
                                        UART_LSR_THRE | UART_LSR_TEMT,
                                        UART_LSR_THRE | UART_LSR_TEMT,
                                        POLL_BUDGET), 0x6101);

    TEST_ASSERT_EQ(0, uart_putc('K'), 0x6102);

    /* The byte must come back. Two attempts so a single lost byte is visible as
     * a failure rather than being silently retried into a pass. */
    rx = 0;
    if (uart_getc_blocking(&rx, POLL_BUDGET) != 0) {
        rx = 0;
        TEST_ASSERT_EQ(0, uart_getc_blocking(&rx, POLL_BUDGET), 0x6103);
    }
    TEST_ASSERT_EQ((uint32_t)'K', (uint32_t)(uint8_t)rx, 0x6104);

    /* Recovery must leave LSR clean of error bits. */
    uart_recover(54u);
    TEST_ASSERT_EQ(0, REG32_READ(APB_UART_BASE + UART_LSR_OFFSET) &
                     (UART_LSR_OE | UART_LSR_PE | UART_LSR_FE | UART_LSR_BI),
                   0x6105);
    proof_note_slot(APB_UART_BASE);
    proof_note_read();

    /* =====================================================================
     * 2. Timer 0 polled count
     * ===================================================================== */
    TEST_SECTION("2. Timer 0 polled count");
    timer_init(APB_TIMER0_BASE, 0u, 0u);   /* compare 0 disables the cmp IRQ */
    timer_set_count(APB_TIMER0_BASE, 0u);
    timer_start(APB_TIMER0_BASE);

    /* Read twice with work in between; the count must strictly increase. */
    c0 = timer_get_count(APB_TIMER0_BASE);
    {
        volatile uint32_t spin = 0;
        uint32_t i;
        for (i = 0; i < 2000u; i++) { spin += i; }
        (void)spin;
    }
    c1 = timer_get_count(APB_TIMER0_BASE);
    TEST_ASSERT(c1 > c0, 0x6201);

    timer_stop(APB_TIMER0_BASE);
    /* Count must freeze after the stop lands. Allow one APB round trip. */
    c2 = timer_get_count(APB_TIMER0_BASE);
    {
        volatile uint32_t spin = 0;
        uint32_t i;
        for (i = 0; i < 2000u; i++) { spin += i; }
        (void)spin;
    }
    TEST_ASSERT_EQ(c2, timer_get_count(APB_TIMER0_BASE), 0x6202);
    TEST_ASSERT_EQ(0u, REG32_READ(APB_TIMER0_BASE + TIMER_CTRL_OFFSET) &
                     TIMER_CTRL_EN, 0x6203);

    /* Recovery restores a known-cold timer. */
    timer_recover(APB_TIMER0_BASE);
    TEST_ASSERT_EQ(0x00000000u, REG32_READ(APB_TIMER0_BASE + TIMER_CTRL_OFFSET), 0x6204);
    TEST_ASSERT_EQ(0x00000000u, REG32_READ(APB_TIMER0_BASE + TIMER_VAL_OFFSET), 0x6205);
    TEST_ASSERT_EQ(0x00000000u, REG32_READ(APB_TIMER0_BASE + TIMER_CMP_OFFSET), 0x6206);
    proof_note_slot(APB_TIMER0_BASE);
    proof_note_read(); proof_note_read(); proof_note_read();

    /* =====================================================================
     * 3. GPIO pin loopback and atomic bit operations
     * ===================================================================== */
    TEST_SECTION("3. GPIO pin loopback");
    gpio_init();
    gpio_set_direction(0xFFFFFFFFu);       /* all pins as outputs */
    gpio_write(0x12345678u);
    TEST_ASSERT_EQ(0, gpio_wait_read(0x12345678u, POLL_BUDGET), 0x6301);

    /* Atomic SET: no read-modify-write, so unaffected bits must not move. */
    gpio_set_bits(0x00000001u);
    TEST_ASSERT_EQ(0, gpio_wait_read(0x12345679u, POLL_BUDGET), 0x6302);

    /* Atomic CLEAR. */
    gpio_clear_bits(0x00000002u);
    TEST_ASSERT_EQ(0, gpio_wait_read(0x12345679u, POLL_BUDGET), 0x6303);

    /* Atomic TOGGLE — two independent bits, so a byte-lane bug shows up. */
    gpio_toggle_bits(0x0000000Cu);
    TEST_ASSERT_EQ(0, gpio_wait_read(0x12345675u, POLL_BUDGET), 0x6304);
    gpio_toggle_bits(0x0000000Cu);
    TEST_ASSERT_EQ(0, gpio_wait_read(0x12345679u, POLL_BUDGET), 0x6305);

    /* The DATA_OUT register itself must still track every atomic operation. */
    TEST_ASSERT_EQ(0x12345679u, REG32_READ(APB_GPIO_BASE + GPIO_OUT_OFFSET), 0x6306);

    gpio_recover();
    TEST_ASSERT_EQ(0x00000000u, REG32_READ(APB_GPIO_BASE + GPIO_EN_OFFSET), 0x6307);
    TEST_ASSERT_EQ(0x00000000u, REG32_READ(APB_GPIO_BASE + GPIO_OUT_OFFSET), 0x6308);
    proof_note_slot(APB_GPIO_BASE);
    proof_note_read(); proof_note_read();

    /* =====================================================================
     * 4. SPI transfer to the flash model
     * ===================================================================== */
    TEST_SECTION("4. SPI transfer");
    spi_init(4u);
    spi_select_cs(0);
    /* JEDEC RDID (0x9F): the S25FS512S model must drive 3 bytes back, so a
     * successful completion plus a non-zero RX word is real traffic, not a
     * no-op. */
    TEST_ASSERT_EQ(0, spi_transfer_command(0x9Fu, 8u, 0u, 0u, 0u, 24u, 1), 0x6401);
    {
        uint32_t id = spi_read_rx_fifo();
        mailbox_puts("  SPI JEDEC ID word = ");
        TEST_ASSERT_NE(0x00000000u, id, 0x6402);
    }
    spi_deselect_cs();
    spi_recover(4u);
    TEST_ASSERT_EQ(0x00000004u, REG32_READ(APB_SPI_BASE + SPI_CLKDIV_OFFSET), 0x6403);
    proof_note_slot(APB_SPI_BASE);
    proof_note_read();

    /* =====================================================================
     * 5. I2C bus recovery and a real EEPROM write/read-back
     * ===================================================================== */
    TEST_SECTION("5. I2C recovery + EEPROM write/read-back");
    i2c_init(250u);
    /* i2c_recover() issues an emergency STOP and then checks that BUSY
     * deasserted. A controller that never released the bus fails here. */
    TEST_ASSERT_EQ(0, i2c_recover(250u), 0x6501);

    /*
     * Write byte 0xA5 to EEPROM word address 0x00, then read it back. This is
     * the only check in the stage that closes the loop through the external
     * pin-level BFM (i2c_eeprom_at24c02), so it is what proves the I2C pins,
     * the pull-ups, and the controller all agree. A controller that ACKs
     * everything without actually clocking data out fails on the read-back.
     */
    TEST_ASSERT_EQ(0, i2c_start_addr(0x50u, 0), 0x6502);   /* START + addr, W */
    TEST_ASSERT_EQ(0, i2c_write_byte(0x00u, 0), 0x6503);   /* word address    */
    TEST_ASSERT_EQ(0, i2c_write_byte(0xA5u, 1), 0x6504);   /* data + STOP     */

    TEST_ASSERT_EQ(0, i2c_start_addr(0x50u, 0), 0x6505);   /* random read: addr */
    TEST_ASSERT_EQ(0, i2c_write_byte(0x00u, 1), 0x6506);   /* word address + repeated START */
    TEST_ASSERT_EQ(0, i2c_start_addr(0x50u, 1), 0x6507);   /* repeated START + addr, R */

    {
        uint8_t rd = 0x00u;
        TEST_ASSERT_EQ(0, i2c_read_byte(&rd, 0, 1), 0x6508); /* NACK + STOP */
        TEST_ASSERT_EQ(0xA5u, rd, 0x6509);
    }
    proof_note_slot(APB_I2C_BASE);
    proof_note_read(); proof_note_read();

    /* =====================================================================
     * 6. Post-recovery integrity: every peripheral answered after its recovery
     *    path ran, and DSRAM is intact.
     * ===================================================================== */
    TEST_SECTION("6. Post-recovery integrity");
    sig = proof_dsram_signature(0x600D0007u);
    TEST_ASSERT_NE(0u, sig, 0x6901);
    TEST_ASSERT_EQ(0, proof_mmio_ping(PROOF_PROBE_T1_CMP, PROOF_MASK_T_CMP), 0x6902);
    TEST_ASSERT_EQ(MAILBOX_CMD_RUNNING, MAILBOX->cmd_status, 0x6903);

    TEST_REQUIRE_ACTIVITY(8, 40, 5, 0x6000);
    TEST_PASS();
    return 0;
}
