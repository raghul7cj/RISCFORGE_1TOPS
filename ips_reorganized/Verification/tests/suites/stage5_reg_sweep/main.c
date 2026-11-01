/* =============================================================================
 * RISCFORGE 1TOPS — Stage 5 Proof: Peripheral Register Reset Sweep (main.c)
 * =============================================================================
 * PROVES
 *   Every APB aperture decodes, answers a 32-bit read, and returns the value
 *   the RTL actually resets to — checked against the RTL source rather than
 *   against a wish list:
 *
 *     I2C    CTR  (0x08) = 0x00        apb_i2c.sv:75  r_ctrl <= 'h0
 *     T0/T1  CTRL (0x04) = 0x00        timer.sv:139   regs_q <= '{default: 32'b0}
 *     T0/T1  VAL  (0x00) = 0x00        timer.sv:139
 *     T0/T1  CMP  (0x08) = 0x00        timer.sv:139
 *     GPIO   EN   (0x080) = 0x00       gpio_reg_pkg: GPIO_GPIO_IN_RESVAL = 0
 *     GPIO   OUT  (0x180) = 0x00       gpio_reg_pkg: GPIO_GPIO_SET_RESVAL  = 0
 *     SPI    CLKD (0x004) = 0x00       spi_master_apb_if.sv:109 spi_clk_div <= '0
 *     UART   LSR  (0x014)              NOT HARD-CODED - see note (b)
 *
 *   Notes on what is deliberately NOT asserted:
 *   (a) GPIO offsets 0x000 and 0x380 are skipped. The register_predictor
 *       models 0x000 as INTRPT_STATUS_W1C and 0x380 as an interrupt-enable
 *       register, but gpio_reg_pkg puts INTRPT_STATUS at 0x580. Those two
 *       offsets are a known predictor/RTL disagreement; touching them would
 *       turn a real hardware question into a confusing false failure. Logged
 *       as a checker defect, not papered over here.
 *   (b) UART LSR is only checked for read-stability. The OBI UART RTL that
 *       implements LSR (obi_uart_register.sv) is absent from the tree, so its
 *       reset value cannot be confirmed from source. Asserting an unverified
 *       constant here would be exactly the kind of guess that makes a
 *       regression lie. Once the RTL is restored, pin the value and move this
 *       to a strict equality check.
 *
 * VACUITY
 *   The sweep *is* the activity: every expectation below is a value that could
 *   only come back if the address decoded, the APB slave answered, and the read
 *   data path delivered. The gate then cross-checks the counts against the TB.
 *   TEST_REQUIRE_ACTIVITY(8, 24, 6, 0x5000) — all six APB apertures proven.
 * ============================================================================= */

#include "test_harness.h"
#include "gpio_driver.h"
#include "spi_driver.h"
#include "uart_driver.h"
#include "timer_driver.h"
#include "i2c_driver.h"

/* Probe register addresses and masks come from proof_activity.h (PROOF_PROBE_*).
 * Keeping them there means the "safe to read-modify-write" knowledge lives next
 * to the code that actually performs the write. */

/* GPIO offsets 0x000 and 0x380 are deliberately never touched - see note (a) in
 * the header comment above. */

int main(void) {
    uint32_t sig;
    uint32_t r1, r2;

    TEST_START(0x0005, "Stage 5 Peripheral Register Reset Sweep");

    /* ---------------------------------------------------------------------
     * 1. DSRAM sanity: the sweep is meaningless if the data path is dead, and
     *    it separates a DSRAM fault from a peripheral fault in the report.
     * ------------------------------------------------------------------- */
    TEST_SECTION("0. DSRAM data-path sanity");
    sig = proof_dsram_signature(0x5EE50005u);
    TEST_ASSERT_NE(0u, sig, 0x5001);

    /* ---------------------------------------------------------------------
     * 2. I2C (APB slot 0, base 0x4000_0000)
     * ------------------------------------------------------------------- */
    TEST_SECTION("1. I2C aperture");
    r1 = REG32_READ(APB_I2C_BASE + I2C_CTR_OFFSET);
    r2 = REG32_READ(APB_I2C_BASE + I2C_CTR_OFFSET);
    TEST_ASSERT_EQ(0x00000000u, r1, 0x5101);
    TEST_ASSERT_EQ(r1, r2, 0x5102); /* stable across reads */
    TEST_ASSERT_EQ(0, proof_mmio_ping(PROOF_PROBE_I2C_PRER, PROOF_MASK_I2C_PRER), 0x5103);

    /* ---------------------------------------------------------------------
     * 3. Timer 0 / Timer 1 (APB slots 1 and 5)
     * ------------------------------------------------------------------- */
    TEST_SECTION("2. Timer 0 and Timer 1 apertures");
    r1 = REG32_READ(APB_TIMER0_BASE + TIMER_CTRL_OFFSET);
    r2 = REG32_READ(APB_TIMER0_BASE + TIMER_VAL_OFFSET);
    TEST_ASSERT_EQ(0x00000000u, r1, 0x5201);
    TEST_ASSERT_EQ(0x00000000u, r2, 0x5202);
    TEST_ASSERT_EQ(0x00000000u, REG32_READ(APB_TIMER0_BASE + TIMER_CMP_OFFSET), 0x5203);

    r1 = REG32_READ(APB_TIMER1_BASE + TIMER_CTRL_OFFSET);
    r2 = REG32_READ(APB_TIMER1_BASE + TIMER_VAL_OFFSET);
    TEST_ASSERT_EQ(0x00000000u, r1, 0x5204);
    TEST_ASSERT_EQ(0x00000000u, r2, 0x5205);
    TEST_ASSERT_EQ(0x00000000u, REG32_READ(APB_TIMER1_BASE + TIMER_CMP_OFFSET), 0x5206);

    TEST_ASSERT_EQ(0, proof_mmio_ping(PROOF_PROBE_T0_CMP, PROOF_MASK_T_CMP), 0x5207);
    TEST_ASSERT_EQ(0, proof_mmio_ping(PROOF_PROBE_T1_CMP, PROOF_MASK_T_CMP), 0x5208);

    /* ---------------------------------------------------------------------
     * 4. GPIO (APB slot 3). Only the two registers the predictor models, plus
     *    a direction/read/write round-trip.
     * ------------------------------------------------------------------- */
    TEST_SECTION("3. GPIO aperture");
    TEST_ASSERT_EQ(0x00000000u, REG32_READ(APB_GPIO_BASE + GPIO_EN_OFFSET), 0x5301);
    TEST_ASSERT_EQ(0x00000000u, REG32_READ(APB_GPIO_BASE + GPIO_OUT_OFFSET), 0x5302);

    /* All pins as inputs, then confirm the direction register took the write. */
    gpio_set_direction(0x00000000u);
    TEST_ASSERT_EQ(0x00000000u, REG32_READ(APB_GPIO_BASE + GPIO_EN_OFFSET), 0x5303);

    /* All pins as outputs. GPIOCount is 32, so the full mask is meaningful;
     * gpio_out is modelled RW by the predictor, so this must read back. */
    gpio_set_direction(0xFFFFFFFFu);
    TEST_ASSERT_EQ(0xFFFFFFFFu, REG32_READ(APB_GPIO_BASE + GPIO_EN_OFFSET), 0x5304);

    gpio_write(0xA5A5A5A5u);
    TEST_ASSERT_EQ(0xA5A5A5A5u, REG32_READ(APB_GPIO_BASE + GPIO_OUT_OFFSET), 0x5305);
    gpio_write(0x00000000u);
    TEST_ASSERT_EQ(0x00000000u, REG32_READ(APB_GPIO_BASE + GPIO_OUT_OFFSET), 0x5306);

    /* ---------------------------------------------------------------------
     * 5. SPI master (APB slot 4). NOTE spi_clk_div is only 8 bits wide
     *    (spi_master_apb_if.sv:42) while the predictor shadows 32, so any
     *    write above 0xFF would read back truncated and trip the predictor on
     *    a correct design. Keep every SPI value 8-bit.
     * ------------------------------------------------------------------- */
    TEST_SECTION("4. SPI master aperture");
    TEST_ASSERT_EQ(0x00000000u, REG32_READ(APB_SPI_BASE + SPI_CLKDIV_OFFSET), 0x5401);

    spi_init(0x04u);
    TEST_ASSERT_EQ(0x00000004u, REG32_READ(APB_SPI_BASE + SPI_CLKDIV_OFFSET), 0x5402);
    TEST_ASSERT_EQ(0, proof_mmio_ping(APB_SPI_BASE + SPI_CLKDIV_OFFSET,
                                      PROOF_MASK_SPI_CLKDIV), 0x5403);
    TEST_ASSERT_EQ(0x00000004u, REG32_READ(APB_SPI_BASE + SPI_CLKDIV_OFFSET), 0x5404);

    /* ---------------------------------------------------------------------
     * 6. UART (APB slot 2). Read-stability only — see note (b).
     *    The LSR is also a genuine liveness signal: a dead APB slave holds
     *    PRDATA at its last value, so a single stable read is not enough, but
     *    a *sequence* of different offsets returning their distinct reset
     *    values is. LCR and MCR both reset to 0, so we additionally program and
     *    read back LCR, which the predictor models and which is real hardware
     *    state rather than a constant.
     * ------------------------------------------------------------------- */
    TEST_SECTION("5. UART aperture");
    r1 = REG32_READ(APB_UART_BASE + UART_LSR_OFFSET);
    r2 = REG32_READ(APB_UART_BASE + UART_LSR_OFFSET);
    TEST_ASSERT_EQ(r1, r2, 0x5501);

    TEST_ASSERT_EQ(0x00000000u, REG32_READ(APB_UART_BASE + UART_LCR_OFFSET), 0x5502);
    TEST_ASSERT_EQ(0x00000000u, REG32_READ(APB_UART_BASE + UART_MCR_OFFSET), 0x5503);

    /* Program the line control register and read it back. This is real,
     * predictor-modelled state and proves the write path independently of the
     * THRE/TEMT bit values. */
    REG32_WRITE(APB_UART_BASE + UART_LCR_OFFSET, UART_LCR_8N1);
    TEST_ASSERT_EQ((uint32_t)UART_LCR_8N1,
                   REG32_READ(APB_UART_BASE + UART_LCR_OFFSET), 0x5504);
    REG32_WRITE(APB_UART_BASE + UART_LCR_OFFSET, 0x00000000u);
    TEST_ASSERT_EQ(0x00000000u, REG32_READ(APB_UART_BASE + UART_LCR_OFFSET), 0x5505);

    /* ---------------------------------------------------------------------
     * 7. Post-sweep integrity: the sweep must not have corrupted DSRAM, and
     *    the mailbox control word must still be RUNNING.
     * ------------------------------------------------------------------- */
    TEST_SECTION("6. Post-sweep integrity");
    sig = proof_dsram_signature(0x5EE50006u);
    TEST_ASSERT_NE(0u, sig, 0x5901);
    TEST_ASSERT_EQ(MAILBOX_CMD_RUNNING, MAILBOX->cmd_status, 0x5902);

    /* Vacuity gate: all six APB apertures proven, high MMIO read count. */
    TEST_REQUIRE_ACTIVITY(8, 24, 6, 0x5000);
    TEST_PASS();
    return 0;
}
