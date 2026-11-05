/* =============================================================================
 * RISCFORGE 1TOPS - robotic arm demo (firmware)
 * =============================================================================
 * Drives the lab's WidowX-200 arm (Dynamixel Protocol 2.0: IDs 1-5 XM430-W350,
 * IDs 6-7 XL430-W250, same control table) from the Nexys 4 DDR switches and
 * buttons. Board top: fpga/nexys4ddr/arm.
 *
 * Bus: the SoC UART at 1 Mbps (32 MHz / (16 x 2)). The link is chosen by SW13
 * at reset (top_arm switches the UART pins with it):
 *   SW13 off  direct: the half-duplex DATA line on Pmod JA through a
 *             direction-controlled buffer; GPIO[16] = DXL_DIR (1 = transmit).
 *   SW13 on   laptop relay: the board's USB-UART to the laptop, where
 *             dxl_relay.py passes the packets to a U2D2 on the arm. Servo
 *             answers come back through two USB hops, so the answer timeout
 *             is 50 ms instead of 3 ms.
 * Either way this firmware builds every packet; nothing in the servos'
 * EEPROM is written.
 *
 * Joints and Dynamixel IDs
 *   SW0 waist (ID 1)        SW1 shoulder (ID 2, ID 3 = 4095 - ID 2)
 *   SW2 elbow (ID 4)        SW3 wrist angle (ID 5)
 *   SW4 wrist rotate (ID 6) SW5 gripper (ID 7)
 *
 * Controls
 *   SW15     torque: off -> on reads every present position, makes it the
 *            target (no jump), then enables torque; on -> off makes the arm limp.
 *            IDs 1..6 must answer; the gripper (ID 7) is used only if it does.
 *   SW0..5   select joints (several at once allowed)
 *   BTNU/D   while held: move the selected joints up / down
 *   SW14     fast jog (3x step)
 *   BTNC     go to the C pose (taught by hand on this arm), one joint at a
 *            time, slowly: shoulder, elbow, wrist angle, waist, wrist rotate.
 *            Jogging is ignored until it finishes. Torque must be on.
 *   BTNR     ping IDs 1..7 again (LEDs + console)
 *   BTNL     print present positions on the console
 *
 * USB keyboard on the Nexys USB HOST connector (its PIC24 sends PS/2 on two
 * pins wired to GPIO[21]/[22]; decoded below, clock held low while the servo
 * bus is busy):
 *   1..6       select joint (waist, shoulder, elbow, wrist angle, wrist
 *              rotate, gripper)
 *   W/S, Up/Dn while held: move the selected joint
 *   A/D        step 5 / 10 / 20 / 30 ticks per 20 ms
 *   Z/X        speed (profile velocity 30 / 60 / 100 / 200)
 *   C          C pose          R   rest pose (balanced, shoulder lowered last)
 *   P          print positions T   torque on (SW15 must be on)
 *   O then Y   torque off      Esc stop a pose move, hold     H  help
 *
 * LEDs (top_arm: LED[15:4] = gpio_out[11:0])
 *   LED4      heartbeat (0.5 s)                          gpio_out[0]
 *   LED5      bus error since the last ping scan        gpio_out[1]
 *             (timeout / CRC / status error)
 *   LED6      fast jog (SW14)                            gpio_out[2]
 *   LED7      a move / pose command is running           gpio_out[3]
 *   LED8..14  ID 1..7 answered the last ping             gpio_out[4..10]
 *   LED15     torque on                                  gpio_out[11]
 *
 * Console: the UART TX is mirrored to the PC (USB-UART) by the board top. Status
 * text is sent with DXL_DIR = 0, so it never reaches the servos. Open the COM
 * port at 1000000 baud 8N1.
 *
 * Firmware rules followed (see project notes):
 *   - 32-bit loads and stores only, everywhere (build.py checks the dump):
 *     packet buffers hold one byte per 32-bit word, strings are read through
 *     aligned word loads (str_at).
 *   - UART: RBR is only read when LSR.DR = 1 and LCR.DLAB = 0; nothing but
 *     DLL/DLM is accessed while DLAB = 1; divisor 2 (the minimum).
 *   - No M extension: no multiply/divide.
 * ========================================================================== */

#include <stdint.h>

/* ------------------------------------------------------------------------ */
/*  Board configuration                                                     */
/* ------------------------------------------------------------------------ */
#define CLK_HZ       32000000u        /* Nexys 4 DDR arm top: 32 MHz SoC clock */
#define UART_DIV     2u               /* 32 MHz / (16 x 2) = 1 000 000 baud      */
#define CYC_PER_MS   (CLK_HZ / 1000u) /* compile-time constant                  */

#define LOOP_MS      20u              /* control loop period                    */
#define RX_TIMEOUT_MS 3u              /* status packet timeout (return delay 0.5 ms) */
#define RX_TIMEOUT_RELAY_MS 50u       /* through the laptop relay: 2 x USB delay */
#define READ_TRIES   3u

#define STEP_SLOW    10               /* ticks per loop: ~44 deg/s              */
#define STEP_FAST    30               /* ticks per loop: ~132 deg/s             */
#define PROFILE_VEL  100u             /* 0.229 rpm units: ~23 rpm               */
#define PROFILE_ACC  20u
#define SHOULDER_MISMATCH 100         /* max |ID3 - (4095 - ID2)| to enable     */
#define POSE_VEL     30u              /* profile velocity during a pose move    */
#define POSE_TOL     80               /* ticks: settled (gravity droop ~30)     */
#define POSE_LOOPS   400u             /* 8 s per joint, then the move is dropped */

/* ------------------------------------------------------------------------ */
/*  Memory map                                                              */
/* ------------------------------------------------------------------------ */
#define TIMER0_BASE   0x40001000u
#define UART_BASE     0x40002000u
#define GPIO_BASE     0x40003000u

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
#define LSR_TEMT  0x40u

/* GPIO (reggen offsets, gpio_reg_pkg.sv) */
#define G_EN      0x080u
#define G_IN      0x100u
#define G_OUT     0x180u

/* GPIO inputs (top_arm) */
#define IN_SW_MASK   0x0000FFFFu
#define IN_SEL_MASK  0x0000003Fu      /* SW0..SW5 joint select */
#define IN_SW_RELAY  (1u << 13)       /* 1 = servo bus through the laptop relay */
#define IN_SW_FAST   (1u << 14)
#define IN_SW_TORQUE (1u << 15)
#define IN_BTNC      (1u << 16)
#define IN_BTNU      (1u << 17)
#define IN_BTND      (1u << 18)
#define IN_BTNL      (1u << 19)
#define IN_BTNR      (1u << 20)
#define IN_ALL       0x007FFFFFu      /* switches, buttons, PS/2 */

#define IN_PS2_CLK   (1u << 21)
#define IN_PS2_DATA  (1u << 22)

/* GPIO outputs (top_arm: LED[15:4] = gpio_out[11:0], so bit n -> LD(n+4)) */
#define OUT_HEART    (1u << 0)        /* LD4  */
#define OUT_ERR      (1u << 1)        /* LD5  */
#define OUT_FAST     (1u << 2)        /* LD6  */
#define OUT_CMD      (1u << 3)        /* LD7  */
#define OUT_PING_SHIFT 4u             /* LD8..LD14: bit 4 + (id - 1) */
#define OUT_PING_MASK (0x7Fu << OUT_PING_SHIFT)
#define OUT_TORQUE   (1u << 11)       /* LD15 */
#define OUT_DXL_DIR  (1u << 16)
#define OUT_PS2_CLK_LOW  (1u << 17)   /* 1 = hold the keyboard clock low */
#define OUT_PS2_DATA_LOW (1u << 18)   /* stays 0 (receive only)          */

static inline uint32_t rd32(uint32_t a)             { return *(volatile uint32_t *)a; }
static inline void     wr32(uint32_t a, uint32_t v) { *(volatile uint32_t *)a = v; }

/* ------------------------------------------------------------------------ */
/*  Dynamixel Protocol 2.0 (X-series control table: XM430 / XL430)          */
/* ------------------------------------------------------------------------ */
#define INST_PING        0x01u
#define INST_READ        0x02u
#define INST_WRITE       0x03u
#define INST_SYNC_WRITE  0x83u
#define INST_STATUS      0x55u
#define ID_BROADCAST     0xFEu

#define A_MAX_POS_LIMIT  48u          /* 4 bytes, EEPROM (read only here) */
#define A_MIN_POS_LIMIT  52u          /* 4 bytes, EEPROM (read only here) */
#define A_TORQUE_ENABLE  64u          /* 1 byte  */
#define A_PROFILE_ACC    108u         /* 4 bytes */
#define A_PROFILE_VEL    112u         /* 4 bytes */
#define A_GOAL_POSITION  116u         /* 4 bytes */
#define A_MOVING         122u         /* 1 byte  */
#define A_PRESENT_POS    132u         /* 4 bytes */

#define NUM_IDS     7u
#define NUM_JOINTS  6u
#define J_SHOULDER  1u                /* moves ID 2 and ID 3 together */

/* Trap record written by trap_entry in ../regtest/startup.S. No trap is
 * expected; a bus error is counted and the faulting access skipped. */
typedef struct {
    uint32_t count, cause, tval, epc, total;
} trap_rec_t;

volatile trap_rec_t g_trap;

/* Joint j: Dynamixel ID and software limits in ticks (2048 = 0 deg,
 * 4096 ticks per turn). Limits from the arm repo (wx200_kinematics.py
 * JOINT_LIMITS), except two minimums lowered to this arm's measured poses:
 * shoulder 819 -> 740 (rest pose 742, on its stop) and wrist angle
 * 910 -> 780 (C pose 834). The servos' own EEPROM limits apply on top. */
static const uint32_t joint_id[NUM_JOINTS]  = { 1, 2, 4, 5, 6, 7 };
static const uint32_t joint_min[NUM_JOINTS] = {    0,  740,  819,  780,    0,    0 };
static const uint32_t joint_max[NUM_JOINTS] = { 4095, 3334, 3095, 3447, 4095, 4095 };

/* Poses of this arm in raw ticks, by joint (waist, shoulder, elbow, wrist
 * angle, wrist rotate, gripper - the gripper is left where it is), and the
 * order the joints are moved in.
 *   C pose:    taught by hand and reached through the U2D2, 2026-11-04.
 *              Lift the shoulder first.
 *   rest pose: balanced rest recorded with arm_teleop, 2026-11-04
 *              (shoulder 742 is on its stop; 760 keeps it just above).
 *              Lower the shoulder last. */
#define POSE_STEPS 5u
static const uint32_t c_pose[NUM_JOINTS]     = { 3974, 1160, 1963,  834, 2008, 0 };
static const uint32_t c_order[POSE_STEPS]    = { 1, 2, 3, 0, 4 };
static const uint32_t rest_pose[NUM_JOINTS]  = { 3887,  760,  928, 1442, 2000, 0 };
static const uint32_t rest_order[POSE_STEPS] = { 3, 2, 0, 4, 1 };

static uint32_t lim_min[NUM_JOINTS], lim_max[NUM_JOINTS];  /* effective limits */
static int32_t  target[NUM_JOINTS];                        /* goal positions   */
static uint32_t present[NUM_IDS + 1];                      /* by ID, 1..7      */
static int32_t  off3;             /* ID3 - (4095 - ID2) measured at torque-on */

static uint32_t gout;             /* shadow of GPIO_OUT */
static uint32_t ping_mask;
static uint32_t torque_on;
static uint32_t avail;            /* bit id-1: ID answered when torque came on */

/* ------------------------------------------------------------------------ */
/*  GPIO                                                                    */
/* ------------------------------------------------------------------------ */
static void gpio_init(void)
{
    gout = 0;
    wr32(GPIO_BASE + G_OUT, 0);           /* DXL_DIR = 0: bus not driven */
    wr32(GPIO_BASE + G_EN, IN_ALL);       /* sample switches, buttons, PS/2 */
}

static void out_set(uint32_t mask, uint32_t on)
{
    gout = on ? (gout | mask) : (gout & ~mask);
    wr32(GPIO_BASE + G_OUT, gout);
}

static void out_field(uint32_t mask, uint32_t val)
{
    gout = (gout & ~mask) | (val & mask);
    wr32(GPIO_BASE + G_OUT, gout);
}

/* ------------------------------------------------------------------------ */
/*  Timer: TIMER0 free-running at CLK_HZ (CMP = 0, wraps at 2^32)           */
/* ------------------------------------------------------------------------ */
static void timer_init(void)
{
    wr32(TIMER0_BASE + T_CTRL, 0);
    wr32(TIMER0_BASE + T_CMP, 0);         /* no compare; also clears VAL */
    wr32(TIMER0_BASE + T_CTRL, 1);        /* EN, prescaler bypass */
}

static inline uint32_t now(void) { return rd32(TIMER0_BASE + T_VAL); }

static void delay_ms(uint32_t ms)
{
    uint32_t t0 = now();
    while (ms--) {
        while (now() - t0 < CYC_PER_MS)
            ;
        t0 += CYC_PER_MS;
    }
}

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

static void uart_tx(uint32_t c)
{
    while (!(rd32(UART_BASE + U_LSR) & LSR_THRE))
        ;
    wr32(UART_BASE + U_THR, c & 0xFFu);
}

static void uart_tx_drain(void)
{
    while (!(rd32(UART_BASE + U_LSR) & LSR_TEMT))
        ;
}

/* Bounded: a line that never stops sending (noise, a terminal typing into
 * the relay port) must not lock the firmware here. */
static void uart_rx_flush(void)
{
    for (uint32_t n = 0; n < 64u && (rd32(UART_BASE + U_LSR) & LSR_DR); n++)
        (void)rd32(UART_BASE + U_RBR);
}

/* Next received byte, or -1 if none arrives within timeout_cyc of t0. */
static int32_t uart_rx(uint32_t t0, uint32_t timeout_cyc)
{
    while (!(rd32(UART_BASE + U_LSR) & LSR_DR)) {
        if (now() - t0 >= timeout_cyc)
            return -1;
    }
    return (int32_t)(rd32(UART_BASE + U_RBR) & 0xFFu);
}

/* ------------------------------------------------------------------------ */
/*  Console (PC side of the mirrored TX, DXL_DIR = 0)                       */
/* ------------------------------------------------------------------------ */
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
        uart_tx(c);
}

/* Decimal, 0..99999, without division. */
static void putdec(uint32_t v)
{
    static const uint32_t pow10[4] = { 10000, 1000, 100, 10 };
    uint32_t started = 0;
    for (uint32_t k = 0; k < 4; k++) {
        uint32_t d = 0;
        while (v >= pow10[k]) { v -= pow10[k]; d++; }
        if (d || started) { uart_tx('0' + d); started = 1; }
    }
    uart_tx('0' + v);
}

/* ------------------------------------------------------------------------ */
/*  Dynamixel packets                                                       */
/* ------------------------------------------------------------------------ */
static uint32_t pkt[96];          /* one byte per word */
static uint32_t rx_tmo = RX_TIMEOUT_MS * CYC_PER_MS;   /* set from SW13 */
static uint32_t rxp[32];          /* status packet parameters */
static uint32_t rx_err;           /* status packet error byte */

/* CRC-16 of Protocol 2.0 (poly 0x8005, init 0, MSB first): the same values
 * as the table in DynamixelController.cpp. */
static uint32_t crc_upd(uint32_t crc, uint32_t b)
{
    crc ^= (b & 0xFFu) << 8;
    for (uint32_t k = 0; k < 8; k++)
        crc = (crc & 0x8000u) ? ((crc << 1) ^ 0x8005u) : (crc << 1);
    return crc & 0xFFFFu;
}

/* Builds and sends one instruction packet. Parameters are byte-stuffed
 * (0xFD after FF FF FD) as Protocol 2.0 requires. */
static void dxl_send(uint32_t id, uint32_t inst, const uint32_t *par, uint32_t n)
{
    uint32_t len, i, k, crc;

    pkt[0] = 0xFF; pkt[1] = 0xFF; pkt[2] = 0xFD; pkt[3] = 0x00;
    pkt[4] = id;
    pkt[7] = inst;
    k = 8;
    for (i = 0; i < n; i++) {
        /* full-word read: "par[i] & 0xFF" would compile to lbu */
        pkt[k++] = *(const volatile uint32_t *)&par[i] & 0xFFu;
        if (pkt[k - 1] == 0xFD && pkt[k - 2] == 0xFF && pkt[k - 3] == 0xFF)
            pkt[k++] = 0xFD;
    }
    len = k - 8 + 3;                      /* instruction + params + CRC */
    pkt[5] = len & 0xFFu;
    pkt[6] = (len >> 8) & 0xFFu;
    crc = 0;
    for (i = 0; i < k; i++)
        crc = crc_upd(crc, pkt[i]);
    pkt[k++] = crc & 0xFFu;
    pkt[k++] = (crc >> 8) & 0xFFu;

    uart_tx_drain();                      /* console text finished          */
    uart_rx_flush();
    out_set(OUT_DXL_DIR, 1);              /* drive the bus                  */
    for (i = 0; i < k; i++)
        uart_tx(pkt[i]);
    uart_tx_drain();                      /* last stop bit on the wire      */
    out_set(OUT_DXL_DIR, 0);              /* release it for the answer      */
}

/* Waits for one status packet from `id`. Returns the number of parameters
 * (after the error byte), or -1 on timeout, wrong ID, bad CRC or a set
 * error byte. Parameters land in rxp[], one byte per word. */
static int32_t dxl_recv(uint32_t id, uint32_t max_par)
{
    uint32_t t0 = now();
    const uint32_t tmo = rx_tmo;
    uint32_t sync = 0, crc = 0, len, n, i;
    int32_t  c;

    /* header FF FF FD 00 */
    while (sync < 4) {
        if ((c = uart_rx(t0, tmo)) < 0)
            return -1;
        if (sync < 2)       sync = (c == 0xFF) ? sync + 1 : 0;
        else if (sync == 2) sync = (c == 0xFD) ? 3 : ((c == 0xFF) ? 2 : 0);
        else                sync = (c == 0x00) ? 4 : 0;
    }
    crc = crc_upd(crc_upd(crc_upd(crc_upd(0, 0xFF), 0xFF), 0xFD), 0x00);

    /* ID, LEN_L, LEN_H, INST, ERR */
    if ((c = uart_rx(t0, tmo)) < 0) return -1;
    crc = crc_upd(crc, (uint32_t)c);
    if ((uint32_t)c != id) return -1;
    if ((c = uart_rx(t0, tmo)) < 0) return -1;
    crc = crc_upd(crc, (uint32_t)c);
    len = (uint32_t)c;
    if ((c = uart_rx(t0, tmo)) < 0) return -1;
    crc = crc_upd(crc, (uint32_t)c);
    len |= (uint32_t)c << 8;
    if (len < 4 || len - 4 > max_par) return -1;
    if ((c = uart_rx(t0, tmo)) < 0) return -1;
    crc = crc_upd(crc, (uint32_t)c);
    if ((uint32_t)c != INST_STATUS) return -1;
    if ((c = uart_rx(t0, tmo)) < 0) return -1;
    crc = crc_upd(crc, (uint32_t)c);
    rx_err = (uint32_t)c;

    n = len - 4;                          /* minus INST, ERR, CRC_L, CRC_H */
    for (i = 0; i < n; i++) {
        if ((c = uart_rx(t0, tmo)) < 0) return -1;
        crc = crc_upd(crc, (uint32_t)c);
        rxp[i] = (uint32_t)c;
    }
    if ((c = uart_rx(t0, tmo)) < 0) return -1;
    if ((uint32_t)c != (crc & 0xFFu)) return -1;
    if ((c = uart_rx(t0, tmo)) < 0) return -1;
    if ((uint32_t)c != ((crc >> 8) & 0xFFu)) return -1;
    if (rx_err & 0x7Fu)                   /* bit 7 = hardware alert, ignored */
        return -1;
    return (int32_t)n;
}

static uint32_t bus_err;

static uint32_t dxl_ping(uint32_t id)
{
    dxl_send(id, INST_PING, 0, 0);
    return dxl_recv(id, 3) == 3;
}

/* Reads `size` (1 or 4) bytes at `addr`. Returns 1 on success. */
static uint32_t dxl_read(uint32_t id, uint32_t addr, uint32_t size, uint32_t *val)
{
    uint32_t par[4];
    par[0] = addr & 0xFFu; par[1] = (addr >> 8) & 0xFFu;
    par[2] = size;         par[3] = 0;
    for (uint32_t t = 0; t < READ_TRIES; t++) {
        dxl_send(id, INST_READ, par, 4);
        if (dxl_recv(id, 4) == (int32_t)size) {
            uint32_t v = 0;
            for (uint32_t i = size; i-- > 0;)
                v = (v << 8) | rxp[i];
            *val = v;
            return 1;
        }
    }
    bus_err = 1;
    return 0;
}

/* Writes `size` (1 or 4) bytes and waits for the status packet. */
static uint32_t dxl_write(uint32_t id, uint32_t addr, uint32_t size, uint32_t val)
{
    uint32_t par[6];
    par[0] = addr & 0xFFu; par[1] = (addr >> 8) & 0xFFu;
    for (uint32_t i = 0; i < size; i++) {
        par[2 + i] = val & 0xFFu;
        val >>= 8;
    }
    dxl_send(id, INST_WRITE, par, 2 + size);
    if (dxl_recv(id, 0) == 0)
        return 1;
    bus_err = 1;
    return 0;
}

/* One SYNC WRITE of Goal Position for all 7 IDs (no status packets). */
static void dxl_sync_goal(void)
{
    uint32_t par[4 + 5 * NUM_IDS];
    uint32_t pos[NUM_IDS + 1];
    uint32_t k = 4;

    pos[1] = (uint32_t)target[0];
    pos[2] = (uint32_t)target[J_SHOULDER];
    pos[3] = (uint32_t)(4095 - target[J_SHOULDER] + off3);
    pos[4] = (uint32_t)target[2];
    pos[5] = (uint32_t)target[3];
    pos[6] = (uint32_t)target[4];
    pos[7] = (uint32_t)target[5];

    par[0] = A_GOAL_POSITION & 0xFFu; par[1] = (A_GOAL_POSITION >> 8) & 0xFFu;
    par[2] = 4;                       par[3] = 0;
    for (uint32_t id = 1; id <= NUM_IDS; id++) {
        uint32_t v = pos[id];
        par[k++] = id;
        par[k++] = v & 0xFFu;
        par[k++] = (v >> 8) & 0xFFu;
        par[k++] = (v >> 16) & 0xFFu;
        par[k++] = (v >> 24) & 0xFFu;
    }
    dxl_send(ID_BROADCAST, INST_SYNC_WRITE, par, k);
}

/* ------------------------------------------------------------------------ */
/*  Arm                                                                     */
/* ------------------------------------------------------------------------ */
static void ping_scan(void)
{
    ping_mask = 0;
    bus_err = 0;
    puts_("ping:");
    for (uint32_t id = 1; id <= NUM_IDS; id++) {
        uint32_t ok = dxl_ping(id);
        if (ok)
            ping_mask |= 1u << (id - 1);
        uart_tx_drain();
        puts_(" ");
        putdec(id);
        puts_(ok ? "=ok" : "=--");
    }
    puts_("\r\n");
    out_field(OUT_PING_MASK, ping_mask << OUT_PING_SHIFT);
}

static inline uint32_t has_id(uint32_t mask, uint32_t id) { return (mask >> (id - 1)) & 1u; }

/* Effective limits = software limits narrowed by each servo's EEPROM limits
 * (for the shoulder, ID 2's limits). Keeps the software limits if a read
 * fails. Only for IDs in `mask`. */
static void read_limits(uint32_t mask)
{
    for (uint32_t j = 0; j < NUM_JOINTS; j++) {
        uint32_t lo, hi;
        lim_min[j] = joint_min[j];
        lim_max[j] = joint_max[j];
        if (has_id(mask, joint_id[j]) &&
            dxl_read(joint_id[j], A_MIN_POS_LIMIT, 4, &lo) &&
            dxl_read(joint_id[j], A_MAX_POS_LIMIT, 4, &hi) && lo < hi) {
            if (lo > lim_min[j]) lim_min[j] = lo;
            if (hi < lim_max[j]) lim_max[j] = hi;
        }
    }
}

/* Reads Present Position of the IDs in `mask`; returns the IDs that answered. */
static uint32_t read_present(uint32_t mask)
{
    uint32_t ok = 0;
    for (uint32_t id = 1; id <= NUM_IDS; id++)
        if (has_id(mask, id) && dxl_read(id, A_PRESENT_POS, 4, &present[id]))
            ok |= 1u << (id - 1);
    return ok;
}

static void print_present(uint32_t mask)
{
    puts_("pos:");
    for (uint32_t id = 1; id <= NUM_IDS; id++) {
        puts_(" ");
        putdec(id);
        puts_("=");
        if (has_id(mask, id))
            putdec(present[id]);          /* 0..4095 in position mode */
        else
            puts_("--");
    }
    puts_("\r\n");
}

static int32_t clamp_joint(uint32_t j, int32_t v)
{
    if (v < (int32_t)lim_min[j]) return (int32_t)lim_min[j];
    if (v > (int32_t)lim_max[j]) return (int32_t)lim_max[j];
    return v;
}

/* One jog step. Stops at a limit; a joint that is already outside its limits
 * (e.g. resting pose when torque came on) may only move back towards them. */
static int32_t jog_joint(uint32_t j, int32_t cur, int32_t step)
{
    int32_t v = cur + step;
    if (step > 0 && v > (int32_t)lim_max[j])
        v = (cur > (int32_t)lim_max[j]) ? cur : (int32_t)lim_max[j];
    if (step < 0 && v < (int32_t)lim_min[j])
        v = (cur < (int32_t)lim_min[j]) ? cur : (int32_t)lim_min[j];
    return v;
}

static void torque_all(uint32_t on)
{
    for (uint32_t id = 1; id <= NUM_IDS; id++)
        if (has_id(avail, id))
            dxl_write(id, A_TORQUE_ENABLE, 1, on);
}

static void profile_all(uint32_t vel)
{
    for (uint32_t id = 1; id <= NUM_IDS; id++)
        if (has_id(avail, id)) {
            dxl_write(id, A_PROFILE_VEL, 4, vel);
            dxl_write(id, A_PROFILE_ACC, 4, PROFILE_ACC);
        }
}

/* Torque on without a jump: targets = present positions. Refuses (and keeps
 * torque off) if one of IDs 1..6 does not answer or the shoulder pair
 * disagrees. The gripper (ID 7) is optional. */
static void arm_enable(void)
{
    uint32_t mask;

    puts_("torque on: reading positions\r\n");
    mask = read_present(0x7Fu);
    print_present(mask);
    if ((mask & 0x3Fu) != 0x3Fu) {
        puts_("  REFUSED: IDs 1-6 must all answer\r\n");
        return;
    }
    if (!has_id(mask, 7))
        puts_("  gripper (ID 7) not answering: continuing without it\r\n");
    avail = mask;
    bus_err = 0;                          /* the missing-gripper read is expected */
    read_limits(avail);

    off3 = (int32_t)present[3] - (int32_t)(4095u - present[2]);
    if (off3 < -SHOULDER_MISMATCH || off3 > SHOULDER_MISMATCH) {
        puts_("  REFUSED: ID3 is not 4095 - ID2 (shoulder pair)\r\n");
        return;
    }

    for (uint32_t j = 0; j < NUM_JOINTS; j++)
        target[j] = has_id(avail, joint_id[j]) ? (int32_t)present[joint_id[j]] : 2048;

    profile_all(PROFILE_VEL);
    dxl_sync_goal();                      /* goal = present: no jump */
    torque_all(1);
    torque_on = 1;
    out_set(OUT_TORQUE, 1);
    puts_("  torque ON\r\n");
}

static void arm_disable(void)
{
    torque_all(0);
    torque_on = 0;
    out_set(OUT_TORQUE, 0);
    puts_("torque OFF\r\n");
}

/* ------------------------------------------------------------------------ */
/*  Poses: one joint at a time, each waits until its servo has stopped      */
/* ------------------------------------------------------------------------ */
static uint32_t pose_active, pose_i, pose_loops;
static const uint32_t *pose_tbl, *pose_ord;

static void pose_start_joint(void)
{
    uint32_t j = pose_ord[pose_i];
    target[j] = clamp_joint(j, (int32_t)pose_tbl[j]);
    pose_loops = 0;
    dxl_sync_goal();
}

static void pose_begin(const uint32_t *tbl, const uint32_t *ord, const char *name)
{
    puts_(name);
    puts_(" pose: moving one joint at a time\r\n");
    pose_tbl = tbl;
    pose_ord = ord;
    profile_all(POSE_VEL);
    pose_active = 1;
    pose_i = 0;
    pose_start_joint();
}

static void pose_end(const char *msg)
{
    pose_active = 0;
    profile_all(PROFILE_VEL);
    puts_(msg);
}

/* Called once per loop while a pose move runs. */
static void pose_poll(void)
{
    uint32_t j = pose_ord[pose_i], id = joint_id[j], moving = 1, pos;
    int32_t  d;

    if (dxl_read(id, A_MOVING, 1, &moving) && !moving &&
        dxl_read(id, A_PRESENT_POS, 4, &pos)) {
        d = (int32_t)pos - target[j];
        if (d >= -POSE_TOL && d <= POSE_TOL) {
            if (++pose_i >= POSE_STEPS) {
                pose_end("  pose reached\r\n");
                return;
            }
            pose_start_joint();
            return;
        }
    }
    if (++pose_loops >= POSE_LOOPS) {
        /* Not settled in 8 s (blocked?): hold where the joint is now. */
        if (dxl_read(id, A_PRESENT_POS, 4, &pos))
            target[j] = (int32_t)pos;
        dxl_sync_goal();
        pose_end("  C pose STOPPED: a joint did not settle, holding here\r\n");
    }
}

/* ------------------------------------------------------------------------ */
/*  PS/2 keyboard (USB HOST connector -> PIC24 -> PS2_CLK / PS2_DATA ->     */
/*  GPIO). Decoded here, by polling GPIO_IN.                                */
/*                                                                          */
/*  Frame: 11 bits, the keyboard drives the clock (10..16.7 kHz); data is   */
/*  valid at the falling clock edge: start (0), 8 data bits LSB first, odd  */
/*  parity, stop (1). While the firmware talks to the servos it holds the   */
/*  clock low (PS/2 "inhibit"): the keyboard keeps its keys and sends them  */
/*  when the clock is released. A frame cut by the inhibit is resent by the */
/*  keyboard.                                                               */
/* ------------------------------------------------------------------------ */
#define PS2_FRAME_TMO   (2u * CYC_PER_MS)      /* no edge for 2 ms: resync   */
#define PS2_INHIBIT_MIN (CYC_PER_MS / 10u)     /* hold the clock >= 100 us   */
#define KQ_SIZE         16u                    /* power of 2                 */

static uint32_t ps2_bits, ps2_n, ps2_clk_q, ps2_t_edge, ps2_t_inhibit;
static uint32_t kq[KQ_SIZE], kq_head, kq_tail;
static uint32_t ps2_lost;          /* a byte was lost (bad frame / queue full) */

static void ps2_reset_frame(void)
{
    ps2_bits = 0;
    ps2_n = 0;
}

/* Called as often as possible while the clock is released. */
static void ps2_poll(void)
{
    uint32_t v = rd32(GPIO_BASE + G_IN);
    uint32_t clk = (v & IN_PS2_CLK) ? 1u : 0u;

    if (ps2_clk_q && !clk) {                       /* falling edge */
        uint32_t bit = (v & IN_PS2_DATA) ? 1u : 0u;
        ps2_t_edge = now();
        if (ps2_n == 0 && bit) {
            /* not a start bit: ignore */
        } else {
            ps2_bits |= bit << ps2_n;
            if (++ps2_n == 11) {
                uint32_t ones = 0;
                for (uint32_t i = 1; i <= 9; i++)  /* data + parity */
                    ones += (ps2_bits >> i) & 1u;
                if ((ps2_bits & 1u) == 0 && (ps2_bits >> 10) == 1u && (ones & 1u)) {
                    uint32_t nxt = (kq_head + 1u) & (KQ_SIZE - 1u);
                    if (nxt != kq_tail) {
                        kq[kq_head] = (ps2_bits >> 1) & 0xFFu;
                        kq_head = nxt;
                    } else {
                        ps2_lost = 1;             /* queue full: byte dropped */
                    }
                } else {
                    ps2_lost = 1;                 /* start / parity / stop error */
                }
                ps2_reset_frame();
            }
        }
    } else if (ps2_n && now() - ps2_t_edge > PS2_FRAME_TMO) {
        ps2_reset_frame();                        /* lost a frame: resync */
    }
    ps2_clk_q = clk;
}

/* Before servo traffic: let a frame in progress finish, then hold the
 * clock low. */
static void ps2_inhibit(void)
{
    while (ps2_n && now() - ps2_t_edge <= PS2_FRAME_TMO)
        ps2_poll();
    out_set(OUT_PS2_CLK_LOW, 1);
    ps2_t_inhibit = now();
    ps2_reset_frame();
}

/* After servo traffic: release the clock (inhibit held >= 100 us). */
static void ps2_release(void)
{
    while (now() - ps2_t_inhibit < PS2_INHIBIT_MIN)
        ;
    out_set(OUT_PS2_CLK_LOW, 0);
    ps2_reset_frame();
    ps2_clk_q = (rd32(GPIO_BASE + G_IN) & IN_PS2_CLK) ? 1u : 0u;
}

static int32_t kq_pop(void)
{
    int32_t c;
    if (kq_tail == kq_head)
        return -1;
    c = (int32_t)kq[kq_tail];
    kq_tail = (kq_tail + 1u) & (KQ_SIZE - 1u);
    return c;
}

/* ------------------------------------------------------------------------ */
/*  Keys (PS/2 scan code set 2)                                             */
/* ------------------------------------------------------------------------ */
enum {
    K_NONE = 0, K_1, K_2, K_3, K_4, K_5, K_6,
    K_W, K_S, K_A, K_D, K_Z, K_X, K_C, K_R, K_P, K_T, K_O, K_Y, K_H,
    K_ESC, K_UP, K_DOWN
};

/* { make code, 1 if E0-prefixed, key } */
#define KMAP_N 22u
static const uint32_t kmap[KMAP_N][3] = {
    { 0x16, 0, K_1 }, { 0x1E, 0, K_2 }, { 0x26, 0, K_3 }, { 0x25, 0, K_4 },
    { 0x2E, 0, K_5 }, { 0x36, 0, K_6 }, { 0x1D, 0, K_W }, { 0x1B, 0, K_S },
    { 0x1C, 0, K_A }, { 0x23, 0, K_D }, { 0x1A, 0, K_Z }, { 0x22, 0, K_X },
    { 0x21, 0, K_C }, { 0x2D, 0, K_R }, { 0x4D, 0, K_P }, { 0x2C, 0, K_T },
    { 0x44, 0, K_O }, { 0x35, 0, K_Y }, { 0x33, 0, K_H }, { 0x76, 0, K_ESC },
    { 0x75, 1, K_UP }, { 0x72, 1, K_DOWN },
};

static const char *const joint_name[NUM_JOINTS] = {
    "waist", "shoulder", "elbow", "wrist angle", "wrist rotate", "gripper"
};

#define KSTEP_N  4u
static const int32_t  kb_steps[KSTEP_N] = { 5, 10, 20, 30 };   /* ticks per loop */
#define KSPEED_N 4u
static const uint32_t kb_speeds[KSPEED_N] = { 30, 60, 100, 200 }; /* profile vel */

static uint32_t key_held;          /* bit k: key k is down */
static uint32_t kb_e0, kb_f0;      /* scan code prefixes seen */
static uint32_t kb_joint;          /* 0..5 */
static uint32_t kb_step_i = 1, kb_speed_i = 2, kb_confirm_off;

/* Stuck-key guard. A lost release code would leave a move key "held" and the
 * joint moving. While a key is really held the keyboard repeats its make
 * code (typematic, ~0.25..1 s delay, then ~10..30 per second), so a move key
 * that has not been repeated for KB_HOLD_TMO_REPEAT is treated as released.
 * If this keyboard has never been seen repeating, one press moves for at
 * most KB_HOLD_TMO_MAX. */
#define KEYS_MOVE  ((1u << K_W) | (1u << K_S) | (1u << K_UP) | (1u << K_DOWN))
#define KB_HOLD_TMO_REPEAT (1200u * CYC_PER_MS)
#define KB_HOLD_TMO_MAX    (3000u * CYC_PER_MS)
static uint32_t kb_t_move;         /* last make code of a move key */
static uint32_t kb_repeat_seen;    /* this keyboard sends typematic repeats */

static void kb_release_all(void)
{
    key_held = 0;
    kb_e0 = 0;
    kb_f0 = 0;
    kb_confirm_off = 0;
}

static uint32_t kmap_find(uint32_t code, uint32_t e0)
{
    for (uint32_t i = 0; i < KMAP_N; i++)
        if (kmap[i][0] == code && kmap[i][1] == e0)
            return kmap[i][2];
    return K_NONE;
}

static void kb_help(void)
{
    puts_("keys: 1-6 joint  W/S or Up/Down move  A/D step  Z/X speed\r\n");
    puts_("      C C-pose  R rest  P positions  T torque on  O then Y torque off\r\n");
    puts_("      Esc stop a pose move  H help   (SW15 must be on for torque)\r\n");
}

/* One key pressed (not a repeat). in = GPIO inputs this loop. */
static void kb_action(uint32_t key, uint32_t in)
{
    uint32_t confirm = kb_confirm_off;
    kb_confirm_off = 0;

    if (key >= K_1 && key <= K_6) {
        kb_joint = key - K_1;
        puts_("kb joint: ");
        puts_(joint_name[kb_joint]);
        puts_("\r\n");
    } else if (key == K_A || key == K_D) {
        if (key == K_D && kb_step_i + 1u < KSTEP_N) kb_step_i++;
        if (key == K_A && kb_step_i > 0) kb_step_i--;
        puts_("kb step: ");
        putdec((uint32_t)kb_steps[kb_step_i]);
        puts_("\r\n");
    } else if (key == K_Z || key == K_X) {
        if (key == K_X && kb_speed_i + 1u < KSPEED_N) kb_speed_i++;
        if (key == K_Z && kb_speed_i > 0) kb_speed_i--;
        if (torque_on && !pose_active)
            profile_all(kb_speeds[kb_speed_i]);
        puts_("kb speed: ");
        putdec(kb_speeds[kb_speed_i]);
        puts_("\r\n");
    } else if (key == K_C || key == K_R) {
        if (!torque_on)
            puts_("torque is off\r\n");
        else if (!pose_active)
            pose_begin(key == K_C ? c_pose : rest_pose,
                       key == K_C ? c_order : rest_order,
                       key == K_C ? "C" : "rest");
    } else if (key == K_P) {
        print_present(read_present(torque_on ? avail : ping_mask));
    } else if (key == K_T) {
        if (!(in & IN_SW_TORQUE))
            puts_("SW15 is off: switch it on first\r\n");
        else if (!torque_on)
            arm_enable();
    } else if (key == K_O) {
        if (torque_on) {
            puts_("torque OFF drops the arm: press Y to confirm\r\n");
            kb_confirm_off = 1;
        }
    } else if (key == K_Y) {
        if (confirm && torque_on) {
            pose_active = 0;
            arm_disable();
        }
    } else if (key == K_ESC) {
        key_held = 0;                         /* Esc also releases every key */
        if (pose_active) {
            uint32_t j = pose_ord[pose_i], pos;
            if (dxl_read(joint_id[j], A_PRESENT_POS, 4, &pos))
                target[j] = (int32_t)pos;
            dxl_sync_goal();
            pose_end("  pose STOPPED (Esc), holding here\r\n");
        }
    } else if (key == K_H) {
        kb_help();
    }
}

/* Decodes the queued scan codes: updates held keys, runs key actions. */
static void kb_process(uint32_t in)
{
    int32_t c;

    if (ps2_lost) {                       /* maybe a lost release code: fail safe */
        ps2_lost = 0;
        if (key_held)
            puts_("keyboard: data lost - all keys released\r\n");
        kb_release_all();
    }
    while ((c = kq_pop()) >= 0) {
        uint32_t key;
        if (c == 0xE0) { kb_e0 = 1; continue; }
        if (c == 0xF0) { kb_f0 = 1; continue; }
        key = kmap_find((uint32_t)c, kb_e0);
        if (key != K_NONE) {
            if (kb_f0) {
                key_held &= ~(1u << key);
            } else {
                if (KEYS_MOVE & (1u << key)) {
                    if (key_held & (1u << key))
                        kb_repeat_seen = 1;   /* typematic repeat */
                    kb_t_move = now();
                }
                if (!(key_held & (1u << key))) {   /* new press, not a repeat */
                    key_held |= 1u << key;
                    kb_action(key, in);
                }
            }
        }
        kb_e0 = 0;
        kb_f0 = 0;
    }

    /* Stuck-key guard (see KB_HOLD_TMO_*). */
    if ((key_held & KEYS_MOVE) &&
        now() - kb_t_move > (kb_repeat_seen ? KB_HOLD_TMO_REPEAT : KB_HOLD_TMO_MAX)) {
        key_held &= ~KEYS_MOVE;
        puts_(kb_repeat_seen ? "keyboard: move key not repeating - released\r\n"
                             : "keyboard: move key held 3 s - released, press again\r\n");
    }
}

/* ------------------------------------------------------------------------ */
int main(void)
{
    uint32_t in, prev = 0, rise, sel, k;
    uint32_t heart = 0, t_next, torque_q = 0;
    int32_t  step;

    gpio_init();
    uart_init();
    timer_init();
    torque_on = 0;

    delay_ms(100);                        /* servos finish their own boot */
    puts_("\r\nRISCFORGE robotic arm demo - Dynamixel 1 Mbps, SoC 32 MHz\r\n");
    if (rd32(GPIO_BASE + G_IN) & IN_SW_RELAY) {
        rx_tmo = RX_TIMEOUT_RELAY_MS * CYC_PER_MS;
        puts_("link: laptop relay (SW13 on) - run dxl_relay.py on the laptop\r\n");
    } else {
        puts_("link: direct, Pmod JA (SW13 off)\r\n");
    }
    puts_("SW15 torque, SW0-5 joints, BTNU/BTND move, SW14 fast, BTNC C pose,\r\n");
    puts_("BTNR ping, BTNL positions. USB keyboard on the USB HOST port:\r\n");
    kb_help();
    ping_scan();

    if (rd32(GPIO_BASE + G_IN) & IN_SW_TORQUE)
        puts_("SW15 is on: switch it off and on again (or press T) to enable torque\r\n");

    ps2_release();
    t_next = now();
    for (;;) {
        /* Listen phase: keyboard clock released, decode PS/2 until the
         * period ends. t_next = start of this period; resync after a long
         * command. */
        while (now() - t_next < LOOP_MS * CYC_PER_MS)
            ps2_poll();
        t_next += LOOP_MS * CYC_PER_MS;
        if (now() - t_next >= LOOP_MS * CYC_PER_MS)
            t_next = now();

        /* Work phase: keyboard held off while the servos are talked to. */
        ps2_inhibit();

        in   = rd32(GPIO_BASE + G_IN) & IN_ALL;
        rise = in & ~prev;
        prev = in;
        out_set(OUT_CMD, 0);
        out_set(OUT_FAST, in & IN_SW_FAST);

        if (++heart >= 25) {
            heart = 0;
            out_set(OUT_HEART, !(gout & OUT_HEART));
        }

        /* SW15: torque (SW15 off always wins) */
        if ((in & IN_SW_TORQUE) && !torque_on && (rise & IN_SW_TORQUE))
            arm_enable();
        else if (!(in & IN_SW_TORQUE) && torque_on) {
            pose_active = 0;
            arm_disable();
        }

        kb_process(in);

        /* Torque switched on or off (SW15, T, O+Y): forget held keys, so a
         * key held across the change cannot move the arm on its own. */
        if (torque_on != torque_q) {
            kb_release_all();
            torque_q = torque_on;
        }

        if (rise & IN_BTNR)
            ping_scan();
        if (rise & IN_BTNL) {
            uint32_t m = read_present(torque_on ? avail : ping_mask);
            print_present(m);
        }

        if (torque_on && pose_active) {
            pose_poll();
            out_set(OUT_CMD, 1);
        } else if (torque_on) {
            uint32_t changed = 0;

            if (rise & IN_BTNC) {
                pose_begin(c_pose, c_order, "C");
                out_set(OUT_CMD, 1);
            } else {
                /* buttons: the switch-selected joints */
                step = (in & IN_SW_FAST) ? STEP_FAST : STEP_SLOW;
                if ((in & IN_BTNU) && !(in & IN_BTND)) {
                    /* up */
                } else if ((in & IN_BTND) && !(in & IN_BTNU)) {
                    step = -step;
                } else {
                    step = 0;
                }
                sel = in & IN_SEL_MASK;
                if (step != 0 && sel != 0) {
                    for (k = 0; k < NUM_JOINTS; k++) {
                        if ((sel & (1u << k)) && has_id(avail, joint_id[k])) {
                            int32_t v = jog_joint(k, target[k], step);
                            if (v != target[k]) {
                                target[k] = v;
                                changed = 1;
                            }
                        }
                    }
                }

                /* keyboard: the kb-selected joint, while W/S/Up/Down is held */
                {
                    uint32_t up = key_held & ((1u << K_W) | (1u << K_UP));
                    uint32_t dn = key_held & ((1u << K_S) | (1u << K_DOWN));
                    int32_t  ks = 0;
                    if (up && !dn) ks = kb_steps[kb_step_i];
                    if (dn && !up) ks = -kb_steps[kb_step_i];
                    if (ks != 0 && has_id(avail, joint_id[kb_joint])) {
                        int32_t v = jog_joint(kb_joint, target[kb_joint], ks);
                        if (v != target[kb_joint]) {
                            target[kb_joint] = v;
                            changed = 1;
                        }
                    }
                }
            }
            if (changed) {
                dxl_sync_goal();
                out_set(OUT_CMD, 1);
            }
        }

        out_set(OUT_ERR, bus_err);
        ps2_release();
    }
    return 0;
}
