/* =============================================================================
 * RISCFORGE 1TOPS - In-Core Interrupt Subsystem BSP Header (irq.h)
 * =============================================================================
 * Architecture: RV32IM_Zicsr Direct Mode Trap Vector with 2-Level Priority Class
 * Maps all 13 hardware interrupt lines to C ISR callbacks.
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
#define IRQ_CAUSE_I2C              17  /* I2C Done / Arbitration Lost (Class 0) */
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

/* Interrupt Enable bitmasks for mie CSR */
#define MIE_MTIE                   (1UL << 7)
#define MIE_FLIE(id)               (1UL << (id)) /* Causes 16..27 */

/* Class priority threshold values for custom CSR mintprio (0x7C0) */
#define MINTPRIO_ALLOW_ALL         0x0  /* Class 0, 1, 2 unmasked */
#define MINTPRIO_MASK_CLASS0       0x1  /* Class 1, 2 unmasked */
#define MINTPRIO_MASK_CLASS0_1     0x2  /* Only Class 2 unmasked */

/* =============================================================================
 * 2. API Functions
 * ============================================================================= */
void irq_init(void);
void irq_enable_global(void);
void irq_disable_global(void);
void irq_enable_source(uint32_t cause_id);
void irq_disable_source(uint32_t cause_id);
void irq_set_priority_threshold(uint32_t threshold);

/* Function pointer type for dynamic ISR registration */
typedef void (*isr_handler_t)(void);
void irq_register_handler(uint32_t cause_id, isr_handler_t handler);

/* =============================================================================
 * 3. Default Weak ISR Declarations (can be overridden anywhere in user code)
 * ============================================================================= */
void isr_timer0_cmp(void);
void isr_gpio(void);
void isr_i2c(void);
void isr_spi_thold(void);
void isr_uart(void);
void isr_timer0_ch0_ovf(void);
void isr_timer0_ch1_ovf(void);
void isr_timer0_ch1_cmp(void);
void isr_timer1_ch0_ovf(void);
void isr_timer1_ch0_cmp(void);
void isr_timer1_ch1_ovf(void);
void isr_timer1_ch1_cmp(void);
void isr_spi_eot(void);

#endif /* RISCFORGE_IRQ_H */
