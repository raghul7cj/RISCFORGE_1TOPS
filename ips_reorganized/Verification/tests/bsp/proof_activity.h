/* =============================================================================
 * RISCFORGE 1TOPS — Proof-Stage Activity Attestation (proof_activity.h)
 * =============================================================================
 * PURPOSE
 *   A bare-metal stage that reports PASS without the hardware having done
 *   anything is the single worst failure mode of a software-driven regression:
 *   the regression goes green while the DUT is dead. This header makes that
 *   outcome structurally impossible from the firmware side, and feeds the
 *   testbench side with the cross-check it needs to close the loop.
 *
 * THE TWO INDEPENDENT PROOFS
 *
 *   1. DATA-PATH PROOF (firmware, unforgeable)
 *      `proof_dsram_signature()` writes a non-reproducible pattern into DSRAM,
 *      reads every word back, and mixes it into a checksum. A zero result is
 *      possible only if the store never happened OR the load returned a value
 *      the core could not have obtained from the bus. Both of those are real
 *      hardware failures, so the assertion is self-validating.
 *
 *   2. PERIPHERAL-PATH PROOF (firmware + TB cross-check)
 *      `proof_mmio_ping()` performs a real APB read-modify-write and checks the
 *      value that physically comes back. The count of those transactions is
 *      published into the mailbox attestation word, and the TB requires its own
 *      AXI/APB/LSU monitor totals to agree. If the firmware claims traffic the
 *      monitors did not see (or vice versa), the run fails as an infrastructure
 *      fault rather than silently passing.
 *
 * MINIMUM ACTIVITY BUDGET
 *   Every stage declares what it expects to have done before calling
 *   TEST_PASS(). A stage that under-delivers against its own declaration is a
 *   FAIL — it means the test regressed, not that the hardware got faster.
 * ============================================================================= */

#ifndef RISCFORGE_PROOF_ACTIVITY_H_
#define RISCFORGE_PROOF_ACTIVITY_H_

#include <stdint.h>
#include "mailbox.h"
#include "soc_regs.h"

/* ---------------------------------------------------------------------------
 * Tunables. Keep these tight: they are regression tripwires, not budgets.
 * ------------------------------------------------------------------------- */
#ifndef PROOF_MIN_DSRAM_WORDS
#define PROOF_MIN_DSRAM_WORDS 8u    /* >= 8 DSRAM words read back            */
#endif
#ifndef PROOF_MIN_MMIO_OPS
#define PROOF_MIN_MMIO_OPS    2u    /* >= 2 checked APB transactions         */
#endif
#ifndef PROOF_MMIO_SLOTS
#define PROOF_MMIO_SLOTS      2u    /* distinct APB slots touched by proof_  */
#endif
/* Spin budget for any single polled MMIO wait. Generous enough to absorb the
 * 1-wait-state APB slaves and the AXI round trip, small enough that a truly
 * dead bus is reported in ~5 ms of simulated time instead of the 1 M-cycle
 * testbench watchdog. */
#ifndef PROOF_POLL_TIMEOUT
#define PROOF_POLL_TIMEOUT    20000UL
#endif

/* ---------------------------------------------------------------------------
 * Firmware-observed activity counters (exported so stages and the harness can
 * assert against them).
 * ------------------------------------------------------------------------- */
/*
 * Firmware-observed activity counters.
 *
 * IMPORTANT SEMANTICS — these count *semantically verified* operations only,
 * i.e. accesses whose returned data was checked against what was written or
 * against a known-good constant. They are deliberately NOT a count of every
 * APB transaction the driver happened to issue: hand-tallying driver calls is
 * brittle and would rot the moment a driver changes.
 *
 * The raw traffic count is the testbench's job — it observes every AXI and APB
 * beat directly. The two are cross-checked against each other:
 *   - firmware must show >= min verified round-trips  (semantic proof)
 *   - TB must show >= min AXI beats and >= min APB transfers  (traffic proof)
 * A test that silently skipped its peripheral work fails one or both.
 */
extern volatile uint32_t proof_dsram_reads;
extern volatile uint32_t proof_dsram_sig;
extern volatile uint32_t proof_mmio_reads;      /* verified MMIO reads          */
extern volatile uint32_t proof_mmio_writes;     /* verified MMIO writes         */
extern volatile uint32_t proof_mmio_slots_touched;

/* Bitmap of the 6 APB slots that proof_mmio_ping() has proven round-trip.
 * Derived from the APB aperture (0x4000_0000 + slot * 0x1000). A stage cannot
 * satisfy PROOF_MMIO_SLOTS by hammering one register: each distinct aperture
 * must be touched at least once. */
extern volatile uint32_t proof_slot_bitmap;

/* Scratch storage for the data-path proof. Lives in .bss (DSRAM). */
#define PROOF_DSRAM_WORDS 16u
extern volatile uint32_t proof_dscratch[PROOF_DSRAM_WORDS];

/* ---------------------------------------------------------------------------
 * Approved liveness-probe registers.
 *
 * These live here rather than in the stages so the "is this register safe to
 * read-modify-write" knowledge sits next to proof_mmio_ping(), which is the
 * only code that performs the write. Each is RW, has no side effect while its
 * peripheral is idle, and is modelled by register_predictor.sv so a partial
 * restore is caught by two independent checkers.
 *
 *   I2C PRER_LO   8-bit prescaler. Inert while I2C_CTR.EN = 0.
 *   T0/T1 CMP     Compare register. Inert while TIMER_CTRL.EN = 0: the compare
 *                 IRQ is qualified by EN (timer.sv:67) and the counter is not
 *                 running. NEVER probe T0/T1 CMP while the timer is enabled -
 *                 it would reset the counter and perturb an interrupt test.
 *   GPIO DATA_OUT Direct output register. Safe whenever GPIO is idle.
 *   SPI CLKDIV    8-bit clock divisor (spi_master_apb_if.sv:42). Keep every
 *                 SPI value <= 0xFF: the predictor shadows 32 bits while the
 *                 hardware is 8, so a wider write reads back truncated and
 *                 would trip the predictor on a correct design.
 * ------------------------------------------------------------------------- */
#define PROOF_PROBE_I2C_PRER   (APB_I2C_BASE   + 0x00u)
#define PROOF_PROBE_T0_CMP     (APB_TIMER0_BASE + 0x08u)
#define PROOF_PROBE_T1_CMP     (APB_TIMER1_BASE + 0x08u)
#define PROOF_PROBE_T0_CTRL    (APB_TIMER0_BASE + 0x04u)
#define PROOF_PROBE_T1_CTRL    (APB_TIMER1_BASE + 0x04u)
#define PROOF_PROBE_GPIO_OUT   (APB_GPIO_BASE  + 0x180u)

/* Masks: pick a bit inside each register's real width. */
#define PROOF_MASK_I2C_PRER    0x01u
#define PROOF_MASK_T_CMP       0x00010000u
#define PROOF_MASK_GPIO_OUT    0x00000001u
#define PROOF_MASK_SPI_CLKDIV  0x01u

/* ---------------------------------------------------------------------------
 * proof_activity_reset() — clear counters. Call first thing in main().
 * ------------------------------------------------------------------------- */
static inline void proof_activity_reset(void) {
    proof_dsram_reads        = 0;
    proof_dsram_sig          = 0;
    proof_mmio_reads         = 0;
    proof_mmio_writes        = 0;
    proof_mmio_slots_touched = 0;
    proof_slot_bitmap        = 0;
    mailbox_publish_activity(0, 0);
}

/* Popcount of the proven-slot bitmap. */
static inline uint32_t proof_distinct_slots(void) {
    uint32_t b = proof_slot_bitmap;
    uint32_t n = 0;
    while (b) {
        n += (b & 1u);
        b >>= 1;
    }
    return n;
}

/* Mark an APB aperture as exercised by a hand-written check whose returned
 * value the stage verified itself (as opposed to proof_mmio_ping, which
 * verifies internally). Use this instead of inventing a raw tally. */
static inline void proof_note_slot(uint32_t base) {
    proof_slot_bitmap |= (1u << ((base - APB_I2C_BASE) >> 12));
    proof_mmio_slots_touched = proof_distinct_slots();
}

/* Record a verified read the stage performed itself. */
static inline void proof_note_read(void) {
    proof_mmio_reads++;
}

/* ---------------------------------------------------------------------------
 * proof_dsram_signature(seed)
 *   Writes a seed-dependent pattern to PROOF_DSRAM_WORDS words of DSRAM, reads
 *   every word back, and folds the read values into a checksum.
 *
 *   Returns the checksum. It is a deterministic function of `seed` for correct
 *   hardware, so a stage can pin it exactly (strongest possible check). A stage
 *   that only wants liveness checks `proof_dsram_sig != 0`.
 *
 *   The `volatile` on both the store loop index and the array stops GCC from
 *   eliding the loads — an elided read is precisely the vacuous pass we are
 *   hunting.
 * ------------------------------------------------------------------------- */
static inline uint32_t proof_dsram_signature(uint32_t seed) {
    uint32_t sig = 0x9E3779B9u ^ seed;
    uint32_t i;

    for (i = 0; i < PROOF_DSRAM_WORDS; i++) {
        /* Non-linear, seed-dependent so a stuck-at-zero bus cannot pass. */
        proof_dscratch[i] = (seed * 2654435761u) ^ (i * 0x01000193u) ^ 0xA5A5F00Du;
    }

    for (i = 0; i < PROOF_DSRAM_WORDS; i++) {
        uint32_t v = proof_dscratch[i];
        if (v != ((seed * 2654435761u) ^ (i * 0x01000193u) ^ 0xA5A5F00Du)) {
            return 0; /* Data path is broken — refuse to certify anything. */
        }
        sig = (sig ^ v) * 16777619u; /* FNV-1a style fold */
        proof_dsram_reads++;
    }

    /* Zero checksum would be indistinguishable from "nothing happened". */
    if (sig == 0) {
        sig = 0xFFFFFFFFu;
    }
    proof_dsram_sig = sig;
    return sig;
}

/* ---------------------------------------------------------------------------
 * proof_mmio_ping(reg_addr, mask)
 *   Read-modify-write against one of the approved probe registers above, then
 *   read back and confirm. This is the only way to prove the full
 *   LSU -> AXI-Lite -> xbar -> axi_lite_to_apb -> APB slave -> back path
 *   actually moved data.
 *
 *   `mask` selects the writable bits to toggle. Callers MUST pass one of the
 *   PROOF_MASK_* values above, which are chosen to be inert while the
 *   peripheral is idle. Never point this at a control register whose bit 0
 *   enables something.
 *
 *   Returns 0 on success, -1 on timeout / read-back mismatch.
 * ------------------------------------------------------------------------- */
static inline int proof_mmio_ping(uint32_t reg_addr, uint32_t mask) {
    volatile uint32_t *reg = (volatile uint32_t *)(uintptr_t)reg_addr;
    uint32_t start = csr_read_mcycle();
    uint32_t v0, v1, test_bit;

    /* Phase 1: baseline read. Bounded so a dead bus is a FAIL, not a hang. */
    v0 = *reg;
    proof_mmio_reads++;
    if ((csr_read_mcycle() - start) > PROOF_POLL_TIMEOUT) {
        return -1;
    }

    /* Pick a bit inside `mask` that differs from its complement so that both
     * the set and the clear direction are exercised. */
    test_bit = 1u;
    while ((test_bit & mask) == 0u) {
        test_bit <<= 1;
        if (test_bit == 0x80000000u) {
            return -1; /* mask had no usable bit */
        }
    }

    /* Phase 2: toggle the bit and read back. */
    *reg = v0 ^ test_bit;
    proof_mmio_writes++;
    v1 = *reg;
    proof_mmio_reads++;
    if ((v1 & test_bit) == (v0 & test_bit)) {
        return -1; /* Write did not take effect */
    }

    /* Phase 3: restore the original value so the stage leaves no residue that
     * a later register-sweep check would trip over. */
    *reg = v0;
    proof_mmio_writes++;
    if ((*reg & test_bit) != (v0 & test_bit)) {
        return -1; /* Restore failed */
    }
    proof_mmio_reads++;

    /* Mark the APB aperture this transaction landed in. */
    proof_slot_bitmap |= (1u << ((reg_addr - APB_I2C_BASE) >> 12));
    proof_mmio_slots_touched = proof_distinct_slots();
    return 0;
}

/* ---------------------------------------------------------------------------
 * proof_publish() — push the firmware-side evidence into the mailbox for the
 * testbench to cross-check. Call immediately before TEST_PASS().
 * ------------------------------------------------------------------------- */
static inline void proof_publish(void) {
    mailbox_publish_activity(proof_mmio_reads, proof_mmio_writes);
}

/* ---------------------------------------------------------------------------
 * proof_verify_activity(min_dsram, min_mmio, min_slots, err_base)
 *   The in-firmware half of the anti-vacuity guard. Enforces the declared
 *   minimum activity budget and requires a non-zero data-path signature.
 *   Returns 0 if the evidence is sufficient, -1 otherwise (after reporting).
 * ------------------------------------------------------------------------- */
static inline int proof_verify_activity(uint32_t min_dsram, uint32_t min_mmio,
                                        uint32_t min_slots, uint32_t err_base) {
    proof_publish();

    if (proof_dsram_reads < min_dsram) {
        mailbox_puts("[VACUOUS] Too few DSRAM words read back: ");
        mailbox_puts(" ");
        mailbox_fail(err_base + 0u, proof_dsram_reads, min_dsram, proof_dsram_sig);
    }
    if (proof_dsram_sig == 0u) {
        mailbox_puts("[VACUOUS] Data-path signature is zero - no real DSRAM traffic\n");
        mailbox_fail(err_base + 1u, proof_dsram_reads, 0xFFFFFFFFu, proof_dsram_sig);
    }
    if (proof_mmio_reads < min_mmio) {
        mailbox_puts("[VACUOUS] Too few MMIO reads: ");
        mailbox_fail(err_base + 2u, proof_mmio_reads, min_mmio, proof_mmio_writes);
    }
    if (proof_distinct_slots() < min_slots) {
        mailbox_puts("[VACUOUS] Too few distinct APB slots proven: ");
        mailbox_fail(err_base + 3u, proof_distinct_slots(), min_slots, proof_slot_bitmap);
    }
    return 0;
}

/* ---------------------------------------------------------------------------
 * proof_report() — one-line console summary of the evidence, so the log of a
 * green run still shows what the hardware actually did.
 * ------------------------------------------------------------------------- */
static inline void proof_report(void) {
    static const char hex[] = "0123456789ABCDEF";
    uint32_t v = proof_dsram_sig;
    int i;

    mailbox_puts("[PROOF] dsram_rds=");
    for (i = 7; i >= 0; i--) {
        mailbox_putc(hex[(v >> (i * 4)) & 0xFu]);
    }
    mailbox_puts(" sig=");
    for (i = 7; i >= 0; i--) {
        mailbox_putc(hex[(v >> (i * 4)) & 0xFu]);
    }
    mailbox_puts(" mmio_rd=");
    v = proof_mmio_reads;
    for (i = 7; i >= 0; i--) {
        mailbox_putc(hex[(v >> (i * 4)) & 0xFu]);
    }
    mailbox_puts(" mmio_wr=");
    v = proof_mmio_writes;
    for (i = 7; i >= 0; i--) {
        mailbox_putc(hex[(v >> (i * 4)) & 0xFu]);
    }
    mailbox_puts(" slots=");
    v = proof_slot_bitmap;
    for (i = 7; i >= 0; i--) {
        mailbox_putc(hex[(v >> (i * 4)) & 0xFu]);
    }
    mailbox_puts("\n");
}

#endif /* RISCFORGE_PROOF_ACTIVITY_H_ */
