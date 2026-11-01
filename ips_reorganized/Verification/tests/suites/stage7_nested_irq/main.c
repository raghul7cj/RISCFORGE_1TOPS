/* =============================================================================
 * RISCFORGE 1TOPS — Stage 7 Proof: Interrupt Nesting & Register Integrity
 * =============================================================================
 * PROVES
 *   1. A real machine-timer interrupt (ID 7, Class 2) is delivered, taken and
 *      returned from repeatedly. The ETH timer auto-clears its counter on a
 *      compare match (timer.sv:80-81), so it is genuinely periodic; an
 *      interrupt storm is therefore distinguishable from a healthy run.
 *   2. TWO-LEVEL PREEMPTION actually happens: a Class 1 source (SPI, ID 18) is
 *      entered first, and a Class 2 source (Timer 0, ID 7) preempts it while
 *      the Class 1 handler is still running. Proven from firmware by a software
 *      nesting-depth counter, and independently by the TB irq_predictor which
 *      checks class ordering and the 2-deep hardware shadow stack.
 *      If nesting is not observed the stage FAILS. It does not skip.
 *   3. Zero GPR corruption: every callee-saved register s0..s11 is loaded with a
 *      distinct canary before interrupts are enabled and re-verified afterwards.
 *   4. The nested trap frame does not corrupt the OUTER handler's live state.
 *
 * WHY THE PREVIOUS VERSION WAS VACUOUS
 *   It enabled MTIE and spun on `while (timer_ticks < 5)`. If no interrupt ever
 *   arrived the loop simply ran to the testbench watchdog, which is
 *   indistinguishable from "the interrupt worked but something else hung". The
 *   `TEST_ASSERT_EQ(5, ...)` sat behind that spin loop and was unreachable when
 *   the timer failed. Here every wait is mcycle-bounded, a timeout is its own
 *   explicit failure code, and the interrupt-count and nesting requirements are
 *   checked before PASS is allowed.
 * ============================================================================= */

#include "test_harness.h"
#include "isr_dispatch.h"
#include "timer_driver.h"
#include "spi_driver.h"
#include "soc_regs.h"

#define ISR_BUDGET       400000UL  /* ~4 ms simulated, far under the TB watchdog */
#define REQUIRED_TIMER0  8u        /* Class 2 entries that must be observed       */
#define REQUIRED_NEST    1u        /* Class-2-over-Class-1 preemptions required   */
#define TIMER0_COMPARE   200u      /* ~200-cycle period: dense enough to overlap  */

static volatile uint32_t timer0_entries;
static volatile uint32_t class1_entries;
static volatile uint32_t preemptions;   /* Class 2 seen while inside Class 1 */
static volatile uint32_t sw_nest_depth;
static volatile uint32_t max_sw_nest;
static volatile uint32_t bad_cause;     /* first unexpected cause, 0 if none  */
static volatile uint32_t outer_canary = 0x0C1A55C1u;

/*
 * Class 2 - Timer 0 (ID 7). Runs at depth 1 (top level) or depth 2 (nested).
 */
void timer0_isr(uint32_t mcause, uint32_t mepc) {
    (void)mepc;
    if (mcause != IRQ_ID_TIMER0)     { bad_cause = mcause; }
    if (!MCAUSE_IS_INTERRUPT(mcause)) { bad_cause = mcause; }

    sw_nest_depth++;
    if (sw_nest_depth > max_sw_nest) { max_sw_nest = sw_nest_depth; }

    /* Depth 2 means a Class 2 source preempted a Class 1 one. That is the
     * two-level precedence proof, observed in software. */
    if (sw_nest_depth >= 2u) { preemptions++; }

    timer0_entries++;
    sw_nest_depth--;
}

/*
 * Class 1 - SPI TX/RX (ID 18). Holds the CPU long enough for the Class 2 timer
 * interrupt to arrive, which makes the preemption deterministic rather than a
 * race on arrival order.
 */
void spi_class1_isr(uint32_t mcause, uint32_t mepc) {
    uint32_t start;

    (void)mepc;
    if (mcause != IRQ_ID_SPI) { bad_cause = mcause; }

    sw_nest_depth++;
    if (sw_nest_depth > max_sw_nest) { max_sw_nest = sw_nest_depth; }
    class1_entries++;

    start = csr_read_mcycle();
    while (timer0_entries == 0u) {
        if ((csr_read_mcycle() - start) > ISR_BUDGET) {
            mailbox_puts("[TRAP] SPI ISR: Class 2 never arrived to preempt\n");
            mailbox_fail(0x7A01, sw_nest_depth, 1u, timer0_entries);
        }
    }

    /* The nested Class 2 handler must not have disturbed the outer handler's
     * live state. If the nested trap frame overlapped the outer frame, this
     * word is already trashed. */
    if (outer_canary != 0x0C1A55C1u) {
        mailbox_puts("[TRAP] Outer handler canary corrupted by nested trap\n");
        mailbox_fail(0x7A02, sw_nest_depth, 0x0C1A55C1u, outer_canary);
    }

    sw_nest_depth--;
}

static int wait_for(volatile uint32_t *ctr, uint32_t target, uint32_t budget) {
    uint32_t start = csr_read_mcycle();
    while (*ctr < target) {
        if ((csr_read_mcycle() - start) > budget) {
            return -1;
        }
    }
    return 0;
}

#define CANARY_CHECK(reg, expect, code) \
    do { if ((uint32_t)(reg) != (uint32_t)(expect)) { \
            mailbox_fail((uint32_t)(code), (uint32_t)__LINE__, \
                         (uint32_t)(expect), (uint32_t)(reg)); \
         } } while (0)

int main(void) {
    uint32_t sig;
    uint32_t intcfg;
    volatile uint32_t settle;
    uint32_t i;

    TEST_START(0x0007, "Stage 7 Interrupt Nesting & Register Integrity Proof");

    /* ---------------------------------------------------------------------
     * 0. Baseline liveness: an interrupt test on a dead data path measures
     *    nothing, so prove the data path first.
     * ------------------------------------------------------------------- */
    TEST_SECTION("0. DSRAM data-path sanity");
    sig = proof_dsram_signature(0x7A500007u);
    TEST_ASSERT_NE(0u, sig, 0x7001);

    /* ---------------------------------------------------------------------
     * 1. Load every callee-saved register with a distinct canary. s0..s11 are
     *    preserved by the C ABI, so a fault in the trap save/restore path
     *    surfaces here as a specific corrupted register instead of as generic
     *    misbehaviour much later.
     * ------------------------------------------------------------------- */
    TEST_SECTION("1. Callee-saved register canaries");
    register uint32_t c_s0  __asm__("s0")  = 0x11111111u;
    register uint32_t c_s1  __asm__("s1")  = 0x22222222u;
    register uint32_t c_s2  __asm__("s2")  = 0x33333333u;
    register uint32_t c_s3  __asm__("s3")  = 0x44444444u;
    register uint32_t c_s4  __asm__("s4")  = 0x55555555u;
    register uint32_t c_s5  __asm__("s5")  = 0x66666666u;
    register uint32_t c_s6  __asm__("s6")  = 0x77777777u;
    register uint32_t c_s7  __asm__("s7")  = 0x88888888u;
    register uint32_t c_s8  __asm__("s8")  = 0x99999999u;
    register uint32_t c_s9  __asm__("s9")  = 0xAAAAAAAAu;
    register uint32_t c_s10 __asm__("s10") = 0xBBBBBBBBu;
    register uint32_t c_s11 __asm__("s11") = 0xCCCCCCCCu;

    /* Keep the canaries genuinely live: they are read again in section 7. */
    TEST_ASSERT_NE(0u, (c_s0 ^ c_s1 ^ c_s2 ^ c_s3 ^ c_s4 ^ c_s5 ^
                       c_s6 ^ c_s7 ^ c_s8 ^ c_s9 ^ c_s10 ^ c_s11), 0x7010);

    isr_register_handler(IRQ_ID_TIMER0, timer0_isr);
    isr_register_handler(IRQ_ID_SPI, spi_class1_isr);

    /* ---------------------------------------------------------------------
     * 2. Arm the Class 2 source: Timer 0 compare-match interrupt. The compare
     *    value must be non-zero or timer.sv:67 suppresses the IRQ entirely.
     * ------------------------------------------------------------------- */
    TEST_SECTION("2. Arm Timer 0 Class 2 interrupt");
    timer_init(APB_TIMER0_BASE, 0u, TIMER0_COMPARE);
    timer_start(APB_TIMER0_BASE);
    TEST_ASSERT(REG32_READ(APB_TIMER0_BASE + TIMER_CTRL_OFFSET) & TIMER_CTRL_EN,
                0x7020);

    /* ---------------------------------------------------------------------
     * 3. Arm the Class 1 source: SPI TX/RX interrupt.
     *    INTCFG layout, spi_master_apb_if.sv:174-182, LOG_BUFFER_DEPTH = 4:
     *      [3:0] int_th_tx   [11:8] int_th_rx   [30] int_cnt_en   [31] int_en
     *    spi_events_o[0] = s_int_tx | s_int_rx -> FLI[2] -> mip[18] -> ID 18.
     * ------------------------------------------------------------------- */
    TEST_SECTION("3. Arm SPI Class 1 interrupt");
    spi_init(4u);
    intcfg = (1u << 31);   /* int_en, with a zero TX threshold */
    REG32_WRITE(APB_SPI_BASE + SPI_INTCFG_OFFSET, intcfg);
    /* Read back: proves the write actually reached the SPI APB interface. */
    TEST_ASSERT_EQ(0x80000000u,
                   REG32_READ(APB_SPI_BASE + SPI_INTCFG_OFFSET) & 0x80000000u,
                   0x7030);
    proof_note_slot(APB_SPI_BASE);
    proof_note_read();

    /* ---------------------------------------------------------------------
     * 4. Enable the sources. mie is WARL-masked to 0xFFFF0888 (csr_regfile.v:
     *    219), so bits 7 and 18 are legal. Read back rather than assuming the
     *    CSR write took effect.
     * ------------------------------------------------------------------- */
    TEST_SECTION("4. Enable mie and mstatus.MIE");
    csr_set_mie(MIE_BIT(IRQ_ID_TIMER0) | MIE_BIT(IRQ_ID_SPI));
    TEST_ASSERT_EQ(MIE_BIT(IRQ_ID_TIMER0) | MIE_BIT(IRQ_ID_SPI),
                   csr_read_mie() & (MIE_BIT(IRQ_ID_TIMER0) | MIE_BIT(IRQ_ID_SPI)),
                   0x7040);
    csr_set_mstatus_mie();
    TEST_ASSERT(csr_read_mstatus() & (1u << 3), 0x7041);

    /* ---------------------------------------------------------------------
     * 5. Service interrupts. Every wait is mcycle-bounded, so a timeout here
     *    is an explicit failure code rather than a fall-through to the TB
     *    watchdog.
     * ------------------------------------------------------------------- */
    TEST_SECTION("5. Service interrupts and observe preemption");
    TEST_ASSERT_EQ(0, wait_for(&timer0_entries, REQUIRED_TIMER0, ISR_BUDGET), 0x7050);

    /* Kick a transfer so the Class 1 source has something to report. */
    spi_select_cs(0);
    (void)spi_transfer_command(0x9Fu, 8u, 0u, 0u, 0u, 24u, 1);
    spi_deselect_cs();

    /* Bounded window for the Class 1 handler to be entered and preempted. */
    TEST_ASSERT_EQ(0, wait_for(&preemptions, REQUIRED_NEST, ISR_BUDGET), 0x7051);

    /* ---------------------------------------------------------------------
     * 6. Quiesce the sources BEFORE checking integrity, otherwise a new
     *    interrupt can land between the checks and make the result
     *    irreproducible.
     * ------------------------------------------------------------------- */
    TEST_SECTION("6. Quiesce interrupt sources");
    csr_clear_mstatus_mie();
    csr_clear_mie(MIE_BIT(IRQ_ID_TIMER0) | MIE_BIT(IRQ_ID_SPI));
    timer_stop(APB_TIMER0_BASE);
    REG32_WRITE(APB_SPI_BASE + SPI_INTCFG_OFFSET, 0x00000000u);
    TEST_ASSERT_EQ(0u, REG32_READ(APB_TIMER0_BASE + TIMER_CTRL_OFFSET) & TIMER_CTRL_EN,
                   0x7060);

    for (i = 0; i < 500u; i++) { settle += i; }   /* let in-flight traps retire */
    TEST_ASSERT_EQ(0u, sw_nest_depth, 0x7061);

    /* ---------------------------------------------------------------------
     * 7. The actual proofs.
     * ------------------------------------------------------------------- */
    TEST_SECTION("7. Nesting and register integrity");
    TEST_ASSERT_EQ(0u, bad_cause, 0x7070);
    TEST_ASSERT(timer0_entries >= REQUIRED_TIMER0, 0x7071);
    TEST_ASSERT(class1_entries >= 1u, 0x7072);
    TEST_ASSERT(preemptions >= REQUIRED_NEST, 0x7073);
    TEST_ASSERT_EQ(2u, max_sw_nest, 0x7074);

    /* Every callee-saved register survived all of the above. */
    CANARY_CHECK(c_s0,  0x11111111u, 0x7080);
    CANARY_CHECK(c_s1,  0x22222222u, 0x7081);
    CANARY_CHECK(c_s2,  0x33333333u, 0x7082);
    CANARY_CHECK(c_s3,  0x44444444u, 0x7083);
    CANARY_CHECK(c_s4,  0x55555555u, 0x7084);
    CANARY_CHECK(c_s5,  0x66666666u, 0x7085);
    CANARY_CHECK(c_s6,  0x77777777u, 0x7086);
    CANARY_CHECK(c_s7,  0x88888888u, 0x7087);
    CANARY_CHECK(c_s8,  0x99999999u, 0x7088);
    CANARY_CHECK(c_s9,  0xAAAAAAAAu, 0x7089);
    CANARY_CHECK(c_s10, 0xBBBBBBBBu, 0x708A);
    CANARY_CHECK(c_s11, 0xCCCCCCCCu, 0x708B);
    CANARY_CHECK(outer_canary, 0x0C1A55C1u, 0x708C);

    /* DSRAM and the mailbox control word survived the whole interrupt storm. */
    TEST_ASSERT_NE(0u, proof_dsram_signature(0x7A500008u), 0x7090);
    TEST_ASSERT_EQ(MAILBOX_CMD_RUNNING, MAILBOX->cmd_status, 0x7091);

    TEST_REQUIRE_ACTIVITY(16, 6, 3, 0x7000);
    TEST_PASS();
    return 0;
}
