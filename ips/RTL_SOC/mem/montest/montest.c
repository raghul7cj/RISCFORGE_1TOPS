/* =============================================================================
 * RISCFORGE 1TOPS - bus timeout monitor test (firmware)
 * =============================================================================
 * Companion to regtest.c. That program proves every peripheral register reads
 * and writes correctly; this one proves that when a slave STOPS answering, the
 * bus monitors end the access instead of hanging the CPU, and that they never
 * end an access that was still legitimate.
 *
 * Under test
 *   apb_timeout_monitor      one per APB slot (ips/bus_monitors/)
 *   axi_lite_timeout_monitor core AXI-Lite master port
 *
 * Thresholds (riscforge_soc_subsystem.sv, Section 4)
 *   slot 0 I2C      16        slot 3 GPIO         16
 *   slot 1 Timer 0  16        slot 4 SPI       65536
 *   slot 2 UART     16        slot 5 Timer 1      16
 *   AXI, APB region  131072   AXI, other region      64 (unreachable, see below)
 *
 * How a stall is produced
 *   Only the SPI master can stall by itself (empty RXFIFO read / full TXFIFO
 *   write). Every other slave ties PREADY high, so the testbench has to hold it
 *   low. The firmware asks for that over the result words: CMD_STALL names a target,
 *   soc_montest_tb.sv forces that slave's PREADY (or, for the AXI target,
 *   freezes the APB bridge before it drives PSEL), and CMD_RELEASE undoes it.
 *   Result words traffic is DSRAM, not MMIO, so it still works while the bus is
 *   jammed.
 *
 * Three behaviours are checked per slot, because the monitor has three
 *   1. timeout   the counter runs to the threshold, then SLVERR
 *   2. blocked   while the slave is still stuck, the next access is failed at
 *                once instead of paying the threshold again (measurably faster)
 *   3. recovery  after the slave is healthy the slot works normally again
 *
 * The AXI monitor's 64-cycle region is NOT reachable from here: the core's
 * hybrid_mem_interface sends only 0x4000_0000-0x4FFF_FFFF over AXI and handles
 * DSRAM directly (riscforge_soc_subsystem.sv:1264-1267), so every core
 * transaction decodes as the APB region. Only the 131072-cycle threshold can be
 * exercised by software.
 *
 * Firmware rules followed (see project notes)
 *   - 32-bit MMIO accesses only, no sub-word loads or stores anywhere
 *   - SPI RXFIFO is read empty only in the tests that are MEANT to abort
 *   - built for rv32i_zicsr: no M-extension instructions
 *
 * Testbench dependencies (soc_montest_tb.sv)
 *   - GPIO pads looped back, SPI CS1 slave shifting out 0xC3A55A3C_0F1E2D4B
 *   - result words commands CMD_STALL / CMD_RELEASE / CMD_MONCLR / CMD_MONCHK /
 *     CMD_STICKY implemented as described below
 * ========================================================================== */

#include <stdint.h>

/* ------------------------------------------------------------------------ */
/*  Memory map                                                              */
/* ------------------------------------------------------------------------ */
#define I2C_BASE      0x40000000u
#define TIMER0_BASE   0x40001000u
#define UART_BASE     0x40002000u
#define GPIO_BASE     0x40003000u
#define SPI_BASE      0x40004000u
#define TIMER1_BASE   0x40005000u

#define T_VAL     0x00u
#define T_CTRL    0x04u
#define T_CMP     0x08u

#define U_THR     0x00u
#define U_RBR     0x00u
#define U_IER     0x04u
#define U_FCR     0x08u
#define U_LCR     0x0Cu
#define U_MCR     0x10u
#define U_LSR     0x14u

#define G_EN      0x080u
#define G_OUT     0x180u

#define S_STATUS  0x00u
#define S_CLKDIV  0x04u
#define S_SPICMD  0x08u
#define S_SPIADR  0x0Cu
#define S_SPILEN  0x10u
#define S_SPIDUM  0x14u
#define S_TXFIFO  0x18u
#define S_RXFIFO  0x20u

#define ALL       0xFFFFFFFFu

/* ------------------------------------------------------------------------ */
/*  Result words (DSRAM 0x0002_0000, reserved by link.ld)               */
/*  The TB acts on the write to R_CMD, which is always the last store.     */
/* ------------------------------------------------------------------------ */
#define RES_ADDR  0x00020000u
#define RES(i)      (*(volatile uint32_t *)(RES_ADDR + ((uint32_t)(i) << 2)))

enum { R_CMD = 0, R_IP, R_NAME, R_SUB, R_ADDR, R_EXP, R_GOT };

enum {
    CMD_PASS    = 1,      /* check passed                                     */
    CMD_FAIL    = 2,      /* check failed: TB prints ip.name : sub, exp, got  */
    CMD_SECTION = 3,      /* progress heading                                 */

    CMD_STALL   = 0x10,   /* ADDR = stall target, hold that slave off the bus */
    CMD_RELEASE = 0x11,   /* release every force                              */
    CMD_MONCLR  = 0x12,   /* zero the TB's per-monitor fire counters          */
    CMD_MONCHK  = 0x13,   /* ADDR = monitor id, EXP = its fire count;         */
                          /* every OTHER monitor must have fired 0 times      */
    CMD_STICKY  = 0x14,   /* EXP = expected {axi_rd,axi_wr,apb[5:0]} stickies */

    CMD_DONE    = 0xD0    /* ADDR = passes, EXP = fails, GOT = total traps    */
};

/* CMD_STALL targets */
enum {
    ST_I2C = 0, ST_TMR0 = 1, ST_UART = 2, ST_GPIO = 3, ST_SPI = 4, ST_TMR1 = 5,
    ST_AXI = 6            /* freeze axi_lite_to_apb before it drives PSEL */
};

/* CMD_MONCHK monitor ids */
enum {
    MON_APB0 = 0, MON_APB1 = 1, MON_APB2 = 2, MON_APB3 = 3,
    MON_APB4 = 4, MON_APB5 = 5,
    MON_AXI_WR = 6, MON_AXI_RD = 7,
    MON_NONE   = 0xFF     /* "no monitor fired at all" */
};

/* sticky bit positions, matching the TB's {axi_rd, axi_wr, apb[5:0]} vector */
#define STK_APB(i)   (1u << (i))
#define STK_AXI_WR   (1u << 6)
#define STK_AXI_RD   (1u << 7)

/* ------------------------------------------------------------------------ */
/*  Trap record, written by trap_entry in ../regtest/startup.S              */
/* ------------------------------------------------------------------------ */
typedef struct {
    uint32_t count;      /* cleared by the firmware before a probe */
    uint32_t cause;
    uint32_t tval;
    uint32_t epc;
    uint32_t total;      /* never cleared */
} trap_rec_t;

volatile trap_rec_t g_trap;

static uint32_t n_pass, n_fail, n_exp_traps, sticky_exp;

/* ------------------------------------------------------------------------ */
/*  Low-level helpers                                                       */
/* ------------------------------------------------------------------------ */
static inline uint32_t rd32(uint32_t a)             { return *(volatile uint32_t *)a; }
static inline void     wr32(uint32_t a, uint32_t v) { *(volatile uint32_t *)a = v; }

/* Free-running machine cycle counter (csr_regfile.v:191). The "memory"
 * clobber stops the compiler moving the access under test across it. */
static inline uint32_t rdcyc(void)
{
    uint32_t c;
    __asm__ volatile ("csrr %0, mcycle" : "=r"(c) : : "memory");
    return c;
}

static void delay(uint32_t n)
{
    while (n--)
        __asm__ volatile ("nop");
}

#define P(s) ((uint32_t)(uintptr_t)(s))

static void report(uint32_t cmd, const char *ip, const char *name, const char *sub,
                      uint32_t addr, uint32_t exp, uint32_t got)
{
    RES(R_IP)   = P(ip);
    RES(R_NAME) = P(name);
    RES(R_SUB)  = P(sub);
    RES(R_ADDR) = addr;
    RES(R_EXP)  = exp;
    RES(R_GOT)  = got;
    RES(R_CMD)  = cmd;
}

static void section(const char *title)
{
    report(CMD_SECTION, "", title, "", 0, 0, 0);
}

static void check(const char *ip, const char *name, const char *sub,
                  uint32_t addr, uint32_t exp, uint32_t got)
{
    if (got == exp) {
        n_pass++;
        report(CMD_PASS, ip, name, sub, addr, exp, got);
    } else {
        n_fail++;
        report(CMD_FAIL, ip, name, sub, addr, exp, got);
    }
}

/* exp is the bound; got is the measurement. */
static void check_ge(const char *ip, const char *name, const char *sub,
                     uint32_t addr, uint32_t lo, uint32_t got)
{
    if (got >= lo) {
        n_pass++;
        report(CMD_PASS, ip, name, sub, addr, lo, got);
    } else {
        n_fail++;
        report(CMD_FAIL, ip, name, sub, addr, lo, got);
    }
}

static void check_le(const char *ip, const char *name, const char *sub,
                     uint32_t addr, uint32_t hi, uint32_t got)
{
    if (got <= hi) {
        n_pass++;
        report(CMD_PASS, ip, name, sub, addr, hi, got);
    } else {
        n_fail++;
        report(CMD_FAIL, ip, name, sub, addr, hi, got);
    }
}

/* ------------------------------------------------------------------------ */
/*  Testbench control                                                       */
/* ------------------------------------------------------------------------ */
static void tb_stall(uint32_t target)   { report(CMD_STALL,   "", "", "", target, 0, 0); }
static void tb_release(void)            { report(CMD_RELEASE, "", "", "", 0, 0, 0); }
static void tb_monclr(void)             { report(CMD_MONCLR,  "", "", "", 0, 0, 0); }
static void tb_monchk(uint32_t mon, uint32_t fires)
                                        { report(CMD_MONCHK,  "", "", "", mon, fires, 0); }
static void tb_sticky(uint32_t vec)     { report(CMD_STICKY,  "", "", "", 0, vec, 0); }

/* ------------------------------------------------------------------------ */
/*  Timed accesses                                                          */
/* ------------------------------------------------------------------------ */
typedef struct {
    uint32_t cyc;      /* mcycle delta across the access (incl. any trap)  */
    uint32_t traps;    /* traps taken during the access                    */
    uint32_t cause;
    uint32_t tval;
    uint32_t data;     /* undefined when the access faulted                */
} acc_t;

/* The result is written through a pointer, not returned: a struct return at
 * -Os makes GCC emit memcpy, which this freestanding image does not link. */
static void timed_read(acc_t *r, uint32_t a)
{
    uint32_t t0;

    g_trap.count = 0;
    g_trap.cause = 0;
    g_trap.tval  = 0;

    t0      = rdcyc();
    r->data = rd32(a);
    r->cyc  = rdcyc() - t0;

    r->traps = g_trap.count;
    r->cause = g_trap.cause;
    r->tval  = g_trap.tval;
}

static void timed_write(acc_t *r, uint32_t a, uint32_t v)
{
    uint32_t t0;

    g_trap.count = 0;
    g_trap.cause = 0;
    g_trap.tval  = 0;

    t0 = rdcyc();
    wr32(a, v);
    r->cyc = rdcyc() - t0;

    r->data  = 0;
    r->traps = g_trap.count;
    r->cause = g_trap.cause;
    r->tval  = g_trap.tval;
}

static void expect_trap(const char *ip, const char *nm, const acc_t *r,
                        uint32_t a, uint32_t cause)
{
    n_exp_traps++;
    check(ip, nm, "exactly one trap taken",          a, 1,     r->traps);
    check(ip, nm, "mcause (5 load / 7 store)",       a, cause, r->cause);
    check(ip, nm, "mtval = aborted address",         a, a,     r->tval);
}

/* ------------------------------------------------------------------------ */
/*  Slot table                                                              */
/* ------------------------------------------------------------------------ */
typedef struct {
    const char *name;
    uint32_t    idx;     /* APB slot: stall target and monitor id alike      */
    uint32_t    rprobe;  /* register the timing tests read                   */
    uint32_t    rval;    /* what it reads while the slot is healthy          */
    uint32_t    wprobe;  /* register the store test writes                   */
    uint32_t    wmask;   /* implemented bits of wprobe                       */
    uint32_t    wrst;    /* value wprobe is restored to                      */
    uint32_t    to_lo;   /* elapsed-cycle window for an aborted access       */
    uint32_t    to_hi;
} slot_t;

/* Probe registers are chosen so that a REPEATED access is harmless. A forced
 * stall holds PSEL and PENABLE asserted for the whole threshold, and most of
 * these slaves act on every such cycle rather than only on the last one, so a
 * FIFO port, a self-clearing command register or GPIO SET/CLEAR/TOGGLE would
 * be acted on many times over. Plain storage registers are not.
 *
 * LSR is the UART read probe for the same reason (reading RBR would pop the
 * RX FIFO), but it is read-only - a store to it answers PSLVERR - so the store
 * test uses IER. Every other slot reads and writes the same register. */
static const slot_t slots[] = {
    { "I2C",    0, I2C_BASE    + 0x00,  0x00000000u, I2C_BASE    + 0x00,  0x0000FFFFu, 0, 16,    600   },
    { "TIMER0", 1, TIMER0_BASE + T_CMP, 0x00000000u, TIMER0_BASE + T_CMP, ALL,         0, 16,    600   },
    { "UART",   2, UART_BASE   + U_LSR, 0x00000060u, UART_BASE   + U_IER, 0x000000FFu, 0, 16,    600   },
    { "GPIO",   3, GPIO_BASE   + G_OUT, 0x00000000u, GPIO_BASE   + G_OUT, ALL,         0, 16,    600   },
    { "SPI",    4, SPI_BASE    + S_CLKDIV, 0x00000000u, SPI_BASE + S_CLKDIV, 0x000000FFu, 0, 60000, 75000 },
    { "TIMER1", 5, TIMER1_BASE + T_CMP, 0x00000000u, TIMER1_BASE + T_CMP, ALL,         0, 16,    600   },
};
#define N_SLOTS ((uint32_t)(sizeof(slots) / sizeof(slots[0])))

/* ==========================================================================
 *  PHASE 1: one forced stall per APB slot
 * ======================================================================== */
static void phase1_apb_slots(void)
{
    section("PHASE 1: APB timeout monitor, one forced stall per slot");

    for (uint32_t i = 0; i < N_SLOTS; i++) {
        const slot_t *s = &slots[i];
        acc_t         base, to, blk, st, rec;
        uint32_t      pat;

        /* --- baseline: how long a healthy access to this slot takes ---- */
        timed_read(&base, s->rprobe);
        check(s->name, "probe", "healthy read: no trap",   s->rprobe, 0,       base.traps);
        check(s->name, "probe", "healthy read: value",     s->rprobe, s->rval, base.data);

        tb_monclr();

        /* --- 1. the counter runs out ----------------------------------- */
        tb_stall(s->idx);
        timed_read(&to, s->rprobe);
        expect_trap(s->name, "stalled load", &to, s->rprobe, 5);
        check_ge(s->name, "stalled load", "elapsed cycles >= threshold",
                 s->rprobe, s->to_lo, to.cyc);
        check_le(s->name, "stalled load", "elapsed cycles <= threshold + margin",
                 s->rprobe, s->to_hi, to.cyc);
        tb_monchk(s->idx, 1);

        /* --- 2. blocked: answered at once, counter not re-run ----------- */
        timed_read(&blk, s->rprobe);
        expect_trap(s->name, "blocked load", &blk, s->rprobe, 5);
        check_ge(s->name, "blocked load", "at least 10 cycles faster than the first abort",
                 s->rprobe, blk.cyc + 10, to.cyc);
        check_le(s->name, "blocked load", "no slower than a healthy access + trap entry",
                 s->rprobe, base.cyc + 150, blk.cyc);
        tb_monchk(s->idx, 2);

        /* --- 3. a store aborts the same way, with mcause 7 -------------- */
        timed_write(&st, s->wprobe, 0x5A5A5A5Au);
        expect_trap(s->name, "stalled store", &st, s->wprobe, 7);
        tb_monchk(s->idx, 3);

        /* --- 4. sticky status is latched -------------------------------- */
        sticky_exp |= STK_APB(s->idx);
        tb_sticky(sticky_exp);

        /* --- 5. recovery ------------------------------------------------ */
        tb_release();
        delay(64);
        tb_monclr();

        pat = 0x5A5A5A5Au & s->wmask;
        wr32(s->wprobe, pat);
        check(s->name, "recovery", "write lands after the slot recovers",
              s->wprobe, pat, rd32(s->wprobe));
        wr32(s->wprobe, s->wrst);

        timed_read(&rec, s->rprobe);
        check(s->name, "recovery", "read takes no trap", s->rprobe, 0, rec.traps);
        check_le(s->name, "recovery", "read back at healthy latency",
                 s->rprobe, base.cyc + 40, rec.cyc);
        tb_monchk(MON_NONE, 0);
    }
}

/* ==========================================================================
 *  PHASE 2: the SPI master stalling on its own, which is the real case
 * ======================================================================== */
static void phase2_spi_natural(void)
{
    const char *ip = "SPI";
    uint32_t    b  = SPI_BASE;
    acc_t       r1, r2, r3;
    uint32_t    st, n;

    section("PHASE 2a: SPI empty-RXFIFO read aborts and loses no data");

    wr32(b + S_STATUS, 0x10);            /* swrst: both FIFOs empty */
    check(ip, "STATUS", "idle, FIFOs empty", b + S_STATUS, 0x00000001u, rd32(b + S_STATUS));

    tb_monclr();
    timed_read(&r1, b + S_RXFIFO);
    expect_trap(ip, "empty RXFIFO read", &r1, b + S_RXFIFO, 5);
    check_ge(ip, "empty RXFIFO read", "elapsed cycles >= 65536",
             b + S_RXFIFO, 60000, r1.cyc);
    check_le(ip, "empty RXFIFO read", "elapsed cycles <= 65536 + margin",
             b + S_RXFIFO, 75000, r1.cyc);
    tb_monchk(MON_APB4, 1);
    check(ip, "STATUS", "FIFO levels unchanged by the abort",
          b + S_STATUS, 0x00000001u, rd32(b + S_STATUS));

    /* The SPI master drops PREADY only while it is selected, so the monitor's
     * block clears as soon as PSEL falls: the next empty read pays the full
     * threshold again. This is the documented difference from a slave that is
     * stuck low permanently (phase 1, step 2). */
    timed_read(&r2, b + S_RXFIFO);
    expect_trap(ip, "second empty RXFIFO read", &r2, b + S_RXFIFO, 5);
    check_ge(ip, "second empty RXFIFO read", "block cleared: full threshold again",
             b + S_RXFIFO, 60000, r2.cyc);
    tb_monchk(MON_APB4, 2);

    section("PHASE 2b: SPI full-TXFIFO write aborts and loses no data");

    for (uint32_t k = 1; k <= 10; k++)
        wr32(b + S_TXFIFO, k | (k << 8) | (k << 16) | (k << 24));
    check(ip, "STATUS", "TX level 10, controller idle",
          b + S_STATUS, 0x0A000001u, rd32(b + S_STATUS));

    tb_monclr();
    timed_write(&r3, b + S_TXFIFO, 0xDEADBEEFu);
    expect_trap(ip, "full TXFIFO write", &r3, b + S_TXFIFO, 7);
    check_ge(ip, "full TXFIFO write", "elapsed cycles >= 65536",
             b + S_TXFIFO, 60000, r3.cyc);
    tb_monchk(MON_APB4, 1);
    check(ip, "STATUS", "11th word was not accepted",
          b + S_STATUS, 0x0A000001u, rd32(b + S_STATUS));

    wr32(b + S_STATUS, 0x10);
    check(ip, "STATUS", "swrst empties the TX FIFO", b + S_STATUS, 0x00000001u, rd32(b + S_STATUS));

    section("PHASE 2c: longest LEGITIMATE SPI wait must not abort");

    /* Worst case the 65536 threshold was sized for: the slowest divider, and a
     * blocking RXFIFO read issued before the first word exists.
     *   CLKDIV 255 -> 2 x (255+1) = 512 clk per SPI bit
     *   8 cmd + 24 addr + 32 data = 64 bits before word 0 lands = 32768 clk
     * With 8 dummy bits as well it would be 36864, still inside the threshold.
     * The CS1 model shifts 0xC3A55A3C_0F1E2D4B out from the first SCK edge, so
     * after 32 bits of command and address, word 0 is 0x0F1E2D4B. */
    wr32(b + S_CLKDIV, 255);
    wr32(b + S_SPICMD, 0);
    wr32(b + S_SPIADR, 0);
    wr32(b + S_SPIDUM, 0);
    wr32(b + S_SPILEN, (64u << 16) | (24u << 8) | 8u);

    tb_monclr();
    wr32(b + S_STATUS, (0x2u << 8) | 0x1u);   /* CS1, standard read */

    timed_read(&r1, b + S_RXFIFO);            /* blocks ~32768 cycles */
    check(ip, "RXFIFO", "legitimate long wait takes no trap", b + S_RXFIFO, 0, r1.traps);
    check(ip, "RXFIFO", "word 0 from the CS1 slave", b + S_RXFIFO, 0x0F1E2D4Bu, r1.data);
    check_ge(ip, "RXFIFO", "waited for the SPI transfer, not for the monitor",
             b + S_RXFIFO, 28000, r1.cyc);
    check_le(ip, "RXFIFO", "wait stayed below the 65536 threshold",
             b + S_RXFIFO, 50000, r1.cyc);

    timed_read(&r2, b + S_RXFIFO);            /* blocks ~16384 more */
    check(ip, "RXFIFO", "word 1 takes no trap", b + S_RXFIFO, 0, r2.traps);
    check(ip, "RXFIFO", "word 1 from the CS1 slave", b + S_RXFIFO, 0x00000000u, r2.data);
    tb_monchk(MON_NONE, 0);

    n = 0;
    do {
        st = rd32(b + S_STATUS);
    } while (!(st & 0x1u) && ++n < 4000);
    check(ip, "STATUS", "controller idle after the transfer", b + S_STATUS, 0x00000001u, st);

    wr32(b + S_STATUS, 0x10);
    wr32(b + S_CLKDIV, 0);
    wr32(b + S_SPILEN, 0);
}

/* ==========================================================================
 *  PHASE 3: AXI-Lite monitor, with the APB bridge frozen before it drives PSEL
 * ======================================================================== */
static void phase3_axi(void)
{
    const char *ip = "AXI";
    uint32_t    a  = TIMER0_BASE + T_CMP;
    acc_t       to, drain, rec;

    section("PHASE 3a: AXI read timeout, orphan drained, no APB monitor fires");

    wr32(a, 0);
    tb_monclr();
    tb_stall(ST_AXI);

    timed_read(&to, a);
    expect_trap(ip, "read, bridge frozen", &to, a, 5);
    check_ge(ip, "read, bridge frozen", "elapsed cycles >= 131072", a, 125000, to.cyc);
    check_le(ip, "read, bridge frozen", "elapsed cycles <= 131072 + margin", a, 150000, to.cyc);
    /* The bridge never reached its Access phase, so PSEL/PENABLE never went
     * high and no APB slot counter ever started. Only the AXI read monitor may
     * have fired. */
    tb_monchk(MON_AXI_RD, 1);

    sticky_exp |= STK_AXI_RD;
    tb_sticky(sticky_exp);

    /* While the orphan is still outstanding the monitor errors new reads at
     * once rather than forwarding them into the collision. */
    timed_read(&drain, a);
    expect_trap(ip, "read while draining", &drain, a, 5);
    check_le(ip, "read while draining", "failed immediately, counter not re-run",
             a, 2000, drain.cyc);

    tb_release();
    delay(256);
    tb_monclr();

    timed_read(&rec, a);
    check(ip, "recovery", "read takes no trap after the bridge is released", a, 0, rec.traps);
    check(ip, "recovery", "value is the real register, not the orphan's late data",
          a, 0, rec.data);
    check_le(ip, "recovery", "back to healthy latency", a, 2000, rec.cyc);
    tb_monchk(MON_NONE, 0);

    section("PHASE 3b: AXI write timeout; the accepted write still lands");

    tb_monclr();
    tb_stall(ST_AXI);

    timed_write(&to, a, 0x1234ABCDu);
    expect_trap(ip, "write, bridge frozen", &to, a, 7);
    check_ge(ip, "write, bridge frozen", "elapsed cycles >= 131072", a, 125000, to.cyc);
    check_le(ip, "write, bridge frozen", "elapsed cycles <= 131072 + margin", a, 150000, to.cyc);
    tb_monchk(MON_AXI_WR, 1);

    sticky_exp |= STK_AXI_WR;
    tb_sticky(sticky_exp);

    timed_write(&drain, a, 0xFFFFFFFFu);
    expect_trap(ip, "write while draining", &drain, a, 7);
    check_le(ip, "write while draining", "failed immediately, counter not re-run",
             a, 2000, drain.cyc);

    tb_release();
    delay(256);
    tb_monclr();

    /* The first write was already inside the bridge when the monitor gave up on
     * it, so it completes once the bridge runs again: the monitor can end the
     * CPU's wait but cannot cancel a request the fabric has accepted. The
     * second write was answered by the monitor and never forwarded, so
     * 0xFFFFFFFF must NOT be there. */
    check(ip, "orphan write", "aborted write lands on release, drained write does not",
          a, 0x1234ABCDu, rd32(a));

    wr32(a, 0);
    check(ip, "recovery", "slot writable again", a, 0, rd32(a));
    tb_monchk(MON_NONE, 0);
}

/* ==========================================================================
 *  PHASE 4: no monitor may fire on healthy traffic
 * ======================================================================== */
/* Read/write bursts with no idle cycle between them: an APB monitor whose
 * counter does not clear at the end of a transfer would fire here. */
static void hammer_rw(const slot_t *s, uint32_t n)
{
    for (uint32_t i = 0; i < n; i++) {
        (void)rd32(s->rprobe);
        wr32(s->wprobe, s->wrst);
        (void)rd32(s->rprobe);
    }
}

/* Read-only variant, used while the peripherals are mid-transfer: writing the
 * probe registers then would change a divider or a compare value under a
 * running peripheral. */
static void hammer_rd(const slot_t *s, uint32_t n)
{
    for (uint32_t i = 0; i < n; i++) {
        (void)rd32(s->rprobe);
        (void)rd32(s->rprobe);
        (void)rd32(s->rprobe);
    }
}

static void phase4_no_false_fire(void)
{
    const char *ip = "BUS";
    uint32_t    st, n;

    section("PHASE 4a: back-to-back traffic on each slot, no monitor may fire");

    for (uint32_t i = 0; i < N_SLOTS; i++) {
        tb_monclr();
        hammer_rw(&slots[i], 50);
        tb_monchk(MON_NONE, 0);
        check(slots[i].name, "no false timeout", "150 back-to-back accesses",
              slots[i].rprobe, slots[i].rval, rd32(slots[i].rprobe));
    }

    section("PHASE 4b: the same with three peripherals actually running");

    /* Timer 0 channel 0 counting, compare far away so no IRQ fires with EN=1
     * and none can be pending when it is switched off again. */
    wr32(TIMER0_BASE + T_CMP,  ALL);
    wr32(TIMER0_BASE + T_VAL,  0);
    wr32(TIMER0_BASE + T_CTRL, 1);

    /* UART transmitting into its own receiver */
    wr32(UART_BASE + U_LCR, 0x80);
    wr32(UART_BASE + 0x00,  0x02);          /* DLL = 2 */
    wr32(UART_BASE + 0x04,  0x00);          /* DLM = 0 */
    wr32(UART_BASE + U_LCR, 0x03);          /* 8N1, DLAB = 0 */
    wr32(UART_BASE + U_FCR, 0x07);
    wr32(UART_BASE + U_MCR, 0x10);          /* loopback */
    wr32(UART_BASE + U_THR, 0xA5);

    /* SPI transfer in flight on CS1. CLKDIV = 1, not 0: at CLKDIV = 0 the SCK
     * period is 2 clk and the testbench's CS1 model, which loads its shift
     * register on the CS falling edge and shifts on every SCK falling edge,
     * loses the first bit to the scheduler -- every word comes back shifted
     * left by one. That is a limitation of the behavioural slave, not of the
     * SPI master. Nothing below writes CLKDIV, so the transfer is safe. */
    wr32(SPI_BASE + S_CLKDIV, 1);
    wr32(SPI_BASE + S_SPICMD, 0);
    wr32(SPI_BASE + S_SPIADR, 0);
    wr32(SPI_BASE + S_SPIDUM, 0);
    wr32(SPI_BASE + S_SPILEN, 64u << 16);
    wr32(SPI_BASE + S_STATUS, (0x2u << 8) | 0x1u);

    tb_monclr();
    for (uint32_t i = 0; i < N_SLOTS; i++)
        hammer_rd(&slots[i], 20);
    tb_monchk(MON_NONE, 0);

    /* Drain everything that was started, never reading an empty FIFO. */
    n = 0;
    do {
        st = rd32(SPI_BASE + S_STATUS);
    } while (!((st & 0x1u) && (((st >> 16) & 0x1Fu) == 2u)) && ++n < 8000);
    check(ip, "SPI", "transfer survived the MMIO hammering",
          SPI_BASE + S_STATUS, 0x00020001u, st);
    if (((st >> 16) & 0x1Fu) == 2u) {
        check(ip, "SPI", "word 0 intact", SPI_BASE + S_RXFIFO, 0xC3A55A3Cu, rd32(SPI_BASE + S_RXFIFO));
        check(ip, "SPI", "word 1 intact", SPI_BASE + S_RXFIFO, 0x0F1E2D4Bu, rd32(SPI_BASE + S_RXFIFO));
    }
    wr32(SPI_BASE + S_STATUS, 0x10);
    wr32(SPI_BASE + S_SPILEN, 0);

    n = 0;
    do {
        st = rd32(UART_BASE + U_LSR);
    } while (!(st & 0x01u) && ++n < 8000);
    check(ip, "UART", "loopback byte survived the MMIO hammering",
          UART_BASE + U_RBR, 0xA5, rd32(UART_BASE + U_RBR));
    wr32(UART_BASE + U_MCR, 0x00);
    wr32(UART_BASE + U_FCR, 0x06);
    wr32(UART_BASE + U_LCR, 0x00);

    st = rd32(TIMER0_BASE + T_VAL);
    wr32(TIMER0_BASE + T_CTRL, 0);
    check_ge(ip, "TIMER0", "counter advanced while the bus was busy",
             TIMER0_BASE + T_VAL, 1, st);
    wr32(TIMER0_BASE + T_CMP, 0);

    /* Every sticky bit set earlier must still be set, and nothing new. */
    tb_sticky(sticky_exp);
}

/* ------------------------------------------------------------------------ */
int main(void)
{
    section("RISCFORGE bus timeout monitor test: firmware started");

    /* Nothing has failed yet, so no sticky bit may be set. */
    tb_sticky(0);
    tb_monchk(MON_NONE, 0);

    phase1_apb_slots();
    phase2_spi_natural();
    phase3_axi();
    phase4_no_false_fire();

    section("PHASE 5: summary");
    check("CORE", "trap handler", "traps taken == traps expected", 0, n_exp_traps, g_trap.total);

    report(CMD_DONE, "", "", "", n_pass, n_fail, g_trap.total);
    return 0;
}
