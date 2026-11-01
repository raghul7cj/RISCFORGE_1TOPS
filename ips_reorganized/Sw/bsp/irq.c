/* =============================================================================
 * RISCFORGE 1TOPS - In-Core Interrupt Subsystem C Dispatcher (irq.c)
 * ============================================================================= */

#include "irq.h"

extern void trap_entry(void);

#define CSR_MSTATUS   0x300
#define CSR_MIE       0x304
#define CSR_MTVEC     0x305
#define CSR_MINTPRIO  0x7C0

/* Table of function pointers for registered ISRs */
static isr_handler_t isr_table[32];

/* =============================================================================
 * Weak ISR Stubs
 * If unhandled, mask the offending interrupt source to prevent an infinite
 * trap loop on level-triggered / unserviced interrupt lines.
 * Override any of these in test code or application.
 * ============================================================================= */
__attribute__((weak)) void isr_timer0_cmp(void)     { irq_disable_source(IRQ_CAUSE_TIMER0_CMP); }
__attribute__((weak)) void isr_gpio(void)           { irq_disable_source(IRQ_CAUSE_GPIO); }
__attribute__((weak)) void isr_i2c(void)            { irq_disable_source(IRQ_CAUSE_I2C); }
__attribute__((weak)) void isr_spi_thold(void)      { irq_disable_source(IRQ_CAUSE_SPI_THOLD); }
__attribute__((weak)) void isr_uart(void)           { irq_disable_source(IRQ_CAUSE_UART); }
__attribute__((weak)) void isr_timer0_ch0_ovf(void) { irq_disable_source(IRQ_CAUSE_TIMER0_CH0_OVF); }
__attribute__((weak)) void isr_timer0_ch1_ovf(void) { irq_disable_source(IRQ_CAUSE_TIMER0_CH1_OVF); }
__attribute__((weak)) void isr_timer0_ch1_cmp(void) { irq_disable_source(IRQ_CAUSE_TIMER0_CH1_CMP); }
__attribute__((weak)) void isr_timer1_ch0_ovf(void) { irq_disable_source(IRQ_CAUSE_TIMER1_CH0_OVF); }
__attribute__((weak)) void isr_timer1_ch0_cmp(void) { irq_disable_source(IRQ_CAUSE_TIMER1_CH0_CMP); }
__attribute__((weak)) void isr_timer1_ch1_ovf(void) { irq_disable_source(IRQ_CAUSE_TIMER1_CH1_OVF); }
__attribute__((weak)) void isr_timer1_ch1_cmp(void) { irq_disable_source(IRQ_CAUSE_TIMER1_CH1_CMP); }
__attribute__((weak)) void isr_spi_eot(void)        { irq_disable_source(IRQ_CAUSE_SPI_EOT); }

__attribute__((weak)) void exception_handler(uint32_t mcause, uint32_t mepc) {
    (void)mcause;
    (void)mepc;
    while (1); /* Hang on unhandled synchronous exception */
}

/* =============================================================================
 * C Trap Handler: Dispatches interrupt or exception
 * ============================================================================= */
void c_trap_handler(uint32_t mcause, uint32_t mepc) {
    if (mcause & 0x80000000UL) {
        /* Asynchronous Interrupt */
        uint32_t cause_id = mcause & 0x1FUL;
        
        /* If custom handler registered in table, call it; else call weak ISR */
        if (isr_table[cause_id]) {
            isr_table[cause_id]();
        } else {
            switch (cause_id) {
                case IRQ_CAUSE_TIMER0_CMP:     isr_timer0_cmp();     break;
                case IRQ_CAUSE_GPIO:           isr_gpio();           break;
                case IRQ_CAUSE_I2C:            isr_i2c();            break;
                case IRQ_CAUSE_SPI_THOLD:      isr_spi_thold();      break;
                case IRQ_CAUSE_UART:           isr_uart();           break;
                case IRQ_CAUSE_TIMER0_CH0_OVF: isr_timer0_ch0_ovf(); break;
                case IRQ_CAUSE_TIMER0_CH1_OVF: isr_timer0_ch1_ovf(); break;
                case IRQ_CAUSE_TIMER0_CH1_CMP: isr_timer0_ch1_cmp(); break;
                case IRQ_CAUSE_TIMER1_CH0_OVF: isr_timer1_ch0_ovf(); break;
                case IRQ_CAUSE_TIMER1_CH0_CMP: isr_timer1_ch0_cmp(); break;
                case IRQ_CAUSE_TIMER1_CH1_OVF: isr_timer1_ch1_ovf(); break;
                case IRQ_CAUSE_TIMER1_CH1_CMP: isr_timer1_ch1_cmp(); break;
                case IRQ_CAUSE_SPI_EOT:        isr_spi_eot();        break;
                default: break;
            }
        }
    } else {
        /* Synchronous Exception */
        exception_handler(mcause, mepc);
    }
}

/* =============================================================================
 * Initialization & Control API
 * All CSR operations include compiler memory clobbers ("memory") to guarantee
 * proper memory ordering across interrupt enable/disable boundaries.
 * ============================================================================= */
void irq_init(void) {
    /* 1. Ensure global interrupts are disabled during re-initialization */
    irq_disable_global();

    /* 2. Clear mie */
    __asm__ volatile ("csrw %0, zero" : : "i"(CSR_MIE) : "memory");

    /* 3. Set mtvec to trap_entry (Direct Mode) */
    uint32_t t_addr = (uint32_t)&trap_entry;
    __asm__ volatile ("csrw %0, %1" : : "i"(CSR_MTVEC), "r"(t_addr) : "memory");

    /* 4. Set mintprio threshold to 0 (allow Class 0, 1, 2) */
    __asm__ volatile ("csrw %0, %1" : : "i"(CSR_MINTPRIO), "r"(0) : "memory");
}

void irq_enable_global(void) {
    __asm__ volatile ("csrsi %0, 0x8" : : "i"(CSR_MSTATUS) : "memory");
}

void irq_disable_global(void) {
    __asm__ volatile ("csrci %0, 0x8" : : "i"(CSR_MSTATUS) : "memory");
}

void irq_enable_source(uint32_t cause_id) {
    if (cause_id < 32) {
        uint32_t mask = (1UL << cause_id);
        __asm__ volatile ("csrs %0, %1" : : "i"(CSR_MIE), "r"(mask) : "memory");
    }
}

void irq_disable_source(uint32_t cause_id) {
    if (cause_id < 32) {
        uint32_t mask = (1UL << cause_id);
        __asm__ volatile ("csrc %0, %1" : : "i"(CSR_MIE), "r"(mask) : "memory");
    }
}

void irq_set_priority_threshold(uint32_t threshold) {
    __asm__ volatile ("csrw %0, %1" : : "i"(CSR_MINTPRIO), "r"(threshold & 0x3) : "memory");
}

void irq_register_handler(uint32_t cause_id, isr_handler_t handler) {
    if (cause_id < 32) {
        isr_table[cause_id] = handler;
    }
}
