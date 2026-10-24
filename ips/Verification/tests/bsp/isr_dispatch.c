/* =============================================================================
 * RISCFORGE 1TOPS — C Interrupt & Exception Dispatcher (isr_dispatch.c)
 * ============================================================================= */

#include "isr_dispatch.h"
#include "mailbox.h"

#define MAX_HANDLERS 32

static isr_handler_t isr_table[MAX_HANDLERS] = {0};

void isr_register_handler(uint32_t cause, isr_handler_t handler) {
    uint32_t idx = cause & 0x1F;
    if (idx < MAX_HANDLERS) {
        isr_table[idx] = handler;
    }
}

void default_unexpected_handler(uint32_t mcause, uint32_t mepc) {
    mailbox_puts("[ERROR] Unexpected Trap Occurred!\n");
    mailbox_fail(0xDEAD0001, mepc, 0, mcause);
}

void c_trap_handler(uint32_t mcause, uint32_t mepc) {
    uint32_t idx = mcause & 0x1F;
    if (idx < MAX_HANDLERS && isr_table[idx] != 0) {
        isr_table[idx](mcause, mepc);
    } else {
        default_unexpected_handler(mcause, mepc);
    }
}
