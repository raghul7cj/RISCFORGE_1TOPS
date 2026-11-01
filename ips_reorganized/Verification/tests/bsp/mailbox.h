/* =============================================================================
 * RISCFORGE 1TOPS — SoC Verification Mailbox Interface (mailbox.h)
 * =============================================================================
 * Firmware is stimulus, Testbench is the judge.
 * Mailbox sits in DSRAM at 0x0002_0000 (reserved 64 Bytes).
 *
 * The CMD_* encodings MUST match tb_pkg.sv verbatim:
 *     CMD_PASS = 32'hC0DE_C0DE   CMD_FAIL = 32'hBAAD_F00D   CMD_HALT = 32'hDEAD_BEEF
 * Any divergence means the TB never observes the completion word and every
 * test degenerates into a watchdog timeout.
 * ============================================================================= */

#ifndef RISCFORGE_MAILBOX_H_
#define RISCFORGE_MAILBOX_H_

#include <stdint.h>

#define MAILBOX_BASE_ADDR   0x00020000UL

/* Mailbox Command / Status Codes — must mirror tb_pkg.sv */
#define MAILBOX_CMD_RUNNING 0x00000000UL
#define MAILBOX_CMD_PASS    0xC0DEC0DEUL
#define MAILBOX_CMD_FAIL    0xBAADF00DUL
#define MAILBOX_CMD_SECTION 0x00000003UL
#define MAILBOX_CMD_HALT    0xDEADBEEFUL

/* Mailbox Data Structure (Memory Mapped) */
typedef struct {
    volatile uint32_t cmd_status; /* +0x00: Command / Status */
    volatile uint32_t test_id;    /* +0x04: Test Identifier */
    volatile uint32_t arg0;       /* +0x08: Address / Arg 0 */
    volatile uint32_t arg1;       /* +0x0C: Expected / Arg 1 */
    volatile uint32_t arg2;       /* +0x10: Actual / Arg 2 */
    volatile uint32_t char_out;   /* +0x14: Direct console character stream */
    volatile uint32_t error_code; /* +0x18: Error / Assert Code */
    volatile uint32_t cycle_cnt;  /* +0x1C: Firmware activity attestation */
} mailbox_t;

#define MAILBOX ((mailbox_t *)MAILBOX_BASE_ADDR)

/*
 * Activity attestation word (+0x1C).
 *   [15:0]  mmio_rds   - MMIO reads the firmware completed and data-checked
 *   [31:16] mmio_wrs   - MMIO writes the firmware issued
 * The TB cross-checks this against its own AXI/APB/LSU monitor totals. A stage
 * that skips peripheral traffic therefore cannot produce a non-zero word, and
 * the TB rejects the PASS.
 */
static inline void mailbox_publish_activity(uint32_t mmio_rds, uint32_t mmio_wrs) {
    MAILBOX->cycle_cnt = ((mmio_wrs & 0xFFFFUL) << 16) | (mmio_rds & 0xFFFFUL);
}

static inline void mailbox_init(uint32_t test_id) {
    MAILBOX->test_id    = test_id;
    MAILBOX->arg0       = 0;
    MAILBOX->arg1       = 0;
    MAILBOX->arg2       = 0;
    MAILBOX->error_code = 0;
    MAILBOX->cycle_cnt  = 0;
    MAILBOX->cmd_status = MAILBOX_CMD_RUNNING;
}

static inline void mailbox_putc(char c) {
    static uint16_t mb_seq = 1;
    MAILBOX->char_out = ((uint32_t)mb_seq << 16) | ((uint32_t)(uint8_t)c);
    mb_seq++;
}

static inline void mailbox_puts(const char *s) {
    while (*s) {
        mailbox_putc(*s++);
    }
}

static inline void mailbox_halt(void) {
    MAILBOX->cmd_status = MAILBOX_CMD_HALT;
    while (1) {
        __asm__ volatile ("wfi");
    }
}

static inline void mailbox_pass(void) {
    MAILBOX->cmd_status = MAILBOX_CMD_PASS;
    /* Park in WFI. The TB owns $finish; if we are still spinning here the run
     * is being judged by the watchdog instead, which is a FAIL by definition. */
    while (1) {
        __asm__ volatile ("wfi");
    }
}

static inline void mailbox_fail(uint32_t err_code, uint32_t addr, uint32_t exp, uint32_t got) {
    MAILBOX->error_code = err_code;
    MAILBOX->arg0       = addr;
    MAILBOX->arg1       = exp;
    MAILBOX->arg2       = got;
    MAILBOX->cmd_status = MAILBOX_CMD_FAIL;
    while (1) {
        __asm__ volatile ("wfi");
    }
}

#endif /* RISCFORGE_MAILBOX_H_ */
