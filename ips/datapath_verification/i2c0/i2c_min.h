#ifndef I2C_MIN_H
#define I2C_MIN_H

#include <stdint.h>

// =============================================================================
// UART0 Register Definitions (0x4000_2000)
// =============================================================================
#define UART_BASE         0x40002000UL

#define UART_RBR          (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_THR          (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_DLL          (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_IER          (*(volatile uint32_t *)(UART_BASE + 0x04))
#define UART_DLM          (*(volatile uint32_t *)(UART_BASE + 0x04))
#define UART_IIR          (*(volatile uint32_t *)(UART_BASE + 0x08))
#define UART_FCR          (*(volatile uint32_t *)(UART_BASE + 0x08))
#define UART_LCR          (*(volatile uint32_t *)(UART_BASE + 0x0C))
#define UART_MCR          (*(volatile uint32_t *)(UART_BASE + 0x10))
#define UART_LSR          (*(volatile uint32_t *)(UART_BASE + 0x14))

#define UART_LSR_DR       (1 << 0)
#define UART_LSR_THRE     (1 << 5)
#define UART_LSR_TEMT     (1 << 6)
#define UART_LCR_8BIT     (3 << 0)
#define UART_LCR_DLAB     (1 << 7)

static inline void uart_init(void) {
    UART_LCR = UART_LCR_DLAB | UART_LCR_8BIT;
    UART_DLL = 0x02;  // Divisor 2 (32 clocks/bit @ 100 MHz)
    UART_DLM = 0x00;
    UART_LCR = UART_LCR_8BIT;
    UART_IER = 0x00;
    UART_FCR = 0x07;
}

static inline void uart_putc(char c) {
    while (!(UART_LSR & UART_LSR_THRE));
    UART_THR = (uint32_t)(uint8_t)c;
}

static inline void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') {
            uart_putc('\r');
        }
        uart_putc(*s++);
    }
}

static inline void uart_puthex(uint32_t val) {
    uart_putc('0');
    uart_putc('x');
    for (int i = 7; i >= 0; i--) {
        uint8_t nibble = (val >> (i * 4)) & 0xF;
        char c = (nibble < 10) ? ('0' + nibble) : ('A' + (nibble - 10));
        uart_putc(c);
    }
}

// =============================================================================
// I2C Master Register Definitions (0x4000_0000)
// =============================================================================
#define I2C_BASE          0x40000000UL

#define I2C_PRE           (*(volatile uint32_t *)(I2C_BASE + 0x00))
#define I2C_CTRL          (*(volatile uint32_t *)(I2C_BASE + 0x04))
#define I2C_RX            (*(volatile uint32_t *)(I2C_BASE + 0x08))
#define I2C_STATUS        (*(volatile uint32_t *)(I2C_BASE + 0x0C))
#define I2C_TX            (*(volatile uint32_t *)(I2C_BASE + 0x10))
#define I2C_CMD           (*(volatile uint32_t *)(I2C_BASE + 0x14))

// Control Register Bits
#define I2C_CTRL_EN       (1 << 7)  // Core enable
#define I2C_CTRL_IEN      (1 << 6)  // Interrupt enable

// Status Register Bits
#define I2C_STATUS_RXACK  (1 << 7)  // 0 = ACK received from slave, 1 = NACK
#define I2C_STATUS_BUSY   (1 << 6)  // Bus busy
#define I2C_STATUS_AL     (1 << 5)  // Arbitration lost
#define I2C_STATUS_TIP    (1 << 1)  // Transfer in progress
#define I2C_STATUS_IF     (1 << 0)  // Interrupt flag

// Command Register Bits & Encodings
#define I2C_CMD_STA       (1 << 7)  // Generate START
#define I2C_CMD_STO       (1 << 6)  // Generate STOP
#define I2C_CMD_RD        (1 << 5)  // Read from slave
#define I2C_CMD_WR        (1 << 4)  // Write to slave
#define I2C_CMD_ACK       (1 << 3)  // ACK value (0=ACK, 1=NACK)
#define I2C_CMD_IACK      (1 << 0)  // Clear interrupt flag

#define CMD_START_WRITE   (I2C_CMD_STA | I2C_CMD_WR)
#define CMD_WRITE         (I2C_CMD_WR)
#define CMD_WRITE_STOP    (I2C_CMD_STO | I2C_CMD_WR)
#define CMD_READ_ACK      (I2C_CMD_RD)
#define CMD_READ_NACK_STOP (I2C_CMD_STO | I2C_CMD_RD | I2C_CMD_ACK)

// AT24C02 EEPROM Slave Address (7-bit address 0x50)
#define EEPROM_I2C_ADDR   0x50

// Wait for active I2C transfer to complete
static inline void i2c_wait_tip(void) {
    while (I2C_STATUS & I2C_STATUS_TIP);
}

// Initialize I2C Master with prescaler value
static inline void i2c_init(uint16_t prescaler) {
    I2C_CTRL = 0;              // Disable core first
    I2C_PRE  = (uint32_t)prescaler;
    I2C_CTRL = I2C_CTRL_EN;    // Enable core
}

// Write a single byte to AT24C02 EEPROM
// Returns 0 on success, non-zero if NACK
static inline int i2c_eeprom_write_byte(uint8_t dev_addr, uint8_t mem_addr, uint8_t data) {
    // 1. Send START + Device Address (Write Mode: R/W# = 0)
    I2C_TX  = (uint32_t)((dev_addr << 1) | 0);
    I2C_CMD = CMD_START_WRITE;
    i2c_wait_tip();
    if (I2C_STATUS & I2C_STATUS_RXACK) {
        I2C_CMD = I2C_CMD_STO;
        i2c_wait_tip();
        return 1; // NACK on device address
    }

    // 2. Send EEPROM Word/Memory Address
    I2C_TX  = (uint32_t)mem_addr;
    I2C_CMD = CMD_WRITE;
    i2c_wait_tip();
    if (I2C_STATUS & I2C_STATUS_RXACK) {
        I2C_CMD = I2C_CMD_STO;
        i2c_wait_tip();
        return 2; // NACK on memory address
    }

    // 3. Send Data Byte + STOP condition
    I2C_TX  = (uint32_t)data;
    I2C_CMD = CMD_WRITE_STOP;
    i2c_wait_tip();
    if (I2C_STATUS & I2C_STATUS_RXACK) {
        return 3; // NACK on data byte
    }

    return 0; // Success
}

// Read a single byte from AT24C02 EEPROM using Random Read (Combined format)
// Returns 0 on success, non-zero if NACK
static inline int i2c_eeprom_read_byte(uint8_t dev_addr, uint8_t mem_addr, uint8_t *data_out) {
    // 1. Dummy write to set EEPROM memory address pointer
    I2C_TX  = (uint32_t)((dev_addr << 1) | 0);
    I2C_CMD = CMD_START_WRITE;
    i2c_wait_tip();
    if (I2C_STATUS & I2C_STATUS_RXACK) {
        I2C_CMD = I2C_CMD_STO;
        i2c_wait_tip();
        return 1;
    }

    I2C_TX  = (uint32_t)mem_addr;
    I2C_CMD = CMD_WRITE;
    i2c_wait_tip();
    if (I2C_STATUS & I2C_STATUS_RXACK) {
        I2C_CMD = I2C_CMD_STO;
        i2c_wait_tip();
        return 2;
    }

    // 2. Repeated START + Device Address (Read Mode: R/W# = 1)
    I2C_TX  = (uint32_t)((dev_addr << 1) | 1);
    I2C_CMD = CMD_START_WRITE;
    i2c_wait_tip();
    if (I2C_STATUS & I2C_STATUS_RXACK) {
        I2C_CMD = I2C_CMD_STO;
        i2c_wait_tip();
        return 3;
    }

    // 3. Read Data Byte with NACK (Master NACK) + STOP condition
    I2C_CMD = CMD_READ_NACK_STOP;
    i2c_wait_tip();

    *data_out = (uint8_t)(I2C_RX & 0xFF);
    return 0; // Success
}

#endif /* I2C_MIN_H */
