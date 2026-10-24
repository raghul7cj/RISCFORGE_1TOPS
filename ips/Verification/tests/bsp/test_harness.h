/* =============================================================================
 * RISCFORGE 1TOPS — Bare-Metal C Test Harness (test_harness.h)
 * =============================================================================
 * Every stage must clear two bars before it may report PASS:
 *
 *   TEST_REQUIRE_ACTIVITY(...)  firmware-side proof that instructions retired
 *                               and bus transactions completed and returned
 *                               the data the test asked for;
 *   TEST_PASS()                 publishes the evidence and hands control to the
 *                               testbench, which independently re-checks the
 *                               same facts against its monitor counters.
 *
 * Neither half trusts the other, so a broken core, a broken bridge, a broken
 * monitor, and a broken test all fail loudly instead of producing a green run.
 * ============================================================================= */

#ifndef RISCFORGE_TEST_HARNESS_H_
#define RISCFORGE_TEST_HARNESS_H_

#include <stdint.h>
#include "mailbox.h"
#include "soc_regs.h"
#include "proof_activity.h"

#define TEST_START(id, name) do { \
    mailbox_init(id); \
    proof_activity_reset(); \
    mailbox_puts("[TEST START] "); \
    mailbox_puts(name); \
    mailbox_puts("\n"); \
} while (0)

#define TEST_SECTION(name) do { \
    mailbox_puts("--- "); \
    mailbox_puts(name); \
    mailbox_puts(" ---\n"); \
} while (0)

/* arg0 carries __LINE__ (a source location) — NOT __FILE__. Casting a string
 * pointer into the "addr" field produced a meaningless value in every
 * previous failure report, which is exactly the diagnostic you need at 3am. */
#define TEST_ASSERT(cond, err_code) do { \
    if (!(cond)) { \
        mailbox_puts("[FAIL] Assertion failed: " #cond "\n"); \
        mailbox_fail((uint32_t)(err_code), (uint32_t)(__LINE__), 0u, 0u); \
    } \
} while (0)

#define TEST_ASSERT_EQ(exp, got, err_code) do { \
    uint32_t _e = (uint32_t)(exp); \
    uint32_t _g = (uint32_t)(got); \
    if (_e != _g) { \
        mailbox_puts("[FAIL] Assert EQ: Expected != Got\n"); \
        mailbox_fail((uint32_t)(err_code), (uint32_t)(__LINE__), _e, _g); \
    } \
} while (0)

#define TEST_ASSERT_NE(unexp, got, err_code) do { \
    uint32_t _u = (uint32_t)(unexp); \
    uint32_t _g = (uint32_t)(got); \
    if (_u == _g) { \
        mailbox_puts("[FAIL] Assert NE: value must differ\n"); \
        mailbox_fail((uint32_t)(err_code), (uint32_t)(__LINE__), _u, _g); \
    } \
} while (0)

/*
 * Mandatory activity gate. `err_base` should be the stage's error-code prefix
 * (e.g. 0x1000) so a failure report names both the stage and the specific
 * activity shortfall.
 */
#define TEST_REQUIRE_ACTIVITY(min_dsram, min_mmio, min_slots, err_base) \
    (void)proof_verify_activity((min_dsram), (min_mmio), (min_slots), (err_base))

/*
 * PASS is terminal. It publishes the firmware evidence, prints it, and parks
 * in WFI for the testbench to judge. The TB independently requires
 *   total_retired_instr > 0, AXI beats > 0, APB transfers > 0, n_find == 0
 * before it honours this word.
 */
#define TEST_PASS() do { \
    proof_publish(); \
    proof_report(); \
    mailbox_puts("[TEST PASS] All checks verified.\n"); \
    mailbox_pass(); \
} while (0)

#define TEST_FAIL(err_code) do { \
    mailbox_fail((uint32_t)(err_code), (uint32_t)(__LINE__), 0u, 0u); \
} while (0)

/* Busy wait loop with hardware cycle timeout */
static inline int wait_with_timeout(volatile uint32_t *reg, uint32_t mask, uint32_t exp_val, uint32_t max_cycles) {
    uint32_t start = csr_read_mcycle();
    while ((*reg & mask) != exp_val) {
        if ((csr_read_mcycle() - start) > max_cycles) {
            return -1; /* Timeout */
        }
    }
    return 0; /* OK */
}

#endif /* RISCFORGE_TEST_HARNESS_H_ */
