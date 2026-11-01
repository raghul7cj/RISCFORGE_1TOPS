/* =============================================================================
 * RISCFORGE 1TOPS — End-to-End Timer Interrupt Verification Test
 * ============================================================================= */

#include <stdint.h>
#include "../bsp/soc_regs.h"
#include "../bsp/irq.h"
#include "../drivers/uart.h"
#include "../drivers/timer.h"

static volatile uint32_t g_timer_fired = 0;

void test_timer_isr(uint32_t cause, uint32_t epc) {
    (void)cause; (void)epc;
    g_timer_fired++;
    /* Acknowledge and stop timer */
    timer0_init(0, 0);
}

int main(void) {
    /* 1. Initialize UART for test reporting */
    uart_init(27); /* Divisor for 115200 at 50MHz */
    uart_puts("TEST: Timer Interrupt Start\n");

    /* 2. Initialize Interrupt Management */
    irq_init();
    irq_register_handler(IRQ_CAUSE_TIMER0_CMP, test_timer_isr);
    irq_enable_source(IRQ_CAUSE_TIMER0_CMP);
    irq_enable_global();

    /* 3. Configure Timer 0 Channel 0: Compare value = 100 cycles, IRQ enabled */
    timer0_init(100, 1);
    timer0_start();

    /* 4. Wait for interrupt to fire */
    volatile uint32_t timeout = 50000;
    while (!g_timer_fired && --timeout);

    if (g_timer_fired == 1) {
        uart_puts("TIMER_PASS\n");
    } else {
        uart_puts("TIMER_FAIL\n");
    }

    return 0;
}
