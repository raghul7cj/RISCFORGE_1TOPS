/* =============================================================================
 * RISC-V Core-Local Interrupt Controller (CLIC) Driver Header
 * Target: PULP CLIC IP (pulp-platform/clic)
 * Compatible with RISC-V CLIC Specification v0.9 / OpenTitan reggen format
 * ============================================================================= */

#ifndef CLIC_H
#define CLIC_H

#include <stdint.h>
#include <stdbool.h>

#define CLIC_REG32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))
#define CLIC_REG8(addr)  (*(volatile uint8_t  *)(uintptr_t)(addr))

/* Global CLIC configuration register offsets */
#define CLIC_CFG_OFFSET         0x0000
#define CLIC_INFO_OFFSET        0x0004
#define CLIC_MINTTHRESH_OFFSET  0x0008

/* Per-interrupt register configuration (each interrupt has a 4-byte slot) */
#define CLIC_INT_BASE_OFFSET    0x1000
#define CLIC_INT_REG(base, irq) CLIC_REG32((base) + CLIC_INT_BASE_OFFSET + ((irq) * 4))

/* Subfields within each CLIC interrupt register (32-bit packed or byte access) */
#define CLIC_INTIP(base, irq)   CLIC_REG8((base) + CLIC_INT_BASE_OFFSET + ((irq) * 4) + 0)
#define CLIC_INTIE(base, irq)   CLIC_REG8((base) + CLIC_INT_BASE_OFFSET + ((irq) * 4) + 1)
#define CLIC_INTATTR(base, irq) CLIC_REG8((base) + CLIC_INT_BASE_OFFSET + ((irq) * 4) + 2)
#define CLIC_INTCTL(base, irq)  CLIC_REG8((base) + CLIC_INT_BASE_OFFSET + ((irq) * 4) + 3)

/* Trigger modes in ATTR register */
#define CLIC_ATTR_TRIG_LEVEL_POS 0x00
#define CLIC_ATTR_TRIG_EDGE_POS  0x02
#define CLIC_ATTR_TRIG_LEVEL_NEG 0x04
#define CLIC_ATTR_TRIG_EDGE_NEG  0x06
#define CLIC_ATTR_SHV            (1 << 4) /* Selective Hardware Vectoring */

/* API Prototypes */
void clic_init(uintptr_t base_addr);
void clic_set_threshold(uintptr_t base_addr, uint8_t threshold);
void clic_enable_interrupt(uintptr_t base_addr, uint32_t irq_id);
void clic_disable_interrupt(uintptr_t base_addr, uint32_t irq_id);
void clic_set_priority(uintptr_t base_addr, uint32_t irq_id, uint8_t priority);
void clic_set_trigger(uintptr_t base_addr, uint32_t irq_id, uint8_t trigger_mode, bool shv);
void clic_set_pending(uintptr_t base_addr, uint32_t irq_id);
void clic_clear_pending(uintptr_t base_addr, uint32_t irq_id);
bool clic_is_pending(uintptr_t base_addr, uint32_t irq_id);

#endif /* CLIC_H */
