/* =============================================================================
 * RISCFORGE 1TOPS - End-to-End Timer Interrupt Verification Test
 * =============================================================================
 * Verifies:
 *   1. Hardware Timer 0 Channel 0 setup & run via APB
 *   2. Core trap vector entry (Direct Mode mtvec -> trap_entry.S)
 *   3. Context save/restore and C ISR dispatch (irq.c -> isr_timer0_cmp)
 *   4. Timer compare match clear via CMP=0 without masking MTIE (proves no repeated trap)
 *   5. Rearming timer compare for a 2nd interrupt event
 * ============================================================================= */

#include "soc_regs.h"
#include "irq.h"
#include "uart_min.h"

static volatile uint32_t timer_irq_count = 0;
static volatile uint32_t phase = 1;

/* Override weak ISR for Timer 0 Compare Match (Cause 7, MTIP) */
void isr_timer0_cmp(void) {
    timer_irq_count++;
    
    if (phase == 1) {
        /* Phase 1: Clear compare value to acknowledge, but leave MTIE enabled
         * to prove that CMP=0 successfully stops further interrupts. */
        TIMER0_CMP = 0;
    } else {
        /* Phase 2: Finished test, clear compare and mask source */
        TIMER0_CMP = 0;
        irq_disable_source(IRQ_CAUSE_TIMER0_CMP);
    }
}

int main(void) {
    uart_init();
    uart_puts("\n[TEST] Starting RISCFORGE Timer Interrupt Test...\n");

    /* 1. Initialize In-Core Interrupt Subsystem (mtvec, mintprio) */
    irq_init();

    /* 2. Enable Timer 0 Compare Interrupt (MTIE, bit 7) */
    irq_enable_source(IRQ_CAUSE_TIMER0_CMP);

    /* 3. Program Timer 0 (Base 0x4000_1000, Channel 0) - Phase 1 */
    uart_puts("[TEST] Phase 1: Firing first compare match...\n");
    TIMER0_CTRL = 0;              /* Disable during setup */
    TIMER0_VAL  = 0;              /* Reset counter */
    TIMER0_CMP  = 1000;           /* Set compare threshold to 1000 cycles */
    TIMER0_CTRL = TIMER_CTRL_EN;  /* Enable timer */

    /* 4. Enable Global Interrupts (mstatus.MIE = 1) */
    irq_enable_global();

    /* Wait for Phase 1 interrupt */
    for (volatile int i = 0; i < 50000; i++) {
        if (timer_irq_count >= 1) break;
    }

    if (timer_irq_count != 1) {
        uart_puts(">>> TIMER TEST FAILED: Phase 1 IRQ did not fire <<<\n");
        REG32(MAILBOX_ADDR) = CMD_FAIL;
        return 0;
    }

    /* Wait several cycles to verify no spurious or continuous retrapping occurs while MTIE is still active */
    for (volatile int i = 0; i < 10000; i++);

    if (timer_irq_count != 1) {
        uart_puts(">>> TIMER TEST FAILED: Continuous retrapping occurred with CMP=0 <<<\n");
        REG32(MAILBOX_ADDR) = CMD_FAIL;
        return 0;
    }

    uart_puts("[TEST] Phase 1 verified: CMP=0 successfully silenced compare interrupt.\n");

    /* 5. Phase 2: Rearm Timer 0 for second interrupt */
    uart_puts("[TEST] Phase 2: Rearming timer for 2nd interrupt...\n");
    phase = 2;
    TIMER0_VAL  = 0;
    TIMER0_CMP  = 500; /* Set compare to 500 cycles */

    for (volatile int i = 0; i < 50000; i++) {
        if (timer_irq_count >= 2) break;
    }

    if (timer_irq_count == 2) {
        uart_puts(">>> TIMER INTERRUPT TEST: [ PASSED ] <<<\n");
        REG32(MAILBOX_ADDR) = CMD_PASS;
    } else {
        uart_puts(">>> TIMER TEST FAILED: Phase 2 rearm did not fire <<<\n");
        REG32(MAILBOX_ADDR) = CMD_FAIL;
    }

    return 0;
}
