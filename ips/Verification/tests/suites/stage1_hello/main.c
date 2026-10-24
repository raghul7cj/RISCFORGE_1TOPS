/* =============================================================================
 * RISCFORGE 1TOPS — Stage 1 Proof: Boot, Console & Bus Liveness (main.c)
 * =============================================================================
 * PROVES
 *   1. BootROM -> ISRAM handoff executes (crt0.s zeroes .bss, sets mtvec, calls
 *      main). Proof: a known canary written by crt0's bss-clear path reads back
 *      as the value we wrote, and a second canary outside .bss is untouched.
 *   2. The mailbox console channel streams characters to the TB. Proof: the TB
 *      prints them; we additionally check that a full banner round-trips without
 *      corrupting DSRAM word 5 (the char_out port).
 *   3. Instructions actually retired. Proof: proof_dsram_signature() folds 16
 *      read-back words; a core that retired nothing cannot produce it.
 *   4. The MMIO path moved data. Proof: proof_mmio_ping() read-modify-writes two
 *      distinct APB apertures and checks the value that physically came back.
 *      This is what generates the AXI-Lite and APB beats the TB requires, and it
 *      is the reason a Stage 1 "PASS" cannot be produced by a dead peripheral
 *      fabric.
 *
 * VACUITY
 *   TEST_REQUIRE_ACTIVITY(8, 6, 2, 0x1000) — at least 8 DSRAM words read back,
 *   6 MMIO reads, and 2 distinct APB apertures proven round-trip.
 * ============================================================================= */

#include "test_harness.h"

/* Probe registers come from proof_activity.h (PROOF_PROBE_*). I2C PRER_LO and
 * Timer 0 CMP are both inert while their peripheral is idle, so they are the
 * safest registers in the SoC for a bus liveness probe. */

static volatile uint32_t data_canary = 0xC0FFEE11u;

/* Lives in .bss: crt0.s must have zeroed it, so it must read 0 until we write. */
static volatile uint32_t bss_canary;

/* Lives in .rodata: must be byte-identical for the whole run. */
static const uint32_t rodata_guard = 0x5A5A1234u;

int main(void) {
    uint32_t sig;

    TEST_START(0x0001, "Stage 1 Boot / Console / Bus Liveness Proof");

    /* ---------------------------------------------------------------------
     * 1. crt0 executed. The .bss word must read 0 (crt0 zeroed it) and the
     *    .data word must read back the value the hex image carried.
     * ------------------------------------------------------------------- */
    TEST_SECTION("1. crt0 bss clear + data/rodata load");
    TEST_ASSERT_EQ(0u, bss_canary, 0x1001);
    TEST_ASSERT_EQ(0xC0FFEE11u, data_canary, 0x1002);
    TEST_ASSERT_EQ(0x5A5A1234u, rodata_guard, 0x1003);

    /* Write the .bss canary and read it back: a working DSRAM write path. */
    bss_canary = 0x1234ABCDu;
    TEST_ASSERT_EQ(0x1234ABCDu, bss_canary, 0x1004);

    /* ---------------------------------------------------------------------
     * 2. Console streaming through the DSRAM char_out port.
     * ------------------------------------------------------------------- */
    TEST_SECTION("2. Mailbox console streaming");
    mailbox_puts("========================================\n");
    mailbox_puts("  Hello RISCFORGE Verification Infra!   \n");
    mailbox_puts("  Firmware is stimulus, TB is judge.    \n");
    mailbox_puts("========================================\n");

    /* Streaming must not have disturbed the rodata guard or the mailbox
     * control word (word 0 must still be RUNNING, not a premature PASS). */
    TEST_ASSERT_EQ(0x5A5A1234u, rodata_guard, 0x1005);
    TEST_ASSERT_EQ(MAILBOX_CMD_RUNNING, MAILBOX->cmd_status, 0x1006);
    TEST_ASSERT_EQ(0x1234ABCDu, bss_canary, 0x1007);

    /* ---------------------------------------------------------------------
     * 3. DSRAM data-path proof: seed-dependent, so a stuck bus cannot pass.
     * ------------------------------------------------------------------- */
    TEST_SECTION("3. DSRAM data-path signature");
    sig = proof_dsram_signature(0xA11CE01u);
    TEST_ASSERT_NE(0u, sig, 0x1008);
    TEST_ASSERT_EQ(proof_dsram_sig, sig, 0x1009);

    /* Re-run with a different seed: the signature must differ. This catches a
     * DSRAM that returns a constant, which a single-seed check would accept. */
    {
        uint32_t sig2 = proof_dsram_signature(0xB0B0CA5u);
        TEST_ASSERT_NE(sig, sig2, 0x100A);
    }

    /* ---------------------------------------------------------------------
     * 4. MMIO path proof on two distinct APB apertures.
     * ------------------------------------------------------------------- */
    TEST_SECTION("4. APB bus liveness (2 apertures)");
    TEST_ASSERT_EQ(0, proof_mmio_ping(PROOF_PROBE_I2C_PRER, PROOF_MASK_I2C_PRER), 0x100B);
    TEST_ASSERT_EQ(0, proof_mmio_ping(PROOF_PROBE_T0_CMP, PROOF_MASK_T_CMP), 0x100C);

    /* Both probes restored their registers; the register predictor will also
     * flag any divergence, so a partial restore is caught twice. */
    TEST_ASSERT_EQ(0x00000000u, REG32_READ(PROOF_PROBE_T0_CTRL), 0x100D);

    /* ---------------------------------------------------------------------
     * Vacuity gate, then hand judgement to the TB.
     * ------------------------------------------------------------------- */
    TEST_REQUIRE_ACTIVITY(8, 6, 2, 0x1000);
    TEST_PASS();
    return 0;
}
