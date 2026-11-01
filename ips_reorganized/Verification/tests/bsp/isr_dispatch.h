/* =============================================================================
 * RISCFORGE 1TOPS — C Interrupt & Exception Dispatcher (isr_dispatch.h)
 * ============================================================================= */

#ifndef RISCFORGE_ISR_DISPATCH_H_
#define RISCFORGE_ISR_DISPATCH_H_

#include <stdint.h>

typedef void (*isr_handler_t)(uint32_t mcause, uint32_t mepc);

/* Register custom handler for specific cause */
void isr_register_handler(uint32_t cause, isr_handler_t handler);

/* Top-level C trap entry called from trap_handler.s */
void c_trap_handler(uint32_t mcause, uint32_t mepc);

#endif /* RISCFORGE_ISR_DISPATCH_H_ */
