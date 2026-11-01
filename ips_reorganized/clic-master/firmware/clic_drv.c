/* =============================================================================
 * RISC-V Core-Local Interrupt Controller (CLIC) Driver Implementation
 * Target: PULP CLIC IP (pulp-platform/clic)
 * ============================================================================= */

#include "clic.h"

void clic_init(uintptr_t base_addr) {
    /* Set machine interrupt threshold to 0 to allow all priority levels */
    CLIC_REG8(base_addr + CLIC_MINTTHRESH_OFFSET) = 0x00;
}

void clic_set_threshold(uintptr_t base_addr, uint8_t threshold) {
    CLIC_REG8(base_addr + CLIC_MINTTHRESH_OFFSET) = threshold;
}

void clic_enable_interrupt(uintptr_t base_addr, uint32_t irq_id) {
    CLIC_INTIE(base_addr, irq_id) = 1;
}

void clic_disable_interrupt(uintptr_t base_addr, uint32_t irq_id) {
    CLIC_INTIE(base_addr, irq_id) = 0;
}

void clic_set_priority(uintptr_t base_addr, uint32_t irq_id, uint8_t priority) {
    CLIC_INTCTL(base_addr, irq_id) = priority;
}

void clic_set_trigger(uintptr_t base_addr, uint32_t irq_id, uint8_t trigger_mode, bool shv) {
    uint8_t attr = (trigger_mode & 0x06);
    if (shv) {
        attr |= CLIC_ATTR_SHV;
    }
    CLIC_INTATTR(base_addr, irq_id) = attr;
}

void clic_set_pending(uintptr_t base_addr, uint32_t irq_id) {
    CLIC_INTIP(base_addr, irq_id) = 1;
}

void clic_clear_pending(uintptr_t base_addr, uint32_t irq_id) {
    CLIC_INTIP(base_addr, irq_id) = 0;
}

bool clic_is_pending(uintptr_t base_addr, uint32_t irq_id) {
    return (CLIC_INTIP(base_addr, irq_id) & 0x01) != 0;
}
