/* =============================================================================
 * RISCFORGE 1TOPS — Interrupt Management Subsystem Implementation (irq.c)
 * ============================================================================= */

#include "irq.h"
#include "soc_regs.h"

static irq_handler_t g_irq_vector_table[IRQ_NUM_SOURCES];

/* Dedicated fault recording globals */
volatile uint32_t g_last_trap_cause = 0;
volatile uint32_t g_last_trap_epc   = 0;
volatile uint32_t g_unknown_irq_count = 0;

/* Default weak handler declarations with explicit source acknowledgment */
void isr_timer0_cmp(uint32_t cause, uint32_t epc) __attribute__((weak));
void isr_gpio(uint32_t cause, uint32_t epc) __attribute__((weak));
void isr_i2c(uint32_t cause, uint32_t epc) __attribute__((weak));
void isr_spi_thold(uint32_t cause, uint32_t epc) __attribute__((weak));
void isr_uart(uint32_t cause, uint32_t epc) __attribute__((weak));
void isr_spi_eot(uint32_t cause, uint32_t epc) __attribute__((weak));
void isr_default_timer(uint32_t cause, uint32_t epc) __attribute__((weak));

void isr_timer0_cmp(uint32_t cause, uint32_t epc) {
    (void)cause; (void)epc;
    /* Acknowledge Timer 0 Channel 0: disable IRQ or reset counter */
    TIMER0_CTRL_CH0 = TIMER_CTRL_RESET;
}

void isr_gpio(uint32_t cause, uint32_t epc) {
    (void)cause; (void)epc;
    /* Acknowledge GPIO: write-1-to-clear all pending state bits */
    uint32_t pending = GPIO_INTR_STATE;
    GPIO_INTR_STATE = pending;
}

void isr_i2c(uint32_t cause, uint32_t epc) {
    (void)cause; (void)epc;
    /* Acknowledge I2C: read status register */
    volatile uint32_t status = I2C_REG_STATUS;
    (void)status;
}

void isr_spi_thold(uint32_t cause, uint32_t epc) {
    (void)cause; (void)epc;
    /* Acknowledge SPI threshold: read status register */
    volatile uint32_t status = SPI_REG_STATUS;
    (void)status;
}

void isr_uart(uint32_t cause, uint32_t epc) {
    (void)cause; (void)epc;
    /* Acknowledge UART: read IIR to clear pending line/TX interrupt */
    volatile uint32_t iir = UART_IIR;
    (void)iir;
}

void isr_spi_eot(uint32_t cause, uint32_t epc) {
    (void)cause; (void)epc;
    /* Acknowledge SPI EOT: clear interrupt status */
    SPI_REG_INTSTA = 0x1;
}

void isr_default_timer(uint32_t cause, uint32_t epc) {
    (void)cause; (void)epc;
    /* Generic timer acknowledge: clear timer control reset bit */
    TIMER0_CTRL_CH0 = TIMER_CTRL_RESET;
    TIMER1_CTRL_CH0 = TIMER_CTRL_RESET;
}

/* =============================================================================
 * Initialization & Configuration
 * ============================================================================= */
void irq_init(void) {
    for (int i = 0; i < IRQ_NUM_SOURCES; i++) {
        g_irq_vector_table[i] = 0;
    }
    /* Bind default weak ISRs */
    g_irq_vector_table[IRQ_CAUSE_TIMER0_CMP]     = isr_timer0_cmp;
    g_irq_vector_table[IRQ_CAUSE_GPIO]           = isr_gpio;
    g_irq_vector_table[IRQ_CAUSE_I2C]            = isr_i2c;
    g_irq_vector_table[IRQ_CAUSE_SPI_THOLD]      = isr_spi_thold;
    g_irq_vector_table[IRQ_CAUSE_UART]           = isr_uart;
    g_irq_vector_table[IRQ_CAUSE_SPI_EOT]        = isr_spi_eot;
    g_irq_vector_table[IRQ_CAUSE_TIMER0_CH0_OVF] = isr_default_timer;
    g_irq_vector_table[IRQ_CAUSE_TIMER0_CH1_OVF] = isr_default_timer;
    g_irq_vector_table[IRQ_CAUSE_TIMER0_CH1_CMP] = isr_default_timer;
    g_irq_vector_table[IRQ_CAUSE_TIMER1_CH0_OVF] = isr_default_timer;
    g_irq_vector_table[IRQ_CAUSE_TIMER1_CH0_CMP] = isr_default_timer;
    g_irq_vector_table[IRQ_CAUSE_TIMER1_CH1_OVF] = isr_default_timer;
    g_irq_vector_table[IRQ_CAUSE_TIMER1_CH1_CMP] = isr_default_timer;

    /* Reset priority threshold */
    irq_set_priority_threshold(MINTPRIO_ALLOW_ALL);
}

void irq_enable_global(void) {
    __asm__ volatile ("csrsi mstatus, 0x8");
}

void irq_disable_global(void) {
    __asm__ volatile ("csrci mstatus, 0x8");
}

void irq_enable_source(uint32_t cause_id) {
    if (cause_id < 32) {
        uint32_t mask = (1UL << cause_id);
        __asm__ volatile ("csrs mie, %0" : : "r"(mask));
    }
}

void irq_disable_source(uint32_t cause_id) {
    if (cause_id < 32) {
        uint32_t mask = (1UL << cause_id);
        __asm__ volatile ("csrc mie, %0" : : "r"(mask));
    }
}

void irq_set_priority_threshold(uint32_t threshold) {
    __asm__ volatile ("csrw 0x7C0, %0" : : "r"(threshold & 0x3));
}

bool irq_register_handler(uint32_t cause_id, irq_handler_t handler) {
    if (cause_id >= IRQ_NUM_SOURCES) return false;
    g_irq_vector_table[cause_id] = handler;
    return true;
}

/* =============================================================================
 * Trap Dispatchers
 * ============================================================================= */
void c_trap_handler(uint32_t cause, uint32_t epc) {
    g_last_trap_cause = cause;
    g_last_trap_epc   = epc;

    if (cause < IRQ_NUM_SOURCES && g_irq_vector_table[cause]) {
        g_irq_vector_table[cause](cause, epc);
    } else {
        /* Unimplemented / unregistered interrupt: record and halt */
        g_unknown_irq_count++;
        while (1) {
            __asm__ volatile ("csrci mstatus, 0x8; wfi");
        }
    }
}

void c_exception_handler(uint32_t cause, uint32_t epc) {
    g_last_trap_cause = cause;
    g_last_trap_epc   = epc;
    /* Synchronous exception: isolate and halt */
    while (1) {
        __asm__ volatile ("csrci mstatus, 0x8; wfi");
    }
}
