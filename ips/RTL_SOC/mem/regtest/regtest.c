/* =============================================================================
 * RISCFORGE 1TOPS - peripheral register access test (firmware)
 * =============================================================================
 * Runs on the RV32 core after a real SPI-flash cold boot. Every access goes
 * through the full path:
 *     core LSU -> hybrid_mem_interface -> axi_lite_xbar -> axi_lite_to_apb -> IP
 *
 * Results are posted to a mailbox at DSRAM 0x0002_0000, which
 * soc_regtest_tb.sv watches (see mbox_post). The TB prints every FAIL, keeps
 * the totals, and cross-checks the bus response type (SLVERR vs DECERR) of
 * every access that is expected to fault.
 *
 * Phases
 *   1  reset value of every register, before anything is written
 *   2  read-only registers: a write is ignored (OKAY response, value unchanged)
 *   3  read/write registers: 0, all-ones, 0xAAAA_AAAA, 0x5555_5555 and a
 *      walking one (36 patterns), read back through the implemented-bit mask
 *   4  per-IP uniqueness: write a distinct value to every R/W register, then
 *      read them all (catches two offsets decoding to the same register)
 *   5  command / FIFO / W1C registers that cannot be pattern-tested
 *   6  unmapped offsets inside a window (read 0, write ignored) and aliases
 *   7  accesses that must fault (bus error -> access-fault trap)
 *   8  unexpected-trap check and DONE
 *
 * Firmware rules followed (see project notes):
 *   - 32-bit MMIO stores only. The only byte/half-word stores are in
 *     neg_store8/neg_store16, used for the GPIO sub-word negative test.
 *     build.py fails the build if any other function contains lb/lh/sb/sh.
 *   - SPI: RXFIFO is only read when STATUS[20:16] != 0, TXFIFO holds at most
 *     10 words (an empty read / full write would stall the bus for ever).
 *   - UART: no register other than DLL/DLM is read while LCR.DLAB = 1, except
 *     the one deliberate negative test in phase 7.
 *
 * Testbench dependencies (soc_regtest_tb.sv)
 *   - GPIO pads looped back: gpio_in_i = gpio_out_o
 *   - SPI chip select 1 has a slave model that returns 0xC3A55A3C_0F1E2D4B
 *   - I2C SCL/SDA pulled up, UART RX idle high
 *
 * Built for rv32i_zicsr (no M extension: rv32m_mul.v is not yet signed off).
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

/* I2C */
#define I2C_PRE   0x00u
#define I2C_CTR   0x04u
#define I2C_SR    0x0Cu
#define I2C_CR    0x14u

/* Timer (per channel, channel n at +0x10*n) */
#define T_VAL     0x00u
#define T_CTRL    0x04u
#define T_CMP     0x08u

/* UART (DLAB = 0 unless noted) */
#define U_RBR     0x00u   /* read  */
#define U_THR     0x00u   /* write */
#define U_DLL     0x00u   /* DLAB = 1 */
#define U_IER     0x04u
#define U_DLM     0x04u   /* DLAB = 1 */
#define U_IIR     0x08u   /* read  */
#define U_FCR     0x08u   /* write */
#define U_LCR     0x0Cu
#define U_MCR     0x10u
#define U_LSR     0x14u
#define U_MSR     0x18u

/* GPIO (reggen offsets, gpio_reg_pkg.sv) */
#define G_EN            0x080u
#define G_IN            0x100u
#define G_OUT           0x180u
#define G_SET           0x200u
#define G_CLEAR         0x280u
#define G_TOGGLE        0x300u
#define G_RISE_EN       0x380u
#define G_FALL_EN       0x400u
#define G_LVL_HIGH_EN   0x480u
#define G_LVL_LOW_EN    0x500u
#define G_STATUS        0x580u
#define G_RISE_STATUS   0x600u
#define G_FALL_STATUS   0x680u
#define G_LVL_HIGH_STS  0x700u
#define G_LVL_LOW_STS   0x780u

/* SPI master */
#define S_STATUS  0x00u
#define S_CLKDIV  0x04u
#define S_SPICMD  0x08u
#define S_SPIADR  0x0Cu
#define S_SPILEN  0x10u
#define S_SPIDUM  0x14u
#define S_TXFIFO  0x18u
#define S_RXFIFO  0x20u

#define ALL       0xFFFFFFFFu

/* AXI response codes, as seen by the TB bus monitor */
#define RESP_SLVERR  2u
#define RESP_DECERR  3u

/* ------------------------------------------------------------------------ */
/*  Mailbox protocol (DSRAM 0x0002_0000, reserved by link.ld)               */
/*  The TB acts on the write to MB_CMD, which is always the last store.     */
/* ------------------------------------------------------------------------ */
#define MBOX_ADDR  0x00020000u
#define MB(i)      (*(volatile uint32_t *)(MBOX_ADDR + ((uint32_t)(i) << 2)))

enum { MB_CMD = 0, MB_IP, MB_NAME, MB_SUB, MB_ADDR, MB_EXP, MB_GOT };

enum {
    CMD_PASS    = 1,     /* check passed                                    */
    CMD_FAIL    = 2,     /* check failed: TB prints ip.name : sub, exp, got */
    CMD_SECTION = 3,     /* progress banner                                 */
    CMD_BUSRESP = 4,     /* TB: last bus error must be at ADDR with resp EXP */
    CMD_DONE    = 0xD0   /* ADDR = passes, EXP = fails, GOT = total traps   */
};

/* ------------------------------------------------------------------------ */
/*  Trap record, written by trap_entry in startup.S                         */
/* ------------------------------------------------------------------------ */
typedef struct {
    uint32_t count;      /* cleared by the firmware before a probe */
    uint32_t cause;
    uint32_t tval;
    uint32_t epc;
    uint32_t total;      /* never cleared */
} trap_rec_t;

volatile trap_rec_t g_trap;

static uint32_t n_pass, n_fail, n_exp_traps;

/* ------------------------------------------------------------------------ */
/*  Low-level helpers                                                       */
/* ------------------------------------------------------------------------ */
static inline uint32_t rd32(uint32_t a)             { return *(volatile uint32_t *)a; }
static inline void     wr32(uint32_t a, uint32_t v) { *(volatile uint32_t *)a = v; }

/* The ONLY sub-word stores in the program (GPIO negative test). */
__attribute__((noinline)) static void neg_store8(uint32_t a, uint32_t v)
{
    *(volatile uint8_t *)a = (uint8_t)v;
}
__attribute__((noinline)) static void neg_store16(uint32_t a, uint32_t v)
{
    *(volatile uint16_t *)a = (uint16_t)v;
}

static void delay(uint32_t n)
{
    while (n--)
        __asm__ volatile ("nop");
}

#define P(s) ((uint32_t)(uintptr_t)(s))

static void mbox_post(uint32_t cmd, const char *ip, const char *name, const char *sub,
                      uint32_t addr, uint32_t exp, uint32_t got)
{
    MB(MB_IP)   = P(ip);
    MB(MB_NAME) = P(name);
    MB(MB_SUB)  = P(sub);
    MB(MB_ADDR) = addr;
    MB(MB_EXP)  = exp;
    MB(MB_GOT)  = got;
    MB(MB_CMD)  = cmd;
}

static void section(const char *title)
{
    mbox_post(CMD_SECTION, "", title, "", 0, 0, 0);
}

static void check(const char *ip, const char *name, const char *sub,
                  uint32_t addr, uint32_t exp, uint32_t got)
{
    if (got == exp) {
        n_pass++;
        mbox_post(CMD_PASS, ip, name, sub, addr, exp, got);
    } else {
        n_fail++;
        mbox_post(CMD_FAIL, ip, name, sub, addr, exp, got);
    }
}

/* ------------------------------------------------------------------------ */
/*  Register tables                                                         */
/* ------------------------------------------------------------------------ */
enum {
    K_RW  = 1,   /* reset value, 36 patterns, uniqueness                  */
    K_RO  = 2,   /* reset value, write of ~reset must be ignored (OKAY)   */
    K_RST = 3    /* reset value only; writes have side effects (phase 5/7) */
};

typedef struct {
    const char *name;
    uint32_t    off;
    uint32_t    kind;
    uint32_t    rst;     /* reset value                                    */
    uint32_t    rmask;   /* bits that read back what was written           */
    uint32_t    wmask;   /* bits the generic tests may write               */
} reg_t;

typedef struct {
    const char  *name;
    uint32_t     base;
    const reg_t *regs;
    uint32_t     nregs;
} ip_t;

#define NREGS(t) ((uint32_t)(sizeof(t) / sizeof((t)[0])))

/* apb_i2c.sv - PSLVERR tied 0. CR writes are ignored unless CTR.EN = 1. */
static const reg_t i2c_regs[] = {
    { "PRE", 0x00, K_RW,  0x00, 0x0000FFFFu, ALL },
    { "CTR", 0x04, K_RW,  0x00, 0x000000FFu, ALL },
    { "RXR", 0x08, K_RO,  0x00, 0x000000FFu, ALL },
    { "SR",  0x0C, K_RO,  0x00, 0x000000FFu, ALL },
    { "TXR", 0x10, K_RW,  0x00, 0x000000FFu, ALL },
    { "CR",  0x14, K_RST, 0x00, 0x000000FFu, 0   },
};

/* apb_timer.sv / timer.sv - two channels. CTRL bit 0 (EN) is kept out of the
 * generic tests so the counter never runs during them; phase 5 covers it.
 * CMP is listed before VAL because writing CMP clears VAL. */
static const reg_t timer_regs[] = {
    { "CH0 CMP",  0x08, K_RW, 0, ALL,         ALL         },
    { "CH0 CTRL", 0x04, K_RW, 0, 0xFFFFFFFEu, 0xFFFFFFFEu },
    { "CH0 VAL",  0x00, K_RW, 0, ALL,         ALL         },
    { "CH1 CMP",  0x18, K_RW, 0, ALL,         ALL         },
    { "CH1 CTRL", 0x14, K_RW, 0, 0xFFFFFFFEu, 0xFFFFFFFEu },
    { "CH1 VAL",  0x10, K_RW, 0, ALL,         ALL         },
};

/* obi_uart (16550-style), DLAB = 0 view. LCR bit 7 (DLAB) is kept out of the
 * generic tests: with DLAB = 1 every read except DLL/DLM returns PSLVERR.
 * MSR resets to 0x00 because the modem inputs are tied inactive in
 * riscforge_soc_subsystem.sv. SCR is not implemented (reads 0, write ignored). */
static const reg_t uart_regs[] = {
    { "RBR", 0x00, K_RST, 0x00, 0xFF, 0           },
    { "IER", 0x04, K_RW,  0x00, 0xFF, ALL         },
    { "IIR", 0x08, K_RST, 0xC1, 0xFF, 0           },
    { "LCR", 0x0C, K_RW,  0x00, 0x7F, 0xFFFFFF7Fu },
    { "MCR", 0x10, K_RW,  0x00, 0xFF, ALL         },
    { "LSR", 0x14, K_RST, 0x60, 0xFF, 0           },
    { "MSR", 0x18, K_RST, 0x00, 0xFF, 0           },
    { "SCR", 0x1C, K_RO,  0x00, 0xFF, ALL         },
};

/* gpio_reg_top.sv (reggen). Unmapped offsets return PSLVERR (phase 7). */
static const reg_t gpio_regs[] = {
    { "INFO",                   0x000, K_RO,  0x820, ALL, ALL },
    { "CFG",                    0x004, K_RW,  0,     0x3, ALL },
    { "GPIO_MODE_0",            0x008, K_RW,  0,     ALL, ALL },
    { "GPIO_MODE_1",            0x00C, K_RW,  0,     ALL, ALL },
    { "GPIO_EN",                0x080, K_RW,  0,     ALL, ALL },
    { "GPIO_IN",                0x100, K_RO,  0,     ALL, ALL },
    { "GPIO_OUT",               0x180, K_RW,  0,     ALL, ALL },
    { "GPIO_SET",               0x200, K_RST, 0,     ALL, 0   },
    { "GPIO_CLEAR",             0x280, K_RST, 0,     ALL, 0   },
    { "GPIO_TOGGLE",            0x300, K_RST, 0,     ALL, 0   },
    { "INTRPT_RISE_EN",         0x380, K_RW,  0,     ALL, ALL },
    { "INTRPT_FALL_EN",         0x400, K_RW,  0,     ALL, ALL },
    { "INTRPT_LVL_HIGH_EN",     0x480, K_RW,  0,     ALL, ALL },
    { "INTRPT_LVL_LOW_EN",      0x500, K_RW,  0,     ALL, ALL },
    { "INTRPT_STATUS",          0x580, K_RST, 0,     ALL, 0   },
    { "INTRPT_RISE_STATUS",     0x600, K_RST, 0,     ALL, 0   },
    { "INTRPT_FALL_STATUS",     0x680, K_RST, 0,     ALL, 0   },
    { "INTRPT_LVL_HIGH_STATUS", 0x700, K_RST, 0,     ALL, 0   },
    { "INTRPT_LVL_LOW_STATUS",  0x780, K_RST, 0,     ALL, 0   },
};

/* apb_spi_master.sv (through the bootloader APB passthrough). A STATUS write
 * is a command, so STATUS is reset-checked only. TXFIFO reads 0; INTSTA is not
 * in the read mux and reads 0. RXFIFO is only touched in phase 5. */
static const reg_t spi_regs[] = {
    { "STATUS", 0x00, K_RST, 0x00000001u, ALL,         0   },
    { "CLKDIV", 0x04, K_RW,  0,           0x000000FFu, ALL },
    { "SPICMD", 0x08, K_RW,  0,           ALL,         ALL },
    { "SPIADR", 0x0C, K_RW,  0,           ALL,         ALL },
    { "SPILEN", 0x10, K_RW,  0,           0xFFFF3F3Fu, ALL },
    { "SPIDUM", 0x14, K_RW,  0,           ALL,         ALL },
    { "TXFIFO", 0x18, K_RST, 0,           ALL,         0   },
    { "INTCFG", 0x24, K_RW,  0,           0xDF1F1F1Fu, ALL },
    { "INTSTA", 0x28, K_RST, 0,           ALL,         0   },
};

static const ip_t ips[] = {
    { "I2C",    I2C_BASE,    i2c_regs,   NREGS(i2c_regs)   },
    { "TIMER0", TIMER0_BASE, timer_regs, NREGS(timer_regs) },
    { "UART",   UART_BASE,   uart_regs,  NREGS(uart_regs)  },
    { "GPIO",   GPIO_BASE,   gpio_regs,  NREGS(gpio_regs)  },
    { "SPI",    SPI_BASE,    spi_regs,   NREGS(spi_regs)   },
    { "TIMER1", TIMER1_BASE, timer_regs, NREGS(timer_regs) },
};
#define N_IPS ((uint32_t)(sizeof(ips) / sizeof(ips[0])))

/* ------------------------------------------------------------------------ */
/*  Generic register tests                                                  */
/* ------------------------------------------------------------------------ */
static const uint32_t fixed_pats[4] = { 0x00000000u, 0xFFFFFFFFu, 0xAAAAAAAAu, 0x55555555u };

/* 36 patterns; every mismatch is a FAIL (first 4 reported individually). */
static void rw_patterns(const char *ip, const char *name, uint32_t a,
                        uint32_t rmask, uint32_t wmask, uint32_t restore)
{
    uint32_t errs = 0;

    for (uint32_t i = 0; i < 36; i++) {
        uint32_t p   = ((i < 4) ? fixed_pats[i] : (1u << (i - 4))) & wmask;
        uint32_t exp = p & rmask;
        uint32_t got;

        wr32(a, p);
        got = rd32(a);
        if (got != exp) {
            errs++;
            if (errs <= 4) {
                n_fail++;
                mbox_post(CMD_FAIL, ip, name, "RW pattern readback", a, exp, got);
            }
        }
    }
    wr32(a, restore);

    if (errs == 0) {
        n_pass++;
        mbox_post(CMD_PASS, ip, name, "RW patterns (36)", a, 0, 0);
    } else if (errs > 4) {
        n_fail++;
        mbox_post(CMD_FAIL, ip, name, "further RW mismatches (got = total)", a, 4, errs);
    }
}

static uint32_t sig(uint32_t i)
{
    uint32_t b = (i + 0x11u) & 0xFFu;
    return (b << 24) | ((b ^ 0x5Au) << 16) | ((b ^ 0xA5u) << 8) | (b ^ 0x3Cu);
}

static void phase1_reset_values(void)
{
    section("PHASE 1: reset values (read before any write)");
    for (uint32_t i = 0; i < N_IPS; i++)
        for (uint32_t j = 0; j < ips[i].nregs; j++) {
            const reg_t *r = &ips[i].regs[j];
            uint32_t     a = ips[i].base + r->off;
            check(ips[i].name, r->name, "reset value", a, r->rst, rd32(a));
        }
}

static void phase2_ro_writes(void)
{
    section("PHASE 2: read-only registers ignore writes");
    for (uint32_t i = 0; i < N_IPS; i++)
        for (uint32_t j = 0; j < ips[i].nregs; j++) {
            const reg_t *r = &ips[i].regs[j];
            uint32_t     a = ips[i].base + r->off;
            if (r->kind != K_RO)
                continue;
            wr32(a, ~r->rst);
            check(ips[i].name, r->name, "write ignored", a, r->rst, rd32(a));
        }
}

static void phase3_rw_patterns(void)
{
    section("PHASE 3: read/write registers, 36 patterns each");
    for (uint32_t i = 0; i < N_IPS; i++)
        for (uint32_t j = 0; j < ips[i].nregs; j++) {
            const reg_t *r = &ips[i].regs[j];
            if (r->kind == K_RW)
                rw_patterns(ips[i].name, r->name, ips[i].base + r->off,
                            r->rmask, r->wmask, r->rst);
        }
}

static void phase4_uniqueness(void)
{
    section("PHASE 4: per-IP uniqueness (distinct value in every R/W register)");
    for (uint32_t i = 0; i < N_IPS; i++) {
        const ip_t *ip = &ips[i];
        for (uint32_t inv = 0; inv < 2; inv++) {
            for (uint32_t j = 0; j < ip->nregs; j++) {
                const reg_t *r = &ip->regs[j];
                uint32_t     v = inv ? ~sig(j) : sig(j);
                if (r->kind == K_RW)
                    wr32(ip->base + r->off, v & r->wmask);
            }
            for (uint32_t j = 0; j < ip->nregs; j++) {
                const reg_t *r = &ip->regs[j];
                uint32_t     v = inv ? ~sig(j) : sig(j);
                if (r->kind == K_RW)
                    check(ip->name, r->name, inv ? "unique value (inverted)" : "unique value",
                          ip->base + r->off, v & r->wmask & r->rmask, rd32(ip->base + r->off));
            }
        }
        for (uint32_t j = 0; j < ip->nregs; j++) {
            const reg_t *r = &ip->regs[j];
            if (r->kind == K_RW)
                wr32(ip->base + r->off, r->rst);
        }
    }
}

/* ------------------------------------------------------------------------ */
/*  Phase 5: registers with side effects                                    */
/* ------------------------------------------------------------------------ */
static void i2c_special(void)
{
    const char *ip = "I2C";
    uint32_t    b  = I2C_BASE;

    section("PHASE 5: I2C command register");
    wr32(b + I2C_CTR, 0x00);
    wr32(b + I2C_CR, 0x08);
    check(ip, "CR", "write ignored while CTR.EN=0", b + I2C_CR, 0x00, rd32(b + I2C_CR));

    wr32(b + I2C_CTR, 0x80);
    wr32(b + I2C_CR, 0x08);               /* ACK bit only: no bus command */
    check(ip, "CR", "ACK bit holds with CTR.EN=1", b + I2C_CR, 0x08, rd32(b + I2C_CR));
    wr32(b + I2C_CR, 0x01);               /* IACK */
    check(ip, "CR", "IACK self-clears", b + I2C_CR, 0x00, rd32(b + I2C_CR));
    wr32(b + I2C_CTR, 0x00);
    check(ip, "SR", "bus idle after CR tests", b + I2C_SR, 0x00, rd32(b + I2C_SR));
}

static void timer_special(const char *ip, uint32_t b)
{
    section("PHASE 5: timer enable, CMP side effect, disabled-timer hold");
    for (uint32_t ch = 0; ch < 2; ch++) {
        const char *nm  = ch ? "CH1" : "CH0";
        uint32_t    val = b + (ch << 4) + T_VAL;
        uint32_t    ctl = b + (ch << 4) + T_CTRL;
        uint32_t    cmp = b + (ch << 4) + T_CMP;
        uint32_t    v0, v1;

        wr32(val, 0);
        wr32(ctl, 1);                     /* EN = 1, prescaler bypass */
        v0 = rd32(val);
        delay(8);
        v1 = rd32(val);
        wr32(ctl, 0);
        check(ip, nm, "VAL counts while CTRL.EN=1 (1 = yes)", val, 1, (v1 > v0) ? 1u : 0u);

        v0 = rd32(val);
        delay(8);
        check(ip, nm, "VAL holds while CTRL.EN=0", val, v0, rd32(val));

        wr32(val, 0x1234);
        wr32(cmp, 0x10);
        check(ip, nm, "CMP write clears VAL", val, 0, rd32(val));

        /* Issue 4 fix: with EN=0 no IRQ, so VAL is not auto-cleared */
        wr32(cmp, 0x100);
        wr32(val, 0x100);
        delay(16);
        check(ip, nm, "EN=0: VAL==CMP is not cleared", val, 0x100, rd32(val));
        wr32(val, 0xFFFFFFFFu);
        delay(16);
        check(ip, nm, "EN=0: VAL=0xFFFFFFFF is not cleared", val, 0xFFFFFFFFu, rd32(val));

        wr32(cmp, 0);                     /* also clears VAL */
        check(ip, nm, "VAL back to 0", val, 0, rd32(val));
    }
}

static void uart_special(void)
{
    const char *ip = "UART";
    uint32_t    b  = UART_BASE;
    uint32_t    lsr;

    section("PHASE 5: UART divisor latch (DLAB=1)");
    wr32(b + U_LCR, 0x80);
    check(ip, "DLL", "reset value", b + U_DLL, 0x01, rd32(b + U_DLL));
    check(ip, "DLM", "reset value", b + U_DLM, 0x00, rd32(b + U_DLM));
    rw_patterns(ip, "DLL", b + U_DLL, 0xFF, ALL, 0x02);   /* leave divisor = 2 */
    rw_patterns(ip, "DLM", b + U_DLM, 0xFF, ALL, 0x00);
    wr32(b + U_LCR, 0x03);                /* 8N1, DLAB=0 (LCR write allowed with DLAB=1) */
    check(ip, "LCR", "DLAB cleared by write", b + U_LCR, 0x03, rd32(b + U_LCR));
    check(ip, "IER", "not changed by DLM writes", b + U_IER, 0x00, rd32(b + U_IER));

    section("PHASE 5: UART THR -> RBR through MCR loopback");
    wr32(b + U_FCR, 0x07);                /* FIFO enable + reset RX/TX FIFO */
    (void)rd32(b + U_LSR);                /* drain anything the earlier LCR/MCR */
    for (uint32_t n = 0; (rd32(b + U_LSR) & 0x01u) && n < 32; n++)   /* patterns */
        (void)rd32(b + U_RBR);            /* may have looped into RX            */
    (void)rd32(b + U_LSR);
    wr32(b + U_MCR, 0x10);                /* loopback */
    for (uint32_t k = 0; k < 2; k++) {
        uint32_t byte = k ? 0x5Au : 0xA5u;
        uint32_t n    = 0;

        wr32(b + U_THR, byte);
        do {
            lsr = rd32(b + U_LSR);
        } while (!(lsr & 0x01u) && ++n < 4000);
        check(ip, "LSR", "data ready after loopback TX (DR=1)", b + U_LSR, 1, lsr & 0x01u);
        check(ip, "RBR", "loopback byte", b + U_RBR, byte, rd32(b + U_RBR));
    }
    {   /* RX flags DR mid-stop-bit while TX is still sending it: wait for TEMT */
        uint32_t n = 0;
        do {
            lsr = rd32(b + U_LSR);
        } while (lsr != 0x60u && ++n < 4000);
    }
    check(ip, "LSR", "idle, RX empty after reads (THRE+TEMT)", b + U_LSR, 0x60, lsr);

    wr32(b + U_MCR, 0x00);
    wr32(b + U_FCR, 0x06);                /* reset FIFOs, FIFO off */
    wr32(b + U_LCR, 0x00);
    (void)rd32(b + U_MSR);                /* clears the delta bits set by loopback */
    check(ip, "MSR", "delta bits clear on read", b + U_MSR, 0x00, rd32(b + U_MSR));
    (void)rd32(b + U_IIR);
}

static void gpio_special(void)
{
    const char *ip = "GPIO";
    uint32_t    b  = GPIO_BASE;

    section("PHASE 5: GPIO SET / CLEAR / TOGGLE");
    wr32(b + G_EN, 0);
    wr32(b + G_STATUS, ALL);              /* clean up after the uniqueness pass */
    wr32(b + G_OUT, 0);
    wr32(b + G_SET, 0xF0F0F0F0u);
    check(ip, "GPIO_SET",    "sets GPIO_OUT bits",     b + G_OUT, 0xF0F0F0F0u, rd32(b + G_OUT));
    wr32(b + G_CLEAR, 0x30303030u);
    check(ip, "GPIO_CLEAR",  "clears GPIO_OUT bits",   b + G_OUT, 0xC0C0C0C0u, rd32(b + G_OUT));
    wr32(b + G_TOGGLE, 0xFFFF0000u);
    check(ip, "GPIO_TOGGLE", "toggles GPIO_OUT bits",  b + G_OUT, 0x3F3FC0C0u, rd32(b + G_OUT));
    check(ip, "GPIO_SET",    "reads 0",                b + G_SET,    0, rd32(b + G_SET));
    check(ip, "GPIO_CLEAR",  "reads 0",                b + G_CLEAR,  0, rd32(b + G_CLEAR));
    check(ip, "GPIO_TOGGLE", "reads 0",                b + G_TOGGLE, 0, rd32(b + G_TOGGLE));
    wr32(b + G_OUT, 0);

    section("PHASE 5: GPIO_IN through TB pad loopback");
    wr32(b + G_EN, ALL);
    wr32(b + G_OUT, 0xA5A55A5Au);
    delay(8);
    check(ip, "GPIO_IN", "samples pads (loopback)", b + G_IN, 0xA5A55A5Au, rd32(b + G_IN));
    wr32(b + G_OUT, 0x5A5AA5A5u);
    delay(8);
    check(ip, "GPIO_IN", "samples pads (loopback)", b + G_IN, 0x5A5AA5A5u, rd32(b + G_IN));
    wr32(b + G_OUT, 0);
    delay(8);
    wr32(b + G_EN, 0);
    wr32(b + G_OUT, 0xFFFF0000u);
    delay(8);
    check(ip, "GPIO_IN", "frozen while GPIO_EN=0", b + G_IN, 0, rd32(b + G_IN));
    wr32(b + G_OUT, 0);

    section("PHASE 5: GPIO interrupt status registers (W1C) on pin 0");
    wr32(b + G_EN, 0x1);
    delay(8);
    wr32(b + G_STATUS, ALL);
    check(ip, "INTRPT_STATUS", "clear before test", b + G_STATUS, 0, rd32(b + G_STATUS));

    wr32(b + G_RISE_EN, 0x1);
    wr32(b + G_OUT, 0x1);
    delay(8);
    check(ip, "INTRPT_RISE_STATUS", "set by rising edge", b + G_RISE_STATUS, 1, rd32(b + G_RISE_STATUS));
    check(ip, "INTRPT_STATUS",      "OR of per-type status", b + G_STATUS, 1, rd32(b + G_STATUS));
    wr32(b + G_RISE_STATUS, 0x0);
    check(ip, "INTRPT_RISE_STATUS", "writing 0 clears nothing", b + G_RISE_STATUS, 1, rd32(b + G_RISE_STATUS));
    wr32(b + G_RISE_STATUS, 0x1);
    check(ip, "INTRPT_RISE_STATUS", "W1C clears", b + G_RISE_STATUS, 0, rd32(b + G_RISE_STATUS));
    check(ip, "INTRPT_STATUS",      "clear after W1C", b + G_STATUS, 0, rd32(b + G_STATUS));
    wr32(b + G_RISE_EN, 0);

    wr32(b + G_FALL_EN, 0x1);
    wr32(b + G_OUT, 0x0);
    delay(8);
    check(ip, "INTRPT_FALL_STATUS", "set by falling edge", b + G_FALL_STATUS, 1, rd32(b + G_FALL_STATUS));
    wr32(b + G_STATUS, 0x1);              /* aggregate clear */
    check(ip, "INTRPT_FALL_STATUS", "cleared via INTRPT_STATUS W1C", b + G_FALL_STATUS, 0, rd32(b + G_FALL_STATUS));
    wr32(b + G_FALL_EN, 0);

    wr32(b + G_OUT, 0x1);
    delay(8);
    wr32(b + G_LVL_HIGH_EN, 0x1);
    delay(8);
    check(ip, "INTRPT_LVL_HIGH_STATUS", "set by high level", b + G_LVL_HIGH_STS, 1, rd32(b + G_LVL_HIGH_STS));
    wr32(b + G_LVL_HIGH_EN, 0);           /* remove the cause before clearing */
    wr32(b + G_LVL_HIGH_STS, 0x1);
    check(ip, "INTRPT_LVL_HIGH_STATUS", "W1C clears", b + G_LVL_HIGH_STS, 0, rd32(b + G_LVL_HIGH_STS));

    wr32(b + G_OUT, 0x0);
    delay(8);
    wr32(b + G_LVL_LOW_EN, 0x1);
    delay(8);
    check(ip, "INTRPT_LVL_LOW_STATUS", "set by low level", b + G_LVL_LOW_STS, 1, rd32(b + G_LVL_LOW_STS));
    wr32(b + G_LVL_LOW_EN, 0);
    wr32(b + G_LVL_LOW_STS, 0x1);
    check(ip, "INTRPT_LVL_LOW_STATUS", "W1C clears", b + G_LVL_LOW_STS, 0, rd32(b + G_LVL_LOW_STS));

    wr32(b + G_EN, 0);
    wr32(b + G_STATUS, ALL);
    check(ip, "INTRPT_STATUS", "all clear at end", b + G_STATUS, 0, rd32(b + G_STATUS));
}

static void spi_special(void)
{
    const char *ip = "SPI";
    uint32_t    b  = SPI_BASE;
    uint32_t    st = 0, n = 0;

    section("PHASE 5: SPI TX FIFO fill (10 words) and software reset");
    for (uint32_t k = 1; k <= 10; k++) {
        uint32_t w = k | (k << 8) | (k << 16) | (k << 24);
        wr32(b + S_TXFIFO, w);
    }
    check(ip, "STATUS", "TX count = 10, controller idle", b + S_STATUS, 0x0A000001u, rd32(b + S_STATUS));
    check(ip, "TXFIFO", "reads 0 (write-only)", b + S_TXFIFO, 0, rd32(b + S_TXFIFO));
    wr32(b + S_STATUS, 0x10);             /* swrst: clears both FIFOs */
    check(ip, "STATUS", "FIFOs empty after swrst", b + S_STATUS, 0x00000001u, rd32(b + S_STATUS));

    section("PHASE 5: SPI 64-bit read on CS1 (TB slave model) -> RXFIFO");
    wr32(b + S_CLKDIV, 1);
    wr32(b + S_SPICMD, 0);
    wr32(b + S_SPIADR, 0);
    wr32(b + S_SPIDUM, 0);
    wr32(b + S_SPILEN, 64u << 16);        /* data only, 64 bits */
    wr32(b + S_STATUS, (0x2u << 8) | 0x1u); /* CS1, standard read */
    do {
        st = rd32(b + S_STATUS);
    } while (!((st & 0x1u) && (((st >> 16) & 0x1Fu) == 2u)) && ++n < 4000);
    check(ip, "STATUS", "RX count = 2, controller idle", b + S_STATUS, 0x00020001u, st);
    if (((st >> 16) & 0x1Fu) == 2u) {     /* firmware rule: never read an empty RXFIFO */
        check(ip, "RXFIFO", "word 0 from CS1 slave", b + S_RXFIFO, 0xC3A55A3Cu, rd32(b + S_RXFIFO));
        check(ip, "RXFIFO", "word 1 from CS1 slave", b + S_RXFIFO, 0x0F1E2D4Bu, rd32(b + S_RXFIFO));
    }
    check(ip, "STATUS", "RX empty after reads", b + S_STATUS, 0x00000001u, rd32(b + S_STATUS));
    wr32(b + S_STATUS, 0x10);             /* swrst, CS select back to none */
    wr32(b + S_CLKDIV, 0);
    wr32(b + S_SPILEN, 0);
}

/* ------------------------------------------------------------------------ */
/*  Phase 6: holes and aliases (OKAY responses)                             */
/* ------------------------------------------------------------------------ */
static void hole(const char *ip, const char *name, uint32_t a)
{
    check(ip, name, "unmapped offset reads 0", a, 0, rd32(a));
    wr32(a, ALL);
    check(ip, name, "unmapped offset: write ignored", a, 0, rd32(a));
}

static void phase6_holes_aliases(void)
{
    section("PHASE 6: unmapped offsets (OKAY, read 0) and address aliasing");

    /* I2C decodes PADDR[5:2]: registers repeat every 0x40 */
    hole("I2C", "offset 0x18", I2C_BASE + 0x18);
    hole("I2C", "offset 0x3C", I2C_BASE + 0x3C);
    check("I2C", "PRE", "unchanged by hole writes", I2C_BASE + I2C_PRE, 0, rd32(I2C_BASE + I2C_PRE));
    wr32(I2C_BASE + I2C_PRE, 0x1234);
    check("I2C", "PRE", "alias at +0x040",  I2C_BASE + 0x040, 0x1234, rd32(I2C_BASE + 0x040));
    check("I2C", "PRE", "alias at +0xFC0",  I2C_BASE + 0xFC0, 0x1234, rd32(I2C_BASE + 0xFC0));
    wr32(I2C_BASE + 0x7C0, 0xBEEF);
    check("I2C", "PRE", "written through alias +0x7C0", I2C_BASE + I2C_PRE, 0xBEEF, rd32(I2C_BASE + I2C_PRE));
    wr32(I2C_BASE + I2C_PRE, 0);

    /* Timers decode PADDR[4] (channel) and PADDR[3:2]: repeat every 0x20 */
    for (uint32_t t = 0; t < 2; t++) {
        const char *ip = t ? "TIMER1" : "TIMER0";
        uint32_t    b  = t ? TIMER1_BASE : TIMER0_BASE;
        hole(ip, "offset 0x0C", b + 0x0C);
        hole(ip, "offset 0x1C", b + 0x1C);
        wr32(b + T_CMP, 0xABCD);
        wr32(b + 0x10 + T_CMP, 0x5555);
        check(ip, "CH0 CMP", "alias at +0x028", b + 0x028, 0xABCD, rd32(b + 0x028));
        check(ip, "CH0 CMP", "alias at +0xFE8", b + 0xFE8, 0xABCD, rd32(b + 0xFE8));
        check(ip, "CH1 CMP", "alias at +0x038", b + 0x038, 0x5555, rd32(b + 0x038));
        check(ip, "CH1 CMP", "alias at +0xFF8", b + 0xFF8, 0x5555, rd32(b + 0xFF8));
        wr32(b + T_CMP, 0);
        wr32(b + 0x10 + T_CMP, 0);
    }

    /* UART decodes PADDR[4:2]: repeat every 0x20 (all 8 slots are decoded) */
    wr32(UART_BASE + U_IER, 0x05);
    check("UART", "IER", "alias at +0x024", UART_BASE + 0x024, 0x05, rd32(UART_BASE + 0x024));
    check("UART", "IER", "alias at +0xFE4", UART_BASE + 0xFE4, 0x05, rd32(UART_BASE + 0xFE4));
    wr32(UART_BASE + U_IER, 0x00);
    (void)rd32(UART_BASE + U_IIR);

    /* SPI decodes PADDR[5:2]: repeat every 0x40. Aliases of RXFIFO are NOT read. */
    hole("SPI", "offset 0x1C", SPI_BASE + 0x1C);
    hole("SPI", "offset 0x2C", SPI_BASE + 0x2C);
    hole("SPI", "offset 0x3C", SPI_BASE + 0x3C);
    wr32(SPI_BASE + S_CLKDIV, 0x5A);
    check("SPI", "CLKDIV", "alias at +0x044", SPI_BASE + 0x044, 0x5A, rd32(SPI_BASE + 0x044));
    check("SPI", "CLKDIV", "alias at +0xFC4", SPI_BASE + 0xFC4, 0x5A, rd32(SPI_BASE + 0xFC4));
    wr32(SPI_BASE + S_CLKDIV, 0);
    check("SPI", "STATUS", "unchanged by hole writes", SPI_BASE + S_STATUS, 0x00000001u, rd32(SPI_BASE + S_STATUS));
}

/* ------------------------------------------------------------------------ */
/*  Phase 7: accesses that must fault                                       */
/* ------------------------------------------------------------------------ */
enum { ACC_LOAD, ACC_STORE32, ACC_STORE16, ACC_STORE8 };

static void expect_fault(const char *ip, const char *name, uint32_t a,
                         uint32_t acc, uint32_t resp)
{
    uint32_t cause = (acc == ACC_LOAD) ? 5u : 7u;

    g_trap.count = 0;
    g_trap.cause = 0;
    g_trap.tval  = 0;

    switch (acc) {
    case ACC_LOAD:    (void)rd32(a);             break;
    case ACC_STORE32: wr32(a, 0xFFFFFFFFu);      break;
    case ACC_STORE16: neg_store16(a, 0xFFFFu);   break;
    default:          neg_store8(a, 0xFFu);      break;
    }
    n_exp_traps++;

    check(ip, name, "one trap taken",               a, 1,     g_trap.count);
    check(ip, name, "mcause (5 load / 7 store)",    a, cause, g_trap.cause);
    check(ip, name, "mtval = faulting address",     a, a,     g_trap.tval);
    mbox_post(CMD_BUSRESP, ip, name, "bus response", a, resp, 0);
}

static void phase7_faults(void)
{
    section("PHASE 7: accesses that must fault (bus error -> access fault)");

    /* UART: writes to read-only LSR/MSR, and any non-DLL/DLM read with DLAB=1 */
    expect_fault("UART", "LSR write (read-only)", UART_BASE + U_LSR, ACC_STORE32, RESP_SLVERR);
    check("UART", "LSR", "unchanged after faulting write", UART_BASE + U_LSR, 0x60, rd32(UART_BASE + U_LSR));
    expect_fault("UART", "MSR write (read-only)", UART_BASE + U_MSR, ACC_STORE32, RESP_SLVERR);
    check("UART", "MSR", "unchanged after faulting write", UART_BASE + U_MSR, 0x00, rd32(UART_BASE + U_MSR));
    wr32(UART_BASE + U_LCR, 0x80);
    expect_fault("UART", "LCR read with DLAB=1", UART_BASE + U_LCR, ACC_LOAD, RESP_SLVERR);
    wr32(UART_BASE + U_LCR, 0x00);
    check("UART", "LCR", "DLAB cleared again", UART_BASE + U_LCR, 0x00, rd32(UART_BASE + U_LCR));

    /* GPIO: unmapped offsets inside the 2 KB window, and sub-word stores */
    expect_fault("GPIO", "unmapped 0x010 load",  GPIO_BASE + 0x010, ACC_LOAD,    RESP_SLVERR);
    expect_fault("GPIO", "unmapped 0x010 store", GPIO_BASE + 0x010, ACC_STORE32, RESP_SLVERR);
    expect_fault("GPIO", "unmapped 0x7FC load",  GPIO_BASE + 0x7FC, ACC_LOAD,    RESP_SLVERR);
    expect_fault("GPIO", "unmapped 0x7FC store", GPIO_BASE + 0x7FC, ACC_STORE32, RESP_SLVERR);
    expect_fault("GPIO", "GPIO_OUT byte store",      GPIO_BASE + G_OUT,     ACC_STORE8,  RESP_SLVERR);
    expect_fault("GPIO", "GPIO_OUT half-word store", GPIO_BASE + G_OUT + 2, ACC_STORE16, RESP_SLVERR);
    check("GPIO", "GPIO_OUT", "unchanged by sub-word stores", GPIO_BASE + G_OUT, 0, rd32(GPIO_BASE + G_OUT));

    /* Decode misses: no APB slave -> DECERR from axi_lite_to_apb */
    expect_fault("MMIO", "GPIO upper half 0x4000_3800 load",  0x40003800u, ACC_LOAD,    RESP_DECERR);
    expect_fault("MMIO", "GPIO upper half 0x4000_3800 store", 0x40003800u, ACC_STORE32, RESP_DECERR);
    expect_fault("MMIO", "after last slave 0x4000_6000 load",  0x40006000u, ACC_LOAD,    RESP_DECERR);
    expect_fault("MMIO", "after last slave 0x4000_6000 store", 0x40006000u, ACC_STORE32, RESP_DECERR);
    expect_fault("MMIO", "window end 0x4FFF_FFFC load",  0x4FFFFFFCu, ACC_LOAD,    RESP_DECERR);
    expect_fault("MMIO", "window end 0x4FFF_FFFC store", 0x4FFFFFFCu, ACC_STORE32, RESP_DECERR);
}

/* ------------------------------------------------------------------------ */
int main(void)
{
    section("RISCFORGE register access test: firmware started");

    phase1_reset_values();
    phase2_ro_writes();
    phase3_rw_patterns();
    phase4_uniqueness();

    i2c_special();
    timer_special("TIMER0", TIMER0_BASE);
    timer_special("TIMER1", TIMER1_BASE);
    uart_special();
    gpio_special();
    spi_special();

    phase6_holes_aliases();
    phase7_faults();

    section("PHASE 8: summary");
    check("CORE", "trap handler", "traps taken == traps expected", 0, n_exp_traps, g_trap.total);

    mbox_post(CMD_DONE, "", "", "", n_pass, n_fail, g_trap.total);
    return 0;
}
