/* =============================================================================
 * RISCFORGE 1TOPS - Pong demo (firmware)
 * =============================================================================
 * All game logic runs on the RV32 core. The display is the PC on the other end
 * of the UART, in one of two modes selected at run time by a control byte
 * (not printable keys, so a terminal user cannot switch to binary by accident):
 *
 *   0x01 terminal mode (default) - ANSI escape codes, any terminal (PuTTY,
 *        Tera Term, Windows Terminal) set to BAUD 8N1. Only cells that changed
 *        are redrawn each frame.
 *   0x02 binary mode - one 16-byte state packet per frame for pong_viewer.py:
 *          0xA5 0x5A | bx bx by by | p1 p2 | s1 s2 | state | last | rsvd x3 | sum
 *        bx/by: ball position, 4 fractional bits, little-endian
 *        p1/p2: paddle top row, s1/s2: LEFT/RIGHT scores, state: low nibble
 *        game state, bit 4 = right paddle on CPU, last: last point 0 none,
 *        1 LEFT, 2 RIGHT, sum: low byte of bytes [2..14]
 *
 * Keys: w/s LEFT paddle, i/k RIGHT paddle (the first i/k turns the right AI
 * off), a = RIGHT paddle back to AI, p = pause, r = restart, space = serve.
 * A side scores when the ball goes out past the OTHER side's paddle.
 *
 * Frame tick: TIMER0 channel 0 counts at CLK_HZ with CMP = CLK_HZ / FPS. The
 * compare match clears VAL (timer.sv), so a frame starts when VAL < last VAL.
 * Interrupts stay disabled (MIE = 0); the irq output is ignored.
 *
 * Firmware rules followed (see project notes):
 *   - 32-bit loads and stores only, everywhere (build.py checks the dump).
 *     String bytes are extracted from aligned word loads (str_at).
 *   - UART: RBR is only read when LSR.DR = 1 and LCR.DLAB = 0; nothing but
 *     DLL/DLM is accessed while DLAB = 1.
 *   - No M extension: no multiply/divide anywhere in the game logic.
 * ========================================================================== */

#include <stdint.h>

/* ------------------------------------------------------------------------ */
/*  Board configuration                                                     */
/* ------------------------------------------------------------------------ */
#define CLK_HZ     40000000u          /* Nexys 4 DDR top: 40 MHz SoC clock */
#define BAUD       115200u
#define FPS        30u

/* build.py passes both with -D (board values, or the fast simulation values
 * of build.py --sim). obi_uart_baudgen treats a divisor of 1 as invalid. */
#ifndef UART_DIV
#define UART_DIV   ((CLK_HZ + 8u * BAUD) / (16u * BAUD))   /* rounded: 22 */
#endif
#ifndef FRAME_CYC
#define FRAME_CYC  (CLK_HZ / FPS)
#endif

/* ------------------------------------------------------------------------ */
/*  Memory map                                                              */
/* ------------------------------------------------------------------------ */
#define TIMER0_BASE   0x40001000u
#define UART_BASE     0x40002000u

#define T_VAL     0x00u
#define T_CTRL    0x04u
#define T_CMP     0x08u

#define U_RBR     0x00u
#define U_THR     0x00u
#define U_DLL     0x00u
#define U_IER     0x04u
#define U_DLM     0x04u
#define U_FCR     0x08u
#define U_LCR     0x0Cu
#define U_LSR     0x14u

#define LSR_DR    0x01u
#define LSR_THRE  0x20u

static inline uint32_t rd32(uint32_t a)             { return *(volatile uint32_t *)a; }
static inline void     wr32(uint32_t a, uint32_t v) { *(volatile uint32_t *)a = v; }

/* ------------------------------------------------------------------------ */
/*  Playfield (cells) and fixed point (4 fractional bits)                   */
/* ------------------------------------------------------------------------ */
#define FW        80          /* columns 0..79                              */
#define FH        22          /* rows 0..21                                 */
#define PH        4           /* paddle height                              */
#define P1X       2           /* left paddle column                         */
#define P2X       77          /* right paddle column                        */
#define MIDX      40
#define WIN_SCORE 7

#define FIX(c)    ((int32_t)(c) << 4)
#define CELL(f)   ((int32_t)(f) >> 4)

#define SPEED0    9           /* 9/16 cell per frame at serve               */
#define SPEED_MAX 22

enum { ST_PLAY = 0, ST_PAUSE = 1, ST_SERVE = 2, ST_P1WIN = 3, ST_P2WIN = 4 };
enum { MODE_TERM = 1, MODE_BIN = 2 };

typedef struct {
    int32_t  bx, by, vx, vy;      /* ball, fixed point                      */
    int32_t  p1, p2;              /* paddle top rows                        */
    uint32_t s1, s2;
    uint32_t state;
    uint32_t ai;                  /* 1: right paddle driven by the core     */
    uint32_t serve_dir;           /* 0: towards left, 1: towards right      */
    uint32_t last;                /* last point: 0 none, 1 LEFT, 2 RIGHT    */
    uint32_t frame;
} game_t;

/* Trap record written by trap_entry in ../regtest/startup.S. No trap is
 * expected; a bus error is counted and the faulting access skipped. */
typedef struct {
    uint32_t count, cause, tval, epc, total;
} trap_rec_t;

volatile trap_rec_t g_trap;

static game_t   g;
static uint32_t mode;

/* last drawn terminal state, for incremental redraw */
static int32_t  d_bx, d_by, d_p1, d_p2;
static uint32_t d_s1, d_s2, d_state;

/* ------------------------------------------------------------------------ */
/*  UART                                                                    */
/* ------------------------------------------------------------------------ */
static void uart_init(void)
{
    wr32(UART_BASE + U_LCR, 0x83);        /* DLAB = 1, 8N1 */
    wr32(UART_BASE + U_DLL, UART_DIV & 0xFFu);
    wr32(UART_BASE + U_DLM, (UART_DIV >> 8) & 0xFFu);
    wr32(UART_BASE + U_LCR, 0x03);        /* DLAB = 0 */
    wr32(UART_BASE + U_IER, 0x00);
    wr32(UART_BASE + U_FCR, 0x07);        /* FIFOs on and reset */
}

static void putc_(uint32_t c)
{
    while (!(rd32(UART_BASE + U_LSR) & LSR_THRE))
        ;
    wr32(UART_BASE + U_THR, c & 0xFFu);
}

/* -1 if nothing received */
static int32_t getc_nb(void)
{
    if (!(rd32(UART_BASE + U_LSR) & LSR_DR))
        return -1;
    return (int32_t)(rd32(UART_BASE + U_RBR) & 0xFFu);
}

/* Byte i of a string, through an aligned word load (no lbu). */
static uint32_t str_at(const char *s, uint32_t i)
{
    uint32_t a = (uint32_t)(uintptr_t)s + i;
    uint32_t w = *(const volatile uint32_t *)(a & ~3u);
    return (w >> ((a & 3u) << 3)) & 0xFFu;
}

static void puts_(const char *s)
{
    uint32_t c;
    for (uint32_t i = 0; (c = str_at(s, i)) != 0; i++)
        putc_(c);
}

/* Decimal, 0..999, without division. */
static void putdec(uint32_t v)
{
    uint32_t h = 0, t = 0;
    while (v >= 100) { v -= 100; h++; }
    while (v >= 10)  { v -= 10;  t++; }
    if (h)
        putc_('0' + h);
    if (h || t)
        putc_('0' + t);
    putc_('0' + v);
}

/* ------------------------------------------------------------------------ */
/*  Timer                                                                   */
/* ------------------------------------------------------------------------ */
static uint32_t t_last;

static void timer_init(void)
{
    wr32(TIMER0_BASE + T_CTRL, 0);
    wr32(TIMER0_BASE + T_CMP, FRAME_CYC);   /* also clears VAL */
    wr32(TIMER0_BASE + T_CTRL, 1);          /* EN, prescaler bypass */
    t_last = 0;
}

static void wait_frame(void)
{
    uint32_t v;
    for (;;) {
        v = rd32(TIMER0_BASE + T_VAL);
        if (v < t_last)
            break;
        t_last = v;
    }
    t_last = v;
}

/* xorshift32 seeded from the free-running timer */
static uint32_t rng = 0x1234567u;

static uint32_t rand_(void)
{
    rng ^= rng << 13;
    rng ^= rng >> 17;
    rng ^= rng << 5;
    return rng;
}

/* ------------------------------------------------------------------------ */
/*  Game logic                                                              */
/* ------------------------------------------------------------------------ */
static void ball_center(void)
{
    g.bx = FIX(MIDX);
    g.by = FIX(FH / 2);
    g.vx = 0;
    g.vy = 0;
}

static void serve(void)
{
    uint32_t r = rand_();
    int32_t  vy = (int32_t)(r & 7u) - 3;          /* -3..4 */

    g.vx = g.serve_dir ? SPEED0 : -SPEED0;
    g.vy = vy;
    g.state = ST_PLAY;
}

static void game_reset(void)
{
    g.p1 = (FH - PH) / 2;
    g.p2 = (FH - PH) / 2;
    g.s1 = 0;
    g.s2 = 0;
    g.ai = 1;
    g.last = 0;
    g.serve_dir = rand_() & 1u;
    ball_center();
    g.state = ST_SERVE;
}

static int32_t clamp_paddle(int32_t p)
{
    if (p < 0)
        return 0;
    if (p > FH - PH)
        return FH - PH;
    return p;
}

/* Hit position on the paddle decides the outgoing angle. */
static int32_t bounce_vy(int32_t row_on_paddle)
{
    static const int32_t vy_tab[PH] = { -10, -4, 4, 10 };
    return vy_tab[row_on_paddle];
}

static int32_t speed_up(int32_t v)
{
    int32_t a = v < 0 ? -v : v;
    if (a < SPEED_MAX)
        a++;
    return v < 0 ? -a : a;
}

/* A point goes to the side whose OPPONENT let the ball out:
 * out on the right -> LEFT (P1) scores, out on the left -> RIGHT (P2). */
static void point(uint32_t to_p1)
{
    if (to_p1)
        g.s1++;
    else
        g.s2++;
    g.last = to_p1 ? 1u : 2u;
    g.serve_dir = to_p1;                  /* loser receives */
    ball_center();
    if (g.s1 >= WIN_SCORE)
        g.state = ST_P1WIN;
    else if (g.s2 >= WIN_SCORE)
        g.state = ST_P2WIN;
    else
        g.state = ST_SERVE;
}

static void ai_move(void)
{
    int32_t target, centre;

    if (!g.ai)
        return;
    if (g.frame & 1u)                     /* half speed: beatable */
        return;
    target = (g.vx > 0) ? CELL(g.by) : FH / 2;
    centre = g.p2 + PH / 2;
    if (target < centre)
        g.p2 = clamp_paddle(g.p2 - 1);
    else if (target > centre)
        g.p2 = clamp_paddle(g.p2 + 1);
}

static void update(void)
{
    int32_t ox, nx, ny, row;

    ai_move();

    if (g.state != ST_PLAY)
        return;

    ox = CELL(g.bx);
    g.bx += g.vx;
    g.by += g.vy;

    /* top / bottom walls: reflect */
    if (g.by < 0) {
        g.by = -g.by;
        g.vy = -g.vy;
    } else if (g.by >= FIX(FH)) {
        g.by = FIX(FH) - 1 - (g.by - FIX(FH));
        g.vy = -g.vy;
    }

    nx = CELL(g.bx);
    ny = CELL(g.by);

    /* left paddle: crossing into column P1X + 1 */
    if (g.vx < 0 && ox > P1X + 1 && nx <= P1X + 1) {
        row = ny - g.p1;
        if (row >= 0 && row < PH) {
            g.bx = FIX(P1X + 1) + 8;
            g.vx = speed_up(-g.vx);
            g.vy = bounce_vy(row);
            return;
        }
    }
    /* right paddle: crossing into column P2X - 1 */
    if (g.vx > 0 && ox < P2X - 1 && nx >= P2X - 1) {
        row = ny - g.p2;
        if (row >= 0 && row < PH) {
            g.bx = FIX(P2X - 1) + 7;
            g.vx = speed_up(-g.vx);
            g.vy = bounce_vy(row);
            return;
        }
    }

    if (g.bx < 0)
        point(0);
    else if (g.bx >= FIX(FW))
        point(1);
}

/* ------------------------------------------------------------------------ */
/*  Terminal renderer (ANSI)                                                */
/*    row 1: scores, row 2: top wall, field row y -> row y + 3,             */
/*    row FH + 3: bottom wall, row FH + 4: status line. Column x -> x + 1.  */
/* ------------------------------------------------------------------------ */
#define C_RESET  "\x1b[0m"
#define C_WALL   "\x1b[36m"
#define C_PAD    "\x1b[1;32m"
#define C_BALL   "\x1b[1;33m"
#define C_TEXT   "\x1b[1;37m"
#define C_DIM    "\x1b[2;37m"

static void at(int32_t col, int32_t row)
{
    puts_("\x1b[");
    putdec((uint32_t)row);
    putc_(';');
    putdec((uint32_t)col);
    putc_('H');
}

static void field_cell(int32_t x, int32_t y, uint32_t c)
{
    at(x + 1, y + 3);
    putc_(c);
}

/* What the empty field shows at (x, y): the dotted centre line or a blank. */
static uint32_t bg_char(int32_t x, int32_t y)
{
    return (x == MIDX && !(y & 1)) ? ':' : ' ';
}

static void draw_paddle(int32_t x, int32_t top, uint32_t on)
{
    if (on)
        puts_(C_PAD);
    for (int32_t r = 0; r < PH; r++)
        field_cell(x, top + r, on ? '#' : ' ');
    if (on)
        puts_(C_RESET);
}

/* Put back what the field shows at (x, y) without the ball: a paddle cell if
 * a paddle covers it, else the background. The ball crosses the paddle
 * columns above or below a paddle when a player misses. */
static void restore_cell(int32_t x, int32_t y)
{
    int32_t top = (x == P1X) ? g.p1 : (x == P2X) ? g.p2 : -PH;

    if (y >= top && y < top + PH) {
        puts_(C_PAD);
        field_cell(x, y, '#');
    } else {
        puts_(C_DIM);
        field_cell(x, y, bg_char(x, y));
    }
    puts_(C_RESET);
}

static void draw_scores(void)
{
    at(1, 1);
    puts_("\x1b[2K" C_TEXT "  RISCFORGE PONG      LEFT (w/s)  ");
    putdec(g.s1);
    puts_("  :  ");
    putdec(g.s2);
    puts_(g.ai ? "  RIGHT (CPU)" : "  RIGHT (i/k)");
    puts_(C_RESET);
}

static void draw_status(void)
{
    at(1, FH + 4);
    puts_("\x1b[2K" C_DIM);
    switch (g.state) {
    case ST_SERVE:
        if (g.last == 1)
            puts_(C_TEXT "  LEFT scores!   SPACE to serve");
        else if (g.last == 2)
            puts_(C_TEXT "  RIGHT scores!   SPACE to serve");
        else
            puts_("  SPACE serve   w/s left   i/k right   a CPU   p pause   r restart");
        break;
    case ST_PAUSE: puts_("  PAUSED - press p to continue"); break;
    case ST_P1WIN: puts_(C_TEXT "  LEFT WINS!   press r to play again"); break;
    case ST_P2WIN: puts_(C_TEXT "  RIGHT WINS!   press r to play again"); break;
    default:       puts_("  w/s left   i/k right   a CPU   p pause   r restart   on RISCFORGE RV32I"); break;
    }
    puts_(C_RESET);
}

static void term_full_redraw(void)
{
    puts_(C_RESET "\x1b[2J\x1b[?25l");
    puts_(C_WALL);
    at(1, 2);
    for (int32_t x = 0; x < FW; x++)
        putc_('=');
    at(1, FH + 3);
    for (int32_t x = 0; x < FW; x++)
        putc_('=');
    puts_(C_DIM);
    for (int32_t y = 0; y < FH; y += 2)
        field_cell(MIDX, y, ':');
    puts_(C_RESET);

    draw_scores();
    draw_status();
    draw_paddle(P1X, g.p1, 1);
    draw_paddle(P2X, g.p2, 1);
    puts_(C_BALL);
    field_cell(CELL(g.bx), CELL(g.by), 'O');
    puts_(C_RESET);

    d_bx = CELL(g.bx);
    d_by = CELL(g.by);
    d_p1 = g.p1;
    d_p2 = g.p2;
    d_s1 = g.s1;
    d_s2 = g.s2;
    d_state = g.state;
}

static void term_frame(void)
{
    int32_t cx = CELL(g.bx), cy = CELL(g.by);

    if (g.p1 != d_p1) {
        draw_paddle(P1X, d_p1, 0);
        draw_paddle(P1X, g.p1, 1);
        d_p1 = g.p1;
    }
    if (g.p2 != d_p2) {
        draw_paddle(P2X, d_p2, 0);
        draw_paddle(P2X, g.p2, 1);
        d_p2 = g.p2;
    }
    if (cx != d_bx || cy != d_by) {
        if (d_bx >= 0 && d_bx < FW)
            restore_cell(d_bx, d_by);
        if (cx >= 0 && cx < FW) {
            puts_(C_BALL);
            field_cell(cx, cy, 'O');
            puts_(C_RESET);
        }
        d_bx = cx;
        d_by = cy;
    }
    /* The score line is also redrawn on every state change (serve, point,
     * pause, win), so it cannot stay stale even if one update is missed. */
    if (g.s1 != d_s1 || g.s2 != d_s2 || g.state != d_state) {
        draw_scores();
        d_s1 = g.s1;
        d_s2 = g.s2;
    }
    if (g.state != d_state) {
        draw_status();
        d_state = g.state;
    }
    at(1, FH + 5);                        /* park the cursor below the field */
}

/* ------------------------------------------------------------------------ */
/*  Binary renderer (pong_viewer.py)                                        */
/* ------------------------------------------------------------------------ */
static uint32_t pkt_sum;

static void pkt_byte(uint32_t b)
{
    b &= 0xFFu;
    pkt_sum += b;
    putc_(b);
}

static void bin_frame(void)
{
    putc_(0xA5);
    putc_(0x5A);
    pkt_sum = 0;
    pkt_byte((uint32_t)g.bx);
    pkt_byte((uint32_t)g.bx >> 8);
    pkt_byte((uint32_t)g.by);
    pkt_byte((uint32_t)g.by >> 8);
    pkt_byte((uint32_t)g.p1);
    pkt_byte((uint32_t)g.p2);
    pkt_byte(g.s1);
    pkt_byte(g.s2);
    pkt_byte(g.state | (g.ai << 4));
    pkt_byte(g.last);
    pkt_byte(0);
    pkt_byte(0);
    pkt_byte(0);
    putc_(pkt_sum);
}

/* ------------------------------------------------------------------------ */
/*  Input                                                                   */
/* ------------------------------------------------------------------------ */
static void set_mode(uint32_t m)
{
    if (m == mode)
        return;
    mode = m;
    if (mode == MODE_TERM)
        term_full_redraw();
    else
        puts_(C_RESET "\x1b[2J\x1b[H\x1b[?25h");   /* leave the terminal clean */
}

static void handle_input(void)
{
    int32_t c;

    while ((c = getc_nb()) >= 0) {
        rng ^= rd32(TIMER0_BASE + T_VAL);         /* human timing = entropy */
        switch (c) {
        case 'w': case 'W': g.p1 = clamp_paddle(g.p1 - 1); break;
        case 's': case 'S': g.p1 = clamp_paddle(g.p1 + 1); break;
        case 'i': case 'I': g.ai = 0; g.p2 = clamp_paddle(g.p2 - 1); break;
        case 'k': case 'K': g.ai = 0; g.p2 = clamp_paddle(g.p2 + 1); break;
        case 'a': case 'A': g.ai = 1; break;
        case 'p': case 'P':
            if (g.state == ST_PLAY)
                g.state = ST_PAUSE;
            else if (g.state == ST_PAUSE)
                g.state = ST_PLAY;
            break;
        case ' ':
            if (g.state == ST_SERVE)
                serve();
            break;
        case 'r': case 'R':
            game_reset();
            if (mode == MODE_TERM)
                term_full_redraw();
            break;
        case 0x01: set_mode(MODE_TERM); break;   /* sent by pong_viewer.py */
        case 0x02: set_mode(MODE_BIN);  break;
        default: break;
        }
    }
}

/* ------------------------------------------------------------------------ */
int main(void)
{
    uint32_t ai_shown;

    uart_init();
    timer_init();
    game_reset();
    mode = MODE_TERM;
    term_full_redraw();
    ai_shown = g.ai;

    for (;;) {
        wait_frame();
        handle_input();
        update();
        g.frame++;

        if (mode == MODE_TERM) {
            if (g.ai != ai_shown) {
                draw_scores();
                ai_shown = g.ai;
            }
            term_frame();
        } else {
            bin_frame();
        }
    }
    return 0;
}
