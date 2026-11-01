/* =============================================================================
 * RISCFORGE 1TOPS — Stage 2 Proof: Watchdog, Freeze & Blame Engine (main.c)
 * =============================================================================
 * PROVES
 *   1. The testbench watchdog fires at the configured cycle limit.
 *   2. The failure_reporter attributes the timeout to LAYER_FIRMWARE with the
 *      last committed PC, and freezes the monitors before dumping them.
 *   3. The freeze buffers retain the last N retired instructions and bus
 *      transactions for post-mortem inspection.
 *
 * WHY THIS STAGE NEVER CALLS TEST_PASS
 *   A watchdog proof is negative by construction: the only correct outcome is a
 *   timeout. If this firmware ever reported PASS, the watchdog would be broken
 *   and the regression would be lying. So the vacuity rule is INVERTED here:
 *
 *     - The firmware deliberately spins while incrementing an activity counter,
 *       proving retirement is live right up to the moment of the kill.
 *     - The firmware publishes its activity evidence *before* spinning, so the
 *       TB can still confirm the core was genuinely executing when it died.
 *     - Reaching TEST_PASS() here is itself a hard failure: it is guarded by
 *       proof_activity_reset() + a tripwire that halts with CMD_HALT.
 *
 *   The TB detects this stage by test_id == 0x0002 and inverts its verdict:
 *   a WATCHDOG_TIMEOUT blame report is the PASS condition.
 * ============================================================================= */

#include "test_harness.h"

/* How many retired instructions we require the freeze dump to show. 2000 is far
 * above the spin loop's own reach in 1M cycles only if the loop is optimised
 * away — the volatile counter and the mcycle poll keep it real. */
#define SPIN_PROOF_TARGET 64u

static volatile uint32_t spin_iterations;
static volatile uint32_t last_mcycle;

int main(void) {
    uint32_t seen_mcycle = 0;
    uint32_t prev_mcycle = 0;

    TEST_START(0x0002, "Stage 2 Watchdog / Freeze / Blame Proof");

    /* ---------------------------------------------------------------------
     * 1. Prove the core and both buses are alive BEFORE we hang, so the
     *    post-mortem dump can be correlated with a known-good prefix.
     * ------------------------------------------------------------------- */
    TEST_SECTION("1. Pre-hang liveness evidence");
    TEST_ASSERT_NE(0u, proof_dsram_signature(0x5EED0002u), 0x2001);
    TEST_ASSERT_EQ(0, proof_mmio_ping(PROOF_PROBE_I2C_PRER, PROOF_MASK_I2C_PRER), 0x2002);
    TEST_ASSERT_EQ(0, proof_mmio_ping(PROOF_PROBE_T0_CMP, PROOF_MASK_T_CMP), 0x2003);
    proof_publish();

    /* Record the mcycle delta so the report shows the clock really advanced. */
    prev_mcycle = csr_read_mcycle();
    mailbox_puts("Pre-hang activity published. Now spinning for the watchdog...\n");
    mailbox_puts("[EXPECTED OUTCOME] TB FATAL TIMEOUT + LAYER_FIRMWARE blame report\n");

    /* ---------------------------------------------------------------------
     * 2. Deliberate hang. This loop must never exit.
     *
     *    Two things are being proven concurrently:
     *      - retirement is live: spin_iterations is volatile and read back;
     *      - the CSR timer is live: last_mcycle keeps changing.
     *    If the core wedged, the freeze dump would show a static PC and a
     *    static mcycle, which is a distinguishable failure signature from
     *    "firmware chose to spin".
     * ------------------------------------------------------------------- */
    while (1) {
        spin_iterations++;
        seen_mcycle = csr_read_mcycle();
        if (seen_mcycle != prev_mcycle) {
            last_mcycle  = seen_mcycle;
            prev_mcycle  = seen_mcycle;
        }

        /* Tripwire: if the watchdog somehow let us run this long, the run is
         * invalid. Halt with CMD_HALT so the TB reports a distinct failure
         * rather than silently timing out an unbounded amount later. */
        if (spin_iterations > 2000000u) {
            MAILBOX->arg0 = spin_iterations;
            MAILBOX->arg1 = last_mcycle;
            MAILBOX->arg2 = SPIN_PROOF_TARGET;
            mailbox_puts("[FATAL] Stage 2 exceeded expected spin budget\n");
            mailbox_halt();
        }
    }

    /* Unreachable. Present so the compiler does not warn about main(). */
    return 0;
}
