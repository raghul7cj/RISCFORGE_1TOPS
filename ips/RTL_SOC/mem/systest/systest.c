/* =============================================================================
 * RISCFORGE 1TOPS - system test (firmware)
 * =============================================================================
 * Bare-metal C tests for signoff item 6.12 ("memory march and walking-ones,
 * timer/SW/external interrupts, UART/SPI/GPIO loopbacks"), run on the RV32
 * core after a real SPI-flash cold boot. Results go to the same mailbox as
 * regtest (DSRAM 0x0002_0000), watched by soc_systest_tb.sv.
 *
 * Together with regtest, this is the C test suite for 6.12. Split:
 *
 *   Covered by systest (this file)
 *     A  DSRAM memory test over every word the program does not use:
 *        walking ones / walking zeros (data bus), power-of-two offsets
 *        (address bus), March C- (cells, coupling), and a check that the
 *        program's own data was not touched
 *     B  interrupts taken by the core, with mcause and the resume address:
 *        software (MSIP, mip[3]), timer (MTIP, Timer 0 ch0 compare), fast
 *        interrupts Timer 1 ch0 compare (24), GPIO rising edge (16) and
 *        UART receive (19); masking by mie and by mstatus.MIE; and
 *        MEIP (11) reads 0 (tied off: no PLIC in this SoC, not testable)
 *     C  SPI write: a 32-bit word sent on CS1, MOSI bits checked by the TB
 *
 *   Signoff item 4.12 (reset and interrupt entry), with soc_systest_tb.sv:
 *     - B8 clean interrupt boundary: a timer interrupt inside a block of 512
 *       "addi a0, a0, 1"; the sum must be exactly 512 and mepc inside the block
 *     - B9 mtvec is direct mode only and holds the handler address
 *     - TB: first instruction after every reset is at RESET_PC (0x0000_0000),
 *       for the cold boot and for a warm reset (the firmware runs twice);
 *       for every interrupt the jump target = mtvec, mepc = the interrupted
 *       instruction, and that instruction is the first to retire after mret
 *
 *   Already covered by regtest (mem/regtest/regtest.c), not repeated here
 *     - register reset values / RW patterns / aliases of every peripheral
 *     - UART TX and RX on the pins (8N1, polled) and MCR loopback
 *     - GPIO output -> input pad loopback, SET/CLEAR/TOGGLE, W1C status
 *     - SPI read on CS1 (RX FIFO), SPI FIFO fill / soft reset
 *     - timer counting, compare-match period, CMP side effects
 *     - access faults: bus errors in the MMIO window and addresses outside
 *       DSRAM / MMIO (load and store access faults, mtval)
 *
 * Testbench dependencies (soc_systest_tb.sv)
 *   - GPIO pads looped back: gpio_in_i = gpio_out_o
 *   - UART RX pin driven by the TB on CMD_UART_RXSEND (8N1, LSB first)
 *   - SPI CS1: TB captures MOSI on SCK rising edges (mode 0, MSB first)
 *
 * Firmware rules followed (ips/RTL_SOC/FIRMWARE_RULES.md): 32-bit MMIO only,
 * SPI CLKDIV >= 2, UART divisor >= 2, built for rv32i_zicsr.
 * ========================================================================== */

#include <stdint.h>

/* ------------------------------------------------------------------------ */
/*  Memory map                                                              */
/* ------------------------------------------------------------------------ */
#define TIMER0_BASE   0x40001000u
#define UART_BASE     0x40002000u
#define GPIO_BASE     0x40003000u
#define SPI_BASE      0x40004000u
#define TIMER1_BASE   0x40005000u

#define T_VAL     0x00u
#define T_CTRL    0x04u
#define T_CMP     0x08u

#define U_RBR     0x00u
#define U_DLL     0x00u   /* DLAB = 1 */
#define U_IER     0x04u
#define U_DLM     0x04u   /* DLAB = 1 */
#define U_IIR     0x08u
#define U_FCR     0x08u
#define U_LCR     0x0Cu
#define U_MCR     0x10u
#define U_LSR     0x14u

#define G_EN          0x080u
#define G_OUT         0x180u
#define G_RISE_EN     0x380u
#define G_STATUS      0x580u
#define G_RISE_STATUS 0x600u

#define S_STATUS  0x00u
#define S_CLKDIV  0x04u
#define S_SPICMD  0x08u
#define S_SPIADR  0x0Cu
#define S_SPILEN  0x10u
#define S_SPIDUM  0x14u
#define S_TXFIFO  0x18u

#define ALL       0xFFFFFFFFu

/* UART: bit = 16 * divisor clocks (obi_uart_baudgen) */
#define UART_DIV      4u
#define UART_BIT_CYC  (16u * UART_DIV)

/* SPI write test */
#define SPI_TX_WORD   0xA5C30F96u

/* ------------------------------------------------------------------------ */
/*  Mailbox (same protocol as regtest)                                      */
/* ------------------------------------------------------------------------ */
#define MBOX_ADDR  0x00020000u
#define MB(i)      (*(volatile uint32_t *)(MBOX_ADDR + ((uint32_t)(i) << 2)))

enum { MB_CMD = 0, MB_IP, MB_NAME, MB_SUB, MB_ADDR, MB_EXP, MB_GOT };

enum {
    CMD_PASS        = 1,
    CMD_FAIL        = 2,
    CMD_SECTION     = 3,
    CMD_UART_RXSEND = 7,    /* TB: send byte EXP on the RX pin, GOT = clocks per bit */
    CMD_SPI_TXCHK   = 8,    /* TB: last CS1 frame on MOSI must be EXP, GOT = bits    */
    CMD_DONE        = 0xD0  /* ADDR = passes, EXP = fails, GOT = interrupts taken    */
};

static uint32_t n_pass, n_fail;

static inline uint32_t rd32(uint32_t a)             { return *(volatile uint32_t *)a; }
static inline void     wr32(uint32_t a, uint32_t v) { *(volatile uint32_t *)a = v; }

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

static void delay(uint32_t n)
{
    while (n--)
        __asm__ volatile ("nop");
}

/* ------------------------------------------------------------------------ */
/*  CSR access                                                              */
/* ------------------------------------------------------------------------ */
#define CSR_READ(csr)       ({ uint32_t v_; __asm__ volatile ("csrr %0, " #csr : "=r"(v_)); v_; })
#define CSR_SET(csr, v)     __asm__ volatile ("csrs " #csr ", %0" :: "r"(v) : "memory")
#define CSR_CLEAR(csr, v)   __asm__ volatile ("csrc " #csr ", %0" :: "r"(v) : "memory")

#define MSTATUS_MIE   0x8u
#define IRQ_BIT       0x80000000u

/* ------------------------------------------------------------------------ */
/*  Trap handler (called from trap_entry in startup.S)                      */
/* ------------------------------------------------------------------------ */
typedef struct {
    uint32_t count;      /* interrupts since the firmware last cleared it */
    uint32_t cause;      /* last interrupt mcause                         */
    uint32_t epc;        /* last interrupt mepc                           */
    uint32_t total;      /* interrupts since reset (never cleared)        */
    uint32_t exc;        /* exceptions (none expected in systest)         */
    uint32_t exc_cause;  /* last exception mcause                         */
} irq_rec_t;

volatile irq_rec_t g_irq;

__attribute__((used, noinline))
uint32_t trap_c(uint32_t cause, uint32_t epc, uint32_t tval)
{
    (void)tval;
    if (cause & IRQ_BIT) {
        uint32_t id = cause & 0x1Fu;
        g_irq.count++;
        g_irq.total++;
        g_irq.cause = cause;
        g_irq.epc   = epc;
        CSR_CLEAR(mie, 1u << id);   /* not taken again until the test re-enables it */
        return epc;
    }
    g_irq.exc++;
    g_irq.exc_cause = cause;
    return epc + 4;
}

static void irq_clear(void)
{
    g_irq.count = 0;
    g_irq.cause = 0;
    g_irq.epc   = 0;
}

static uint32_t irq_wait(uint32_t n_max)
{
    for (uint32_t n = 0; n < n_max && g_irq.count == 0; n++)
        __asm__ volatile ("nop");
    return g_irq.count;
}

/* Straight-line block for the clean-boundary test (B8). Labels are global so
 * the test can check that mepc points inside the block. */
extern char systest_blk_start[], systest_blk_end[];
extern void trap_entry(void);

__attribute__((noinline)) static uint32_t addi_block(void)
{
    uint32_t a = 0;
    __asm__ volatile (
        ".globl systest_blk_start\n"
        "systest_blk_start:\n"
        ".rept 512\n"
        "addi %0, %0, 1\n"
        ".endr\n"
        ".globl systest_blk_end\n"
        "systest_blk_end:\n"
        : "+r"(a));
    return a;
}

/* Common checks after an interrupt that must have been taken exactly once */
static void irq_expect(const char *name, uint32_t cause)
{
    uint32_t epc = g_irq.epc;
    check("IRQ", name, "taken once",                  0, 1,     g_irq.count);
    check("IRQ", name, "mcause",                      0, cause, g_irq.cause);
    check("IRQ", name, "mepc inside ISRAM (1 = yes)", epc, 1,
          (epc >= 0x00010000u && epc < 0x00018000u) ? 1u : 0u);
}

/* ------------------------------------------------------------------------ */
/*  A: DSRAM memory test                                                    */
/* ------------------------------------------------------------------------ */
extern uint32_t _memtest_start[], _memtest_end[];
extern uint32_t _img_start[], _img_end[];

static uint32_t img_checksum(void)
{
    uint32_t s = 0;
    for (volatile uint32_t *p = _img_start; p < _img_end; p++)
        s = (s << 1 | s >> 31) ^ *p;
    return s;
}

static void mem_tests(void)
{
    volatile uint32_t *m = _memtest_start;
    uint32_t n = (uint32_t)(_memtest_end - _memtest_start);
    uint32_t errs, first_addr, first_got;
    uint32_t sum0 = img_checksum();

    section("A: DSRAM memory test (region below the stack, above program data)");
    check("MEM", "region", "at least 4096 words free (1 = yes)", (uint32_t)(uintptr_t)m,
          1, (n >= 4096u) ? 1u : 0u);

    /* Data bus: walking one and walking zero on one word */
    errs = 0;
    for (uint32_t i = 0; i < 32; i++) {
        m[0] = 1u << i;
        if (m[0] != (1u << i)) errs++;
        m[0] = ~(1u << i);
        if (m[0] != ~(1u << i)) errs++;
    }
    check("MEM", "data bus", "walking 1s and 0s (errors)", (uint32_t)(uintptr_t)m, 0, errs);

    /* Address bus: one word at each power-of-two offset, unique writes */
    errs = 0;
    for (uint32_t o = 1; o < n; o <<= 1)
        m[o] = 0xAAAAAAAAu;
    m[0] = 0xAAAAAAAAu;
    for (uint32_t t = 1; t < n; t <<= 1) {
        m[t] = 0x55555555u;
        if (m[0] != 0xAAAAAAAAu) errs++;
        for (uint32_t o = 1; o < n; o <<= 1)
            if (o != t && m[o] != 0xAAAAAAAAu) errs++;
        m[t] = 0xAAAAAAAAu;
    }
    check("MEM", "address bus", "power-of-two offsets (errors)", (uint32_t)(uintptr_t)m, 0, errs);

    /* March C-: up w0; up r0 w1; up r1 w0; down r0 w1; down r1 w0; up r0 */
    errs = 0; first_addr = 0; first_got = 0;
#define MARCH_CHK(i, exp) do { uint32_t g_ = m[i];                         \
        if (g_ != (exp)) { if (!errs) { first_addr = (uint32_t)(uintptr_t)&m[i]; \
                                         first_got = g_; } errs++; } } while (0)
    for (uint32_t i = 0; i < n; i++) m[i] = 0;
    for (uint32_t i = 0; i < n; i++) { MARCH_CHK(i, 0u);  m[i] = ALL; }
    for (uint32_t i = 0; i < n; i++) { MARCH_CHK(i, ALL); m[i] = 0;   }
    for (uint32_t i = n; i-- > 0; )  { MARCH_CHK(i, 0u);  m[i] = ALL; }
    for (uint32_t i = n; i-- > 0; )  { MARCH_CHK(i, ALL); m[i] = 0;   }
    for (uint32_t i = 0; i < n; i++) { MARCH_CHK(i, 0u); }
#undef MARCH_CHK
    check("MEM", "march C-", "errors over the whole region", n, 0, errs);
    if (errs)
        check("MEM", "march C-", "first failing word (addr = address)", first_addr, 0, first_got);

    check("MEM", "program data", "unchanged by the memory test (checksum)",
          (uint32_t)(uintptr_t)_img_start, sum0, img_checksum());
}

/* ------------------------------------------------------------------------ */
/*  B: interrupts                                                           */
/* ------------------------------------------------------------------------ */
static void irq_tests(void)
{
    uint32_t t0 = TIMER0_BASE, t1 = TIMER1_BASE, g = GPIO_BASE, u = UART_BASE;

    section("B: interrupts taken by the core");
    check("IRQ", "start", "mstatus.MIE = 0 after boot", 0, 0, CSR_READ(mstatus) & MSTATUS_MIE);

    /* Software interrupt: mip[3] is software-writable (csr_regfile.v msip_r) */
    section("B1: software interrupt (MSIP, mcause 3)");
    irq_clear();
    CSR_SET(mie, 1u << 3);
    CSR_SET(mstatus, MSTATUS_MIE);
    CSR_SET(mip, 1u << 3);
    irq_wait(1000);
    CSR_CLEAR(mstatus, MSTATUS_MIE);
    CSR_CLEAR(mip, 1u << 3);
    irq_expect("MSIP", IRQ_BIT | 3u);

    /* Masking: pending with mie bit off, then with MIE off, then released */
    section("B2: masking by mie and by mstatus.MIE");
    irq_clear();
    CSR_CLEAR(mie, 1u << 3);
    CSR_SET(mstatus, MSTATUS_MIE);
    CSR_SET(mip, 1u << 3);
    irq_wait(200);
    check("IRQ", "mask mie", "pending MSIP with mie.MSIE = 0 not taken", 0, 0, g_irq.count);
    CSR_CLEAR(mstatus, MSTATUS_MIE);
    CSR_SET(mie, 1u << 3);
    irq_wait(200);
    check("IRQ", "mask MIE", "pending MSIP with mstatus.MIE = 0 not taken", 0, 0, g_irq.count);
    CSR_SET(mstatus, MSTATUS_MIE);
    irq_wait(1000);
    CSR_CLEAR(mstatus, MSTATUS_MIE);
    CSR_CLEAR(mip, 1u << 3);
    irq_expect("MSIP after unmask", IRQ_BIT | 3u);

    /* Timer interrupt: Timer 0 ch0 compare drives MTIP */
    section("B3: timer interrupt (MTIP, Timer 0 ch0 compare, mcause 7)");
    irq_clear();
    wr32(t0 + T_CTRL, 0);
    wr32(t0 + T_CMP, 0x100);              /* also clears VAL */
    CSR_SET(mie, 1u << 7);
    CSR_SET(mstatus, MSTATUS_MIE);
    wr32(t0 + T_CTRL, 1);                 /* EN, prescaler bypass */
    irq_wait(20000);
    CSR_CLEAR(mstatus, MSTATUS_MIE);
    wr32(t0 + T_CTRL, 0);
    wr32(t0 + T_CMP, 0);
    irq_expect("MTIP", IRQ_BIT | 7u);

    /* Fast interrupt: Timer 1 ch0 compare -> fast_irq_i[8] -> mcause 24 */
    section("B4: fast interrupt, Timer 1 ch0 compare (mcause 24)");
    irq_clear();
    wr32(t1 + T_CTRL, 0);
    wr32(t1 + T_CMP, 0x100);
    CSR_SET(mie, 1u << 24);
    CSR_SET(mstatus, MSTATUS_MIE);
    wr32(t1 + T_CTRL, 1);
    irq_wait(20000);
    CSR_CLEAR(mstatus, MSTATUS_MIE);
    wr32(t1 + T_CTRL, 0);
    wr32(t1 + T_CMP, 0);
    irq_expect("Timer1 CH0 compare", IRQ_BIT | 24u);

    /* Fast interrupt: GPIO rising edge on pin 0 (pad loopback) -> mcause 16 */
    section("B5: fast interrupt, GPIO rising edge (mcause 16)");
    irq_clear();
    wr32(g + G_OUT, 0);
    wr32(g + G_EN, 0x1);
    delay(8);
    wr32(g + G_STATUS, ALL);
    wr32(g + G_RISE_EN, 0x1);
    CSR_SET(mie, 1u << 16);
    CSR_SET(mstatus, MSTATUS_MIE);
    wr32(g + G_OUT, 0x1);                 /* rising edge on pad 0 */
    irq_wait(2000);
    CSR_CLEAR(mstatus, MSTATUS_MIE);
    irq_expect("GPIO rise", IRQ_BIT | 16u);
    check("GPIO", "INTRPT_RISE_STATUS", "pin 0 flagged", g + G_RISE_STATUS, 1, rd32(g + G_RISE_STATUS));
    wr32(g + G_RISE_EN, 0);
    wr32(g + G_STATUS, ALL);
    wr32(g + G_OUT, 0);
    wr32(g + G_EN, 0);

    /* Fast interrupt: UART receive (byte driven on the RX pin) -> mcause 19 */
    section("B6: fast interrupt, UART receive (mcause 19)");
    irq_clear();
    wr32(u + U_LCR, 0x80);
    wr32(u + U_DLL, UART_DIV);
    wr32(u + U_DLM, 0);
    wr32(u + U_LCR, 0x03);                /* 8N1 */
    wr32(u + U_FCR, 0x07);                /* FIFO on, both reset */
    wr32(u + U_MCR, 0x00);
    wr32(u + U_IER, 0x01);                /* ERBFI: receive data interrupt only */
    CSR_SET(mie, 1u << 19);
    CSR_SET(mstatus, MSTATUS_MIE);
    mbox_post(CMD_UART_RXSEND, "UART", "RBR", "TB sends byte on RX pin", u + U_RBR, 0x96u, UART_BIT_CYC);
    irq_wait(20000);
    CSR_CLEAR(mstatus, MSTATUS_MIE);
    irq_expect("UART RX", IRQ_BIT | 19u);
    check("UART", "RBR", "byte that raised the interrupt", u + U_RBR, 0x96u, rd32(u + U_RBR));
    wr32(u + U_IER, 0x00);
    wr32(u + U_FCR, 0x06);
    wr32(u + U_LCR, 0x00);
    (void)rd32(u + U_IIR);

    /* External interrupt: MEIP is tied 0 in riscforge_soc_subsystem.sv (no
     * PLIC), so it cannot be raised; only check that it never reads pending. */
    section("B7: external interrupt (MEIP, mcause 11) - tied off, not testable");
    check("IRQ", "MEIP", "mip[11] reads 0 (tied off, no PLIC)", 0, 0, CSR_READ(mip) & (1u << 11));

    /* Clean interrupt boundary (4.12): a timer interrupt lands inside a block
     * of 512 identical "addi a0, a0, 1". If any instruction were skipped or
     * executed twice around the interrupt, the sum would not be 512. mepc must
     * point at an instruction inside the block (the one not yet executed). */
    section("B8: clean interrupt boundary (MTIP inside a 512-instruction block)");
    irq_clear();
    wr32(t0 + T_CTRL, 0);
    wr32(t0 + T_CMP, 0x80);               /* also clears VAL */
    CSR_SET(mie, 1u << 7);
    CSR_SET(mstatus, MSTATUS_MIE);
    wr32(t0 + T_CTRL, 1);
    {
        uint32_t sum = addi_block();
        uint32_t epc = g_irq.epc;
        uint32_t bs  = (uint32_t)(uintptr_t)systest_blk_start;
        uint32_t be  = (uint32_t)(uintptr_t)systest_blk_end;
        CSR_CLEAR(mstatus, MSTATUS_MIE);
        wr32(t0 + T_CTRL, 0);
        wr32(t0 + T_CMP, 0);
        irq_expect("MTIP in addi block", IRQ_BIT | 7u);
        check("IRQ", "clean boundary", "mepc inside the addi block (1 = yes)", epc, 1,
              (epc >= bs && epc < be && (epc & 3u) == 0) ? 1u : 0u);
        check("IRQ", "clean boundary", "each of the 512 addi executed once (sum)", bs, 512, sum);
    }

    /* mtvec MODE (4.12 "mtvec jump"): csr_regfile.v keeps mtvec[1:0] = 00, so
     * only direct mode exists and every trap jumps to the mtvec base. */
    section("B9: mtvec is direct mode only");
    {
        uint32_t mt = CSR_READ(mtvec), mt2;
        __asm__ volatile ("csrw mtvec, %0" :: "r"(mt | 1u));    /* try vectored */
        mt2 = CSR_READ(mtvec);
        __asm__ volatile ("csrw mtvec, %0" :: "r"(mt));
        check("IRQ", "mtvec", "MODE stays 00 after writing 01 (direct only)", 0, mt, mt2);
        check("IRQ", "mtvec", "base = trap_entry (handler address)", 0,
              (uint32_t)(uintptr_t)trap_entry, mt);
    }

    check("IRQ", "end", "no exception taken during the interrupt tests", 0, 0, g_irq.exc);
}

/* ------------------------------------------------------------------------ */
/*  C: SPI write on CS1                                                     */
/* ------------------------------------------------------------------------ */
static void spi_write_test(void)
{
    uint32_t b = SPI_BASE, st = 0, n = 0;

    section("C: SPI 32-bit write on CS1 (TB captures MOSI)");
    wr32(b + S_STATUS, 0x10);             /* soft reset: both FIFOs empty */
    wr32(b + S_CLKDIV, 2);                /* firmware rule: CLKDIV >= 2 */
    wr32(b + S_SPICMD, 0);
    wr32(b + S_SPIADR, 0);
    wr32(b + S_SPIDUM, 0);
    wr32(b + S_SPILEN, 32u << 16);        /* data only, 32 bits */
    wr32(b + S_TXFIFO, SPI_TX_WORD);      /* TX FIFO was empty: room for it */
    wr32(b + S_STATUS, (0x2u << 8) | 0x2u); /* CS1, standard write */
    delay(16);
    do {
        st = rd32(b + S_STATUS);
    } while (!((st & 0x1u) && (((st >> 24) & 0x1Fu) == 0u)) && ++n < 4000);
    check("SPI", "STATUS", "idle, TX FIFO empty after write", b + S_STATUS, 0x00000001u, st);
    mbox_post(CMD_SPI_TXCHK, "SPI", "TXFIFO", "word on MOSI (CS1)", b + S_TXFIFO, SPI_TX_WORD, 32);
    wr32(b + S_STATUS, 0x10);             /* soft reset, no chip select */
    wr32(b + S_CLKDIV, 0);
    wr32(b + S_SPILEN, 0);
}

/* ------------------------------------------------------------------------ */
int main(void)
{
    section("RISCFORGE system test: firmware started");

    mem_tests();
    irq_tests();
    spi_write_test();

    section("summary");
    check("CORE", "exceptions", "none taken in the whole run", 0, 0, g_irq.exc);
    mbox_post(CMD_DONE, "", "", "", n_pass, n_fail, g_irq.total);
    return 0;
}
