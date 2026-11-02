/* =============================================================================
 * RISCFORGE 1TOPS - I2C register access test (firmware)
 * =============================================================================
 * Exercises EVERY register of the APB I2C master (ips/apb_i2c-master/apb_i2c.sv)
 * on the real RV32 core after a real SPI-flash cold boot, so every access goes
 * through the full path:
 *     core LSU -> hybrid_mem_interface -> axi_lite_xbar -> axi_lite_to_apb -> IP
 *
 * Results are posted to the mailbox at DSRAM 0x0002_0000 (reserved by link.ld)
 * using the same protocol as ips/mem_files/regtest/regtest.c, so any testbench
 * that already understands regtest.c understands this program. A second,
 * self-contained summary block at 0x0002_0020 lets the run be graded from a
 * plain DSRAM dump when no testbench support is attached (see SUM_* below).
 *
 * -----------------------------------------------------------------------------
 * Register map (apb_i2c.sv, APB slot 0, 0x4000_0000 - 0x4000_0FFF)
 *
 *   off   name  kind  reset   reads back  notes
 *   0x00  PRE   RW    0x0000  [15:0]      clock prescale, 16 bit
 *   0x04  CTR   RW    0x00    [7:0]       bit7 EN, bit6 IEN, [5:0] plain storage
 *   0x08  RXR   RO    0x00    [7:0]       shift-register output, hardware driven
 *   0x0C  SR    RO    0x00    [7:0]       7 RXACK, 6 BUSY, 5 AL, 1 TIP, 0 IF
 *   0x10  TXR   RW    0x00    [7:0]       byte to transmit
 *   0x14  CR    CMD   0x00    [7:0]       see the CR rules below
 *   0x18                                  s_apb_addr 6..15: ten unmapped slots,
 *   ..0x3C                                read 0, writes ignored
 *
 * Decode: s_apb_addr = PADDR[5:2]. PADDR[11:6] is NOT decoded, so the 16-slot
 * block repeats 64 times across the 4 KB window (aliases at +0x40, +0x80, ...,
 * +0xFC0). PREADY is tied 1 and PSLVERR is tied 0, and apb_addr_map[0] in
 * riscforge_soc_subsystem.sv covers the full 4 KB, so no access in this test may
 * fault and none may stall. Both facts are checked, not assumed.
 *
 * CR rules taken from the RTL - they are why CR cannot be pattern-swept:
 *   - a CR write only lands while CTR.EN (bit 7) is 1; otherwise CR keeps its
 *     previous contents, and a write can neither set nor clear it
 *   - bits [2:1] are reserved and bit 0 (IACK) is a self-clearing pulse: any
 *     later APB cycle clears them, so they always read back as 0
 *   - bits [7:4] (STA/STO/RD/WR) are cleared by hardware on transfer done or on
 *     arbitration loss; bit 3 (ACK) is plain storage and holds
 *   - writing bits [7:4] starts real I2C traffic, so this test never sets them:
 *     it is a register test, not a protocol test
 *
 * -----------------------------------------------------------------------------
 * What is deliberately NOT covered here, and where it is covered instead
 *   The RXR data path and the hardware-driven SR bits (RXACK, BUSY, AL, TIP, IF)
 *   only change as a result of real I2C traffic, which needs a slave on the bus.
 *   That is protocol behaviour, not register behaviour, and it belongs to the
 *   standalone I2C testbenches (ips/apb_i2c-master/directed_tb.sv and
 *   i2c_thorough_tb.sv). This program verifies their reset state, that they are
 *   read-only, that they decode correctly across the whole window, and that
 *   nothing it does disturbs them.
 *
 * -----------------------------------------------------------------------------
 * Firmware rules followed (build.py enforces the first two)
 *   - 32-bit MMIO loads and stores only: no lb/lh/lbu/lhu/sb/sh anywhere. APB
 *     has no byte strobes and apb_i2c.sv ties PSLVERR low, so a sub-word store
 *     would silently write all 32 bits of PWDATA.
 *   - built for rv32i_zicsr: no M-extension instructions (rv32m_mul.v and
 *     rv32m_div.v are not signed off yet).
 *   - every MMIO address reaching a load or store is a compile-time constant or
 *     pure register arithmetic on a loop variable. No base/offset pair is
 *     fetched from a table, and no address passes through a function pointer or
 *     jump table. This is deliberate: REG-VERIF-v1.0 section 3 traced the 37
 *     failing registers of the all-peripheral register test to address
 *     corruption in the core on exactly that code shape (lw base / lw off / add
 *     / jalr, behind a load-use hazard feeding a branch). Keeping addresses out
 *     of memory means a FAIL reported here is an I2C defect, not that one.
 * ========================================================================== */

#include <stdint.h>

/* ------------------------------------------------------------------------ */
/*  I2C register addresses - absolute constants, never computed             */
/* ------------------------------------------------------------------------ */
#define I2C_BASE   0x40000000u
#define I2C_WIN    0x00001000u        /* apb_addr_map[0] window: 4 KB        */
#define I2C_STRIDE 0x00000040u        /* alias period: PADDR[5:2] decode     */

#define I2C_PRE    (I2C_BASE + 0x00u)
#define I2C_CTR    (I2C_BASE + 0x04u)
#define I2C_RXR    (I2C_BASE + 0x08u)
#define I2C_SR     (I2C_BASE + 0x0Cu)
#define I2C_TXR    (I2C_BASE + 0x10u)
#define I2C_CR     (I2C_BASE + 0x14u)

/* implemented-bit masks: what a read gives back after a 32-bit write */
#define M_PRE      0x0000FFFFu
#define M_BYTE     0x000000FFu
#define ALL        0xFFFFFFFFu

/* CTR bits */
#define CTR_EN     0x80u
#define CTR_IEN    0x40u

/* CR bits */
#define CR_ACK     0x08u
#define CR_IACK    0x01u
#define CR_RSVD    0x06u              /* [2:1], always read back as 0        */

/* ------------------------------------------------------------------------ */
/*  Mailbox protocol (DSRAM 0x0002_0000, reserved by link.ld)               */
/*  Identical to regtest.c: the testbench acts on the write to MB_CMD,      */
/*  which is always the last store of a post.                              */
/* ------------------------------------------------------------------------ */
#define MBOX_ADDR  0x00020000u
#define MB(i)      (*(volatile uint32_t *)(MBOX_ADDR + ((uint32_t)(i) << 2)))

enum { MB_CMD = 0, MB_IP, MB_NAME, MB_SUB, MB_ADDR, MB_EXP, MB_GOT };

enum {
    CMD_PASS    = 1,      /* check passed                                     */
    CMD_FAIL    = 2,      /* check failed: TB prints ip.name : sub, exp, got  */
    CMD_SECTION = 3,      /* progress banner                                  */
    CMD_BUSRESP = 4,      /* reserved (regtest.c); unused, nothing faults here */
    CMD_DONE    = 0xD0    /* ADDR = passes, EXP = fails, GOT = total traps    */
};

/* ------------------------------------------------------------------------ */
/*  Standalone summary block (DSRAM 0x0002_0020, inside .results)           */
/*  Grading without testbench support: dump 16 words at 0x0002_0000 and     */
/*  read words 8..15. PASS means DONE == 0xD09ED09E and FAIL == 0.          */
/* ------------------------------------------------------------------------ */
#define SUM(i)     (*(volatile uint32_t *)(MBOX_ADDR + 0x20u + ((uint32_t)(i) << 2)))

enum {
    SUM_MAGIC = 0,        /* 0x49324352 = "I2CR", written first thing        */
    SUM_PASS,             /* checks passed so far                            */
    SUM_FAIL,             /* checks failed so far                            */
    SUM_CHECKS,           /* checks made so far                              */
    SUM_TRAPS,            /* g_trap.total: must stay 0                       */
    SUM_FIRSTFAIL,        /* address of the first failing check, 0 if none   */
    SUM_PHASE,            /* phase number currently running                  */
    SUM_DONE              /* 0xD09ED09E once main() reached the end          */
};

#define SUM_MAGIC_VAL  0x49324352u
#define SUM_DONE_VAL   0xD09ED09Eu

/* ------------------------------------------------------------------------ */
/*  Trap record, written by trap_entry in startup.S.                        */
/*  Nothing in this test may fault; the record exists to prove that.        */
/* ------------------------------------------------------------------------ */
typedef struct {
    uint32_t count;
    uint32_t cause;
    uint32_t tval;
    uint32_t epc;
    uint32_t total;
} trap_rec_t;

volatile trap_rec_t g_trap;

static const char IP_NAME[] = "I2C";

static uint32_t n_pass, n_fail, first_fail;

/* ------------------------------------------------------------------------ */
/*  Low-level helpers - 32-bit MMIO only                                    */
/* ------------------------------------------------------------------------ */
static inline uint32_t rd32(uint32_t a)             { return *(volatile uint32_t *)a; }
static inline void     wr32(uint32_t a, uint32_t v) { *(volatile uint32_t *)a = v; }

#define P(s) ((uint32_t)(uintptr_t)(s))

static void mbox_post(uint32_t cmd, const char *name, const char *sub,
                      uint32_t addr, uint32_t exp, uint32_t got)
{
    MB(MB_IP)   = P(IP_NAME);
    MB(MB_NAME) = P(name);
    MB(MB_SUB)  = P(sub);
    MB(MB_ADDR) = addr;
    MB(MB_EXP)  = exp;
    MB(MB_GOT)  = got;
    MB(MB_CMD)  = cmd;
}

static void section(uint32_t phase, const char *title)
{
    SUM(SUM_PHASE) = phase;
    mbox_post(CMD_SECTION, title, "", phase, 0, 0);
}

static void pass(const char *name, const char *sub, uint32_t addr)
{
    n_pass++;
    SUM(SUM_PASS)   = n_pass;
    SUM(SUM_CHECKS) = n_pass + n_fail;
    mbox_post(CMD_PASS, name, sub, addr, 0, 0);
}

static void fail(const char *name, const char *sub, uint32_t addr,
                 uint32_t exp, uint32_t got)
{
    n_fail++;
    if (n_fail == 1u) {                /* not "first_fail == 0": a genuine   */
        first_fail = addr;             /* failure may legitimately carry     */
        SUM(SUM_FIRSTFAIL) = addr;     /* address 0 (the phase 8 checks)     */
    }
    SUM(SUM_FAIL)   = n_fail;
    SUM(SUM_CHECKS) = n_pass + n_fail;
    mbox_post(CMD_FAIL, name, sub, addr, exp, got);
}

static void check(const char *name, const char *sub, uint32_t addr,
                  uint32_t exp, uint32_t got)
{
    if (got == exp)
        pass(name, sub, addr);
    else
        fail(name, sub, addr, exp, got);
}

/* ------------------------------------------------------------------------ */
/*  PHASE 1: reset values, read before anything is written                  */
/* ------------------------------------------------------------------------ */
static void phase1_reset_values(void)
{
    section(1, "PHASE 1: reset values (read before any write)");

    check("PRE", "reset value", I2C_PRE, 0x0000u, rd32(I2C_PRE));
    check("CTR", "reset value", I2C_CTR, 0x00u,   rd32(I2C_CTR));
    check("RXR", "reset value", I2C_RXR, 0x00u,   rd32(I2C_RXR));
    check("SR",  "reset value", I2C_SR,  0x00u,   rd32(I2C_SR));
    check("TXR", "reset value", I2C_TXR, 0x00u,   rd32(I2C_TXR));
    check("CR",  "reset value", I2C_CR,  0x00u,   rd32(I2C_CR));

    /* SR spelled out field by field: this is the state every later phase
     * assumes - core disabled, bus released, no interrupt pending. */
    check("SR", "RXACK=0 BUSY=0 AL=0 at reset", I2C_SR, 0u, rd32(I2C_SR) & 0xE0u);
    check("SR", "TIP=0 IF=0 at reset",          I2C_SR, 0u, rd32(I2C_SR) & 0x03u);
    check("SR", "reserved [4:2] read 0",        I2C_SR, 0u, rd32(I2C_SR) & 0x1Cu);
}

/* ------------------------------------------------------------------------ */
/*  PHASE 2: read-only registers ignore writes and answer OKAY              */
/* ------------------------------------------------------------------------ */
static void ro_write_ignored(const char *name, uint32_t a, uint32_t val)
{
    wr32(a, val);
    check(name, "write ignored (read-only)", a, 0x00u, rd32(a));
}

static void phase2_readonly(void)
{
    section(2, "PHASE 2: read-only registers RXR and SR ignore writes");

    ro_write_ignored("RXR", I2C_RXR, ALL);
    ro_write_ignored("RXR", I2C_RXR, 0x000000A5u);
    ro_write_ignored("RXR", I2C_RXR, 0x0000005Au);
    ro_write_ignored("RXR", I2C_RXR, 0x00000000u);

    ro_write_ignored("SR",  I2C_SR,  ALL);
    ro_write_ignored("SR",  I2C_SR,  0x000000A5u);
    ro_write_ignored("SR",  I2C_SR,  0x0000005Au);
    ro_write_ignored("SR",  I2C_SR,  0x00000000u);

    /* a write to a read-only offset must not leak into a neighbour */
    check("PRE", "unchanged by RO writes", I2C_PRE, 0x0000u, rd32(I2C_PRE));
    check("CTR", "unchanged by RO writes", I2C_CTR, 0x00u,   rd32(I2C_CTR));
    check("TXR", "unchanged by RO writes", I2C_TXR, 0x00u,   rd32(I2C_TXR));
    check("CR",  "unchanged by RO writes", I2C_CR,  0x00u,   rd32(I2C_CR));
}

/* ------------------------------------------------------------------------ */
/*  PHASE 3: the ten unmapped slots 0x18..0x3C read 0 and ignore writes     */
/* ------------------------------------------------------------------------ */
static void phase3_holes(void)
{
    section(3, "PHASE 3: unmapped slots 0x18-0x3C read 0, writes ignored");

    for (uint32_t a = I2C_BASE + 0x18u; a <= I2C_BASE + 0x3Cu; a += 4u) {
        check("hole", "unmapped slot reads 0", a, 0u, rd32(a));
        wr32(a, ALL);
        check("hole", "unmapped slot: write ignored", a, 0u, rd32(a));
    }

    check("PRE", "unchanged by hole writes", I2C_PRE, 0x0000u, rd32(I2C_PRE));
    check("CTR", "unchanged by hole writes", I2C_CTR, 0x00u,   rd32(I2C_CTR));
    check("TXR", "unchanged by hole writes", I2C_TXR, 0x00u,   rd32(I2C_TXR));
    check("CR",  "unchanged by hole writes", I2C_CR,  0x00u,   rd32(I2C_CR));
    check("SR",  "bus still idle",           I2C_SR,  0x00u,   rd32(I2C_SR));
}

/* ------------------------------------------------------------------------ */
/*  PHASE 4: read/write pattern sweep, 36 patterns per register             */
/*                                                                          */
/*  0, all-ones, 0xAAAA_AAAA, 0x5555_5555 and a walking one through all 32  */
/*  bit positions, each read back through the implemented-bit mask. The     */
/*  patterns are produced arithmetically, not read from a table, so no      */
/*  pattern load can be mistaken for an address load.                      */
/* ------------------------------------------------------------------------ */
static uint32_t pat_of(uint32_t i)
{
    if (i < 32u)  return 1u << i;
    if (i == 32u) return 0x00000000u;
    if (i == 33u) return 0xFFFFFFFFu;
    if (i == 34u) return 0xAAAAAAAAu;
    return 0x55555555u;
}

static void rw_sweep(const char *name, uint32_t a, uint32_t rmask, uint32_t restore)
{
    uint32_t errs = 0u;

    for (uint32_t i = 0u; i < 36u; i++) {
        uint32_t p   = pat_of(i);
        uint32_t exp = p & rmask;
        uint32_t got;

        wr32(a, p);
        got = rd32(a);
        if (got != exp) {
            if (errs < 4u)
                fail(name, "RW pattern readback", a, exp, got);
            errs++;
        }
    }
    wr32(a, restore);

    if (errs == 0u)
        pass(name, "RW patterns (36 of 36)", a);
    else if (errs > 4u)
        fail(name, "further RW mismatches (got = total)", a, 4u, errs);

    check(name, "restored to reset value", a, restore & rmask, rd32(a));
}

static void phase4_rw_patterns(void)
{
    section(4, "PHASE 4: RW registers, 36 patterns each");

    /* PRE: the upper 16 bits must not store. */
    rw_sweep("PRE", I2C_PRE, M_PRE, 0x0000u);

    /* CTR: bit 7 is EN and bit 6 is IEN. With CR = 0 the core has no command
     * to run, so enabling it starts nothing - the two checks after the sweep
     * prove the bus stayed idle and no command appeared. Upper 24 bits must
     * not store. */
    rw_sweep("CTR", I2C_CTR, M_BYTE, 0x00u);
    check("SR", "bus idle after CTR sweep",       I2C_SR, 0x00u, rd32(I2C_SR));
    check("CR", "no command raised by CTR sweep", I2C_CR, 0x00u, rd32(I2C_CR));

    rw_sweep("TXR", I2C_TXR, M_BYTE, 0x00u);
    check("SR", "bus idle after TXR sweep", I2C_SR, 0x00u, rd32(I2C_SR));

    /* the read-only pair must be untouched by all of the above */
    check("RXR", "unchanged by RW sweeps", I2C_RXR, 0x00u, rd32(I2C_RXR));
}

/* ------------------------------------------------------------------------ */
/*  PHASE 5: CR, the command register                                       */
/*                                                                          */
/*  CR cannot be pattern-swept: bits [7:4] would start I2C traffic. Every   */
/*  rule the RTL implements is checked individually instead, using only the */
/*  ACK (bit 3), IACK (bit 0) and reserved (bits [2:1]) fields, so the I2C  */
/*  bus stays idle from start to finish.                                    */
/* ------------------------------------------------------------------------ */
static void phase5_command_register(void)
{
    section(5, "PHASE 5: CR command register semantics");

    /* 5a  CTR.EN = 0: a CR write does not land */
    wr32(I2C_CTR, 0x00u);
    wr32(I2C_CR, ALL);
    check("CR", "write ignored while CTR.EN=0", I2C_CR, 0x00u, rd32(I2C_CR));
    wr32(I2C_CR, CR_ACK);
    check("CR", "ACK write ignored while CTR.EN=0", I2C_CR, 0x00u, rd32(I2C_CR));
    check("SR", "bus idle (no command accepted)", I2C_SR, 0x00u, rd32(I2C_SR));

    /* 5b  CTR.EN = 1: ACK is plain storage and holds */
    wr32(I2C_CTR, CTR_EN);
    check("CTR", "EN set", I2C_CTR, CTR_EN, rd32(I2C_CTR));
    wr32(I2C_CR, CR_ACK);
    check("CR", "ACK bit holds with CTR.EN=1",    I2C_CR, CR_ACK, rd32(I2C_CR));
    check("CR", "ACK still set on a second read", I2C_CR, CR_ACK, rd32(I2C_CR));

    /* 5c  reserved [2:1] and IACK [0] read back as 0 even when written 1 */
    wr32(I2C_CR, CR_ACK | CR_RSVD | CR_IACK);
    check("CR", "reserved [2:1] and IACK read 0, ACK kept", I2C_CR, CR_ACK, rd32(I2C_CR));

    /* 5d  IACK on its own is a self-clearing pulse. It also clears ACK,
     *     because a CR write with EN = 1 replaces the whole register. */
    wr32(I2C_CR, CR_IACK);
    check("CR", "IACK self-clears", I2C_CR, 0x00u, rd32(I2C_CR));
    check("SR", "IF stays 0 (no event to acknowledge)", I2C_SR, 0x00u, rd32(I2C_SR));

    /* 5e  CR contents are frozen, not cleared, when EN goes away. The CTR
     *     write itself clears [2:1] and [0]; ACK must survive it. */
    wr32(I2C_CR, CR_ACK);
    wr32(I2C_CTR, 0x00u);
    check("CR", "ACK survives CTR.EN being cleared", I2C_CR, CR_ACK, rd32(I2C_CR));
    wr32(I2C_CR, 0x00u);
    check("CR", "cannot be cleared while CTR.EN=0", I2C_CR, CR_ACK, rd32(I2C_CR));
    wr32(I2C_CR, ALL);
    check("CR", "cannot be set while CTR.EN=0",     I2C_CR, CR_ACK, rd32(I2C_CR));

    /* 5f  re-enable and clean up */
    wr32(I2C_CTR, CTR_EN);
    wr32(I2C_CR, 0x00u);
    check("CR", "cleared again with CTR.EN=1", I2C_CR, 0x00u, rd32(I2C_CR));

    /* 5g  CTR.IEN does not raise an interrupt while SR.IF = 0. The interrupt
     *     pin itself is a testbench observable; the register side is checked
     *     here - IEN is storage, IF stays 0. */
    wr32(I2C_CTR, CTR_EN | CTR_IEN);
    check("CTR", "IEN is storage",      I2C_CTR, CTR_EN | CTR_IEN, rd32(I2C_CTR));
    check("SR",  "IF stays 0 with IEN=1", I2C_SR, 0x00u, rd32(I2C_SR));

    wr32(I2C_CTR, 0x00u);
    check("CTR", "restored to reset value",     I2C_CTR, 0x00u, rd32(I2C_CTR));
    check("SR",  "bus idle after all CR tests", I2C_SR,  0x00u, rd32(I2C_SR));
    check("RXR", "unchanged by all CR tests",   I2C_RXR, 0x00u, rd32(I2C_RXR));
}

/* ------------------------------------------------------------------------ */
/*  PHASE 6: uniqueness - no two offsets share one piece of storage         */
/* ------------------------------------------------------------------------ */
static void unique_round(uint32_t pre, uint32_t ctr, uint32_t txr, uint32_t cr,
                         const char *sub)
{
    /* CR is loaded while EN is still set, then CTR is written last so that
     * its own value is the one that finally stands. */
    wr32(I2C_CTR, CTR_EN);
    wr32(I2C_CR,  cr);
    wr32(I2C_PRE, pre);
    wr32(I2C_TXR, txr);
    wr32(I2C_CTR, ctr);

    check("PRE", sub, I2C_PRE, pre & M_PRE,  rd32(I2C_PRE));
    check("CTR", sub, I2C_CTR, ctr & M_BYTE, rd32(I2C_CTR));
    check("TXR", sub, I2C_TXR, txr & M_BYTE, rd32(I2C_TXR));
    check("CR",  sub, I2C_CR,  cr  & M_BYTE, rd32(I2C_CR));
    check("RXR", sub, I2C_RXR, 0x00u,        rd32(I2C_RXR));
    check("SR",  sub, I2C_SR,  0x00u,        rd32(I2C_SR));
}

static void phase6_uniqueness(void)
{
    section(6, "PHASE 6: distinct value in every register, all read back");

    /* CR may only carry ACK (bit 3): every other bit either self-clears or
     * starts a transfer, so CR is 0x08 in one round and 0x00 in the other.
     * CTR keeps EN = 0 in both rounds so RXR and SR stay at 0. */
    unique_round(0x0000A53Cu, 0x0000003Cu, 0x0000005Au, CR_ACK, "unique value");
    unique_round(0x00005AC3u, 0x00000043u, 0x000000A5u, 0x00u,  "unique value (inverted)");

    /* back to reset */
    wr32(I2C_CTR, CTR_EN);
    wr32(I2C_CR,  0x00u);
    wr32(I2C_PRE, 0x0000u);
    wr32(I2C_TXR, 0x00u);
    wr32(I2C_CTR, 0x00u);
    check("CR",  "restored to reset value", I2C_CR,  0x00u,   rd32(I2C_CR));
    check("PRE", "restored to reset value", I2C_PRE, 0x0000u, rd32(I2C_PRE));
    check("TXR", "restored to reset value", I2C_TXR, 0x00u,   rd32(I2C_TXR));
    check("CTR", "restored to reset value", I2C_CTR, 0x00u,   rd32(I2C_CTR));
}

/* ------------------------------------------------------------------------ */
/*  PHASE 7: aliasing and full 4 KB window decode                          */
/*                                                                          */
/*  apb_i2c.sv decodes PADDR[5:2] only, so the 16-slot block repeats 64     */
/*  times over the 4 KB window. All 1024 word addresses in the window are   */
/*  read and must return their slot value, and a write through a high alias */
/*  must land in the real register.                                        */
/* ------------------------------------------------------------------------ */
static uint32_t win_expect(uint32_t slot, uint32_t pre, uint32_t ctr,
                           uint32_t txr, uint32_t cr)
{
    if (slot == 0u) return pre & M_PRE;    /* PRE                           */
    if (slot == 1u) return ctr & M_BYTE;   /* CTR                           */
    if (slot == 4u) return txr & M_BYTE;   /* TXR                           */
    if (slot == 5u) return cr  & M_BYTE;   /* CR                            */
    return 0u;                             /* RXR, SR and the ten holes     */
}

static void phase7_aliases(void)
{
    const uint32_t pre = 0x0000A53Cu;
    const uint32_t ctr = 0x0000003Cu;      /* EN = 0, so RXR and SR stay 0  */
    const uint32_t txr = 0x0000005Au;
    const uint32_t cr  = CR_ACK;

    section(7, "PHASE 7: aliasing and full 4 KB window decode");

    /* named spot checks first, so a failure names the register */
    wr32(I2C_PRE, 0x1234u);
    check("PRE", "alias at +0x040", I2C_BASE + 0x040u, 0x1234u, rd32(I2C_BASE + 0x040u));
    check("PRE", "alias at +0x7C0", I2C_BASE + 0x7C0u, 0x1234u, rd32(I2C_BASE + 0x7C0u));
    check("PRE", "alias at +0xFC0", I2C_BASE + 0xFC0u, 0x1234u, rd32(I2C_BASE + 0xFC0u));
    wr32(I2C_BASE + 0xFC0u, 0x0000BEEFu);
    check("PRE", "written through alias +0xFC0", I2C_PRE, 0xBEEFu, rd32(I2C_PRE));

    wr32(I2C_TXR, 0x00u);
    wr32(I2C_BASE + 0x810u, 0x0000003Cu);          /* TXR through an alias  */
    check("TXR", "written through alias +0x810",  I2C_TXR, 0x3Cu, rd32(I2C_TXR));
    check("TXR", "alias at +0xFD0 reads it back", I2C_BASE + 0xFD0u, 0x3Cu,
          rd32(I2C_BASE + 0xFD0u));

    /* an unmapped slot through an alias: 0x898 -> PADDR[5:2] = 6, i.e. the
     * alias of the hole at 0x18. It must still read 0 and still swallow a write. */
    wr32(I2C_BASE + 0x898u, ALL);
    check("hole", "hole alias +0x898 (slot 6) ignores writes", I2C_BASE + 0x898u, 0u,
          rd32(I2C_BASE + 0x898u));
    check("TXR", "unchanged by the hole alias write", I2C_TXR, 0x3Cu, rd32(I2C_TXR));

    /* full window: 16 slots x 64 aliases = every word address in the 4 KB */
    wr32(I2C_CTR, CTR_EN);
    wr32(I2C_CR,  cr);
    wr32(I2C_PRE, pre);
    wr32(I2C_TXR, txr);
    wr32(I2C_CTR, ctr);

    for (uint32_t slot = 0u; slot < 16u; slot++) {
        uint32_t exp   = win_expect(slot, pre, ctr, txr, cr);
        uint32_t errs  = 0u;
        uint32_t first = 0u;
        uint32_t got   = 0u;

        for (uint32_t a = I2C_BASE + (slot << 2); a < I2C_BASE + I2C_WIN;
             a += I2C_STRIDE) {
            uint32_t v = rd32(a);
            if (v != exp) {
                if (errs == 0u) {
                    first = a;
                    got   = v;
                }
                errs++;
            }
        }
        if (errs == 0u)
            pass("window", "all 64 aliases of this slot read the slot value",
                 I2C_BASE + (slot << 2));
        else
            fail("window", "alias mismatch (ADDR = first bad alias)", first, exp, got);
    }

    /* back to reset */
    wr32(I2C_CTR, CTR_EN);
    wr32(I2C_CR,  0x00u);
    wr32(I2C_PRE, 0x0000u);
    wr32(I2C_TXR, 0x00u);
    wr32(I2C_CTR, 0x00u);
}

/* ------------------------------------------------------------------------ */
/*  PHASE 8: nothing in the run may have faulted                            */
/* ------------------------------------------------------------------------ */
static void phase8_no_faults(void)
{
    section(8, "PHASE 8: no access faulted anywhere in the run");

    SUM(SUM_TRAPS) = g_trap.total;

    check("bus", "no trap taken (PSLVERR tied 0, 4 KB fully decoded)",
          0u, 0u, g_trap.total);
    check("bus", "no mcause recorded",           0u, 0u, g_trap.cause);
    check("bus", "no faulting address recorded", 0u, 0u, g_trap.tval);
}

/* ------------------------------------------------------------------------ */
/*  PHASE 9: final state is the reset state                                 */
/* ------------------------------------------------------------------------ */
static void phase9_final_state(void)
{
    section(9, "PHASE 9: final state equals reset state");

    check("PRE", "final value", I2C_PRE, 0x0000u, rd32(I2C_PRE));
    check("CTR", "final value", I2C_CTR, 0x00u,   rd32(I2C_CTR));
    check("RXR", "final value", I2C_RXR, 0x00u,   rd32(I2C_RXR));
    check("SR",  "final value", I2C_SR,  0x00u,   rd32(I2C_SR));
    check("TXR", "final value", I2C_TXR, 0x00u,   rd32(I2C_TXR));
    check("CR",  "final value", I2C_CR,  0x00u,   rd32(I2C_CR));
}

/* ------------------------------------------------------------------------ */
int main(void)
{
    SUM(SUM_MAGIC)     = SUM_MAGIC_VAL;
    SUM(SUM_PASS)      = 0u;
    SUM(SUM_FAIL)      = 0u;
    SUM(SUM_CHECKS)    = 0u;
    SUM(SUM_TRAPS)     = 0u;
    SUM(SUM_FIRSTFAIL) = 0u;
    SUM(SUM_DONE)      = 0u;

    section(0, "RISCFORGE I2C register test: firmware started");

    phase1_reset_values();
    phase2_readonly();
    phase3_holes();
    phase4_rw_patterns();
    phase5_command_register();
    phase6_uniqueness();
    phase7_aliases();
    phase8_no_faults();
    phase9_final_state();

    SUM(SUM_TRAPS) = g_trap.total;
    SUM(SUM_DONE)  = SUM_DONE_VAL;

    mbox_post(CMD_DONE, "", "", n_pass, n_fail, g_trap.total);
    return 0;
}
