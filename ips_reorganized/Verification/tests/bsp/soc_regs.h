/* =============================================================================
 * RISCFORGE 1TOPS — SoC Memory Map & Register Definitions (soc_regs.h)
 * ============================================================================= */

#ifndef RISCFORGE_SOC_REGS_H_
#define RISCFORGE_SOC_REGS_H_

#include <stdint.h>

/* Memory Regions */
#define BOOTROM_BASE        0x00000000UL
#define BOOTROM_SIZE        0x00000040UL /* 64 B */

#define ISRAM_BASE          0x00010000UL
#define ISRAM_SIZE          0x00008000UL /* 32 KB */

#define DSRAM_BASE          0x00020000UL
#define DSRAM_SIZE          0x00008000UL /* 32 KB */

/* APB Peripherals (0x4000_0000 - 0x4000_5FFF) */
#define APB_I2C_BASE        0x40000000UL /* APB[0] */
#define APB_TIMER0_BASE     0x40001000UL /* APB[1] */
#define APB_UART_BASE       0x40002000UL /* APB[2] */
#define APB_GPIO_BASE       0x40003000UL /* APB[3] */
#define APB_SPI_BASE        0x40004000UL /* APB[4] */
#define APB_TIMER1_BASE     0x40005000UL /* APB[5] */

/* Register Access Helpers (Strict 32-bit MMIO) */
#define REG32_WRITE(addr, val) (*(volatile uint32_t *)(uintptr_t)(addr) = (uint32_t)(val))
#define REG32_READ(addr)       (*(volatile uint32_t *)(uintptr_t)(addr))

/* CSR Addresses */
#define CSR_MSTATUS         0x300
#define CSR_MISA            0x301
#define CSR_MIE             0x304
#define CSR_MTVEC           0x305
#define CSR_MEPC            0x341
#define CSR_MCAUSE          0x342
#define CSR_MIP             0x344
#define CSR_MINTPRIO        0x7C0

/* Helper CSR functions */
static inline uint32_t csr_read_mstatus(void) {
    uint32_t val;
    __asm__ volatile ("csrr %0, mstatus" : "=r"(val));
    return val;
}

static inline void csr_write_mstatus(uint32_t val) {
    __asm__ volatile ("csrw mstatus, %0" :: "r"(val));
}

static inline void csr_write_mtvec(uint32_t val) {
    __asm__ volatile ("csrw mtvec, %0" :: "r"(val));
}

static inline uint32_t csr_read_mcause(void) {
    uint32_t val;
    __asm__ volatile ("csrr %0, mcause" : "=r"(val));
    return val;
}

static inline uint32_t csr_read_mepc(void) {
    uint32_t val;
    __asm__ volatile ("csrr %0, mepc" : "=r"(val));
    return val;
}

static inline uint32_t csr_read_mcycle(void) {
    uint32_t val;
    __asm__ volatile ("csrr %0, mcycle" : "=r"(val));
    return val;
}

static inline uint32_t csr_read_minstret(void) {
    uint32_t val;
    __asm__ volatile ("csrr %0, minstret" : "=r"(val));
    return val;
}

/* mie is WARL-masked to 0xFFFF0888 in csr_regfile.v:219 — bits 3 (MSIE),
 * 7 (MTIE), 11 (MEIE) and 16..31 (FLIE). Writing a bit outside that mask is
 * silently dropped, so read back to confirm the enable actually took. */
static inline uint32_t csr_read_mie(void) {
    uint32_t val;
    __asm__ volatile ("csrr %0, mie" : "=r"(val));
    return val;
}

static inline uint32_t csr_read_mip(void) {
    uint32_t val;
    __asm__ volatile ("csrr %0, mip" : "=r"(val));
    return val;
}

static inline void csr_set_mie(uint32_t mask) {
    __asm__ volatile ("csrs mie, %0" :: "r"(mask) : "memory");
}

static inline void csr_clear_mie(uint32_t mask) {
    __asm__ volatile ("csrc mie, %0" :: "r"(mask) : "memory");
}

static inline void csr_set_mstatus_mie(void) {
    __asm__ volatile ("csrs mstatus, %0" :: "r"(1u << 3) : "memory");
}

static inline void csr_clear_mstatus_mie(void) {
    __asm__ volatile ("csrc mstatus, %0" :: "r"(1u << 3) : "memory");
}

/* ---------------------------------------------------------------------------
 * Interrupt cause numbers.
 *
 * execute_cycle.v:469 sets exc_cause_W = {1'b1, irq_id[4:0]} on an accepted
 * interrupt, and wb_trap_mret_commit_controller.v:84-94 clears the matching
 * gateway latch for exactly these six IDs. Any other interrupt ID would commit
 * a trap with no gateway clear and lock the core into a re-trap storm, so only
 * these six are ever enabled.
 *
 *   ID  7  Machine timer   Timer 0 compare   Class 2 (fixed, highest)
 *   ID 16  Fast local  0   GPIO global       Class 0 (round-robin)
 *   ID 17  Fast local  1   I2C               Class 0 (level sensitive)
 *   ID 18  Fast local  2   SPI TX/RX         Class 1 (round-robin)
 *   ID 19  Fast local  3   UART              Class 1 (level sensitive)
 *   ID 27  Fast local 11   SPI end-of-xfer   Class 2 (fixed, highest)
 *
 * Timer 1 (IDs 23..26) has NO gateway clear strobe and is absent from the
 * predictor's class map — enabling it would hang the core. Do not use it.
 * ------------------------------------------------------------------------- */
#define IRQ_ID_TIMER0        7u
#define IRQ_ID_GPIO         16u
#define IRQ_ID_I2C          17u
#define IRQ_ID_SPI          18u
#define IRQ_ID_UART         19u
#define IRQ_ID_SPI_EOT      27u

#define MIE_BIT(id)         (1u << (id))
#define MIP_BIT(id)         (1u << (id))

/* Synchronous exception causes (mcause bit 5 == 0) */
#define MCAUSE_INSN_MISALIGNED  0u
#define MCAUSE_INSN_ACCESS_FAULT 1u
#define MCAUSE_ILLEGAL_INSN     2u
#define MCAUSE_BREAKPOINT       3u
#define MCAUSE_LOAD_ACCESS_FAULT 5u
#define MCAUSE_STORE_ACCESS_FAULT 7u
#define MCAUSE_ECALL_U          8u

/* True if an mcause describes an interrupt rather than an exception. */
#define MCAUSE_IS_INTERRUPT(c)  (((c) >> 31) & 1u)

#endif /* RISCFORGE_SOC_REGS_H_ */
