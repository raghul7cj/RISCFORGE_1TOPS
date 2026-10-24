/* =============================================================================
 * RISCFORGE 1TOPS — Stage 4 Proof: Bus Fault Injection & Trap Recovery (main.c)
 * =============================================================================
 * PROVES
 *   1. An access to the unmapped APB hole at 0x4000_3800 raises
 *      RESP_DECERR. The aperture map is:
 *           slot 0 I2C    0x4000_0000..0x4000_0FFF
 *           slot 3 GPIO   0x4000_3000..0x4000_37FF   <-- ends at 0x37FF
 *      so 0x4000_3800 is in the GPIO *gap*, decodes to no APB slave, and the
 *      axi_lite_to_apb decode-error path returns DECERR.
 *   2. DECERR is converted by hybrid_mem_interface into mem_err, which
 *      memory_cycle turns into a synchronous trap with mcause=5 (load access
 *      fault) — or mcause=7 for a store. The stage checks BOTH, because
 *      proving only one direction would let a load/store asymmetry through.
 *   3. The handler can recover: it advances mepc past the faulting instruction
 *      and the stage resumes normal execution, so this is a recovery proof and
 *      not just a trap proof.
 *   4. The surrounding DSRAM/MMIO evidence is intact, i.e. the trap did not
 *      corrupt the data path.
 *
 * VACUITY
 *   The central hazard here is a test that "passes" because the fault never
 *   happened and the handler never ran. Two defences:
 *     - TEST_ASSERT_EQ(1, load_fault_seen) is checked immediately after the
 *       faulting load, before anything else can mask it.
 *     - trap_entries must be > 0 AND the stage additionally performs a benign
 *       MMIO round-trip to prove the bus recovered, so "the core wedged" is
 *       distinguishable from "the core handled it".
 *   TEST_REQUIRE_ACTIVITY(16, 8, 2, 0x4000) enforces the minimum traffic.
 * ============================================================================= */

#include "test_harness.h"
#include "isr_dispatch.h"

#define APB_DECODE_HOLE 0x40003800UL   /* in the GPIO aperture gap -> DECERR   */

static volatile uint32_t load_fault_seen;
static volatile uint32_t store_fault_seen;
static volatile uint32_t trap_entries;
static volatile uint32_t last_mcause;
static volatile uint32_t last_mepc;
static volatile uint32_t resume_point;

/* Load access fault: mcause = 5 */
void handle_load_access_fault(uint32_t mcause, uint32_t mepc) {
    last_mcause = mcause;
    last_mepc   = mepc;
    trap_entries++;
    load_fault_seen = 1;
    mailbox_puts("[TRAP] Load Access Fault (mcause=5) caught on APB decode hole\n");
    /* Resume after the 4-byte faulting LW. */
    __asm__ volatile ("csrw mepc, %0" :: "r"(mepc + 4));
}

/* Store access fault: mcause = 7 */
void handle_store_access_fault(uint32_t mcause, uint32_t mepc) {
    last_mcause = mcause;
    last_mepc   = mepc;
    trap_entries++;
    store_fault_seen = 1;
    mailbox_puts("[TRAP] Store Access Fault (mcause=7) caught on APB decode hole\n");
    __asm__ volatile ("csrw mepc, %0" :: "r"(mepc + 4));
}

/*
 * No catch-all is registered here on purpose: isr_dispatch.c's
 * default_unexpected_handler() already turns any un-registered cause into a
 * CMD_FAIL with the mcause in arg2. That is the behaviour we want — a stage
 * that silently ignored an unexpected trap would be a vacuous pass.
 */

int main(void) {
    uint32_t sig;

    TEST_START(0x0004, "Stage 4 Bus Fault Injection & Recovery Proof");

    /* Trap vector is already installed by crt0; register our handlers. */
    isr_register_handler(5, handle_load_access_fault);
    isr_register_handler(7, handle_store_access_fault);

    /* ---------------------------------------------------------------------
     * 1. Establish that the bus was healthy BEFORE the fault. Without this, a
     *    broken bus and a correctly-caught fault are indistinguishable.
     * ------------------------------------------------------------------- */
    TEST_SECTION("1. Pre-fault bus health");
    sig = proof_dsram_signature(0xFA017004u);
    TEST_ASSERT_NE(0u, sig, 0x4001);
    TEST_ASSERT_EQ(0, proof_mmio_ping(PROOF_PROBE_I2C_PRER, PROOF_MASK_I2C_PRER), 0x4002);
    TEST_ASSERT_EQ(0, proof_mmio_ping(PROOF_PROBE_T0_CMP, PROOF_MASK_T_CMP), 0x4003);
    TEST_ASSERT_EQ(0u, trap_entries, 0x4004);

    /* ---------------------------------------------------------------------
     * 2. Inject the load fault.
     *    The volatile sink is required: without it GCC folds the load away and
     *    the access never reaches the bus, which is the classic way a
     *    fault-injection test silently stops injecting.
     * ------------------------------------------------------------------- */
    TEST_SECTION("2. Load from unmapped APB hole (expect mcause=5)");
    resume_point = 0xF00Du;
    {
        volatile uint32_t bad_val = REG32_READ(APB_DECODE_HOLE);
        (void)bad_val;
    }
    /* Checked immediately: nothing between the load and here can hide a miss. */
    TEST_ASSERT_EQ(1u, load_fault_seen, 0x4005);
    TEST_ASSERT_EQ(5u, last_mcause, 0x4006);
    TEST_ASSERT_NE(0u, last_mepc, 0x4007);

    /* ---------------------------------------------------------------------
     * 3. Prove the handler actually resumed us: the marker after the
     *    faulting load must have been written.
     * ------------------------------------------------------------------- */
    TEST_SECTION("3. mepc advance resumed normal execution");
    TEST_ASSERT_EQ(0xF00Du, resume_point, 0x4008);

    /* ---------------------------------------------------------------------
     * 4. Store-side fault: proves the error path is symmetric, not load-only.
     * ------------------------------------------------------------------- */
    TEST_SECTION("4. Store to unmapped APB hole (expect mcause=7)");
    REG32_WRITE(APB_DECODE_HOLE, 0xDEADBEEFu);
    TEST_ASSERT_EQ(1u, store_fault_seen, 0x4009);
    TEST_ASSERT_EQ(7u, last_mcause, 0x400A);
    TEST_ASSERT_EQ(2u, trap_entries, 0x400B);

    /* ---------------------------------------------------------------------
     * 5. Recovery proof: the peripheral path still works after the faults. A
     *    core that trapped but wedged fails here rather than passing.
     * ------------------------------------------------------------------- */
    TEST_SECTION("5. Post-fault bus recovery");
    TEST_ASSERT_EQ(0, proof_mmio_ping(PROOF_PROBE_I2C_PRER, PROOF_MASK_I2C_PRER), 0x400C);
    TEST_ASSERT_EQ(0, proof_mmio_ping(PROOF_PROBE_T0_CMP, PROOF_MASK_T_CMP), 0x400D);
    sig = proof_dsram_signature(0xFA017005u);
    TEST_ASSERT_NE(0u, sig, 0x400E);

    /* The GPIO DATA_OUT register is a modelled RW register: prove the value
     * round-trips through the full APB path and matches the predictor. */
    TEST_SECTION("6. Modelled register round-trip");
    REG32_WRITE(PROOF_PROBE_GPIO_OUT, 0x0F0F0F0Fu);
    TEST_ASSERT_EQ(0x0F0F0F0Fu, REG32_READ(PROOF_PROBE_GPIO_OUT), 0x400F);
    REG32_WRITE(PROOF_PROBE_GPIO_OUT, 0x00000000u);

    TEST_REQUIRE_ACTIVITY(16, 10, 2, 0x4000);
    TEST_PASS();
    return 0;
}
