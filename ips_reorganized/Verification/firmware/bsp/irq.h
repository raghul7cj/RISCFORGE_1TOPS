/* =============================================================================
 * RISCFORGE 1TOPS — Interrupt Management Subsystem Header (irq.h)
 * ============================================================================= */

#ifndef RISCFORGE_IRQ_H
#define RISCFORGE_IRQ_H

#include <stdint.h>
#include <stdbool.h>

/* =============================================================================
 * 1. Cause IDs (mcause & 0x7FFFFFFF)
 * ============================================================================= */
#define IRQ_CAUSE_TIMER0_CMP       7   /* Machine Timer Interrupt (MTIP, Class 2) */
#define IRQ_CAUSE_GPIO             16  /* GPIO Global Event (Class 0) */
#define IRQ_CAUSE_I2C              17  /* I2C Transfer Done / Arb Lost (Class 0) */
#define IRQ_CAUSE_SPI_THOLD        18  /* SPI Buffer Threshold Event (Class 1) */
#define IRQ_CAUSE_UART             19  /* 16550 UART Event (Class 1) */
#define IRQ_CAUSE_TIMER0_CH0_OVF   20  /* Timer 0 Channel 0 Overflow (Class 2) */
#define IRQ_CAUSE_TIMER0_CH1_OVF   21  /* Timer 0 Channel 1 Overflow (Class 2) */
#define IRQ_CAUSE_TIMER0_CH1_CMP   22  /* Timer 0 Channel 1 Compare (Class 2) */
#define IRQ_CAUSE_TIMER1_CH0_OVF   23  /* Timer 1 Channel 0 Overflow (Class 2) */
#define IRQ_CAUSE_TIMER1_CH0_CMP   24  /* Timer 1 Channel 0 Compare (Class 2) */
#define IRQ_CAUSE_TIMER1_CH1_OVF   25  /* Timer 1 Channel 1 Overflow (Class 2) */
#define IRQ_CAUSE_TIMER1_CH1_CMP   26  /* Timer 1 Channel 1 Compare (Class 2) */
#define IRQ_CAUSE_SPI_EOT          27  /* SPI End of Transfer Event (Class 1) */

#define IRQ_NUM_SOURCES            32

/* Enable bitmasks for mie CSR */
#define MIE_MTIE                   (1UL << 7)
#define MIE_FLIE(id)               (1UL << (id))

/* Class priority threshold values for custom CSR mintprio (0x7C0) */
#define MINTPRIO_ALLOW_ALL         0x0
#define MINTPRIO_MASK_CLASS0       0x1
#define MINTPRIO_MASK_CLASS0_1     0x2

typedef void (*irq_handler_t)(uint32_t cause, uint32_t epc);

/* =============================================================================
 * 2. API Functions
 * ============================================================================= */
void irq_init(void);
void irq_enable_global(void);
void irq_disable_global(void);
void irq_enable_source(uint32_t cause_id);
void irq_disable_source(uint32_t cause_id);
void irq_set_priority_threshold(uint32_t threshold);
bool irq_register_handler(uint32_t cause_id, irq_handler_t handler);

/* Trap dispatch entry points called from trap_entry.S */
void c_trap_handler(uint32_t cause, uint32_t epc);
void c_exception_handler(uint32_t cause, uint32_t epc);

#endif /* RISCFORGE_IRQ_H */
