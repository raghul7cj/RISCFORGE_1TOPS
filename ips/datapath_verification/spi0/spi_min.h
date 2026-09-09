#ifndef SPI_MIN_H
#define SPI_MIN_H

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
    UART_DLL = 0x02;  // Divisor 2 (32 clocks/bit)
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
        if (*s == '\n') uart_putc('\r');
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
// SPI Master Register Definitions (0x4000_4000)
// =============================================================================
#define SPI_BASE          0x40004000UL

#define SPI_STATUS        (*(volatile uint32_t *)(SPI_BASE + 0x00))
#define SPI_CLKDIV        (*(volatile uint32_t *)(SPI_BASE + 0x04))
#define SPI_SPICMD        (*(volatile uint32_t *)(SPI_BASE + 0x08))
#define SPI_SPIADR        (*(volatile uint32_t *)(SPI_BASE + 0x0C))
#define SPI_SPILEN        (*(volatile uint32_t *)(SPI_BASE + 0x10))
#define SPI_SPIDUM        (*(volatile uint32_t *)(SPI_BASE + 0x14))
#define SPI_TXFIFO        (*(volatile uint32_t *)(SPI_BASE + 0x18))
#define SPI_RXFIFO        (*(volatile uint32_t *)(SPI_BASE + 0x20))
#define SPI_INTCFG        (*(volatile uint32_t *)(SPI_BASE + 0x24))
#define SPI_INTSTA        (*(volatile uint32_t *)(SPI_BASE + 0x28))

// Status write flags
#define SPI_CMD_RD        (1 << 0)
#define SPI_CMD_WR        (1 << 1)
#define SPI_CMD_QRD       (1 << 2)
#define SPI_CMD_QWR       (1 << 3)
#define SPI_CMD_SWRST     (1 << 4)
#define SPI_CS_0          (1 << 8)
#define SPI_CS_1          (1 << 9)
#define SPI_CS_2          (1 << 10)
#define SPI_CS_3          (1 << 11)

// Status read bits
#define SPI_STATUS_IDLE   (1 << 0)

// SPI Flash standard command opcodes
#define CMD_READ_ID       0x9F
#define CMD_WRITE_ENABLE  0x06
#define CMD_WRITE_DISABLE 0x04
#define CMD_READ_STATUS   0x05
#define CMD_READ_DATA     0x03
#define CMD_FAST_READ     0x0B
#define CMD_PAGE_PROGRAM  0x02
#define CMD_SECTOR_ERASE  0x20
#define CMD_CHIP_ERASE    0xC7

// Helper to wait until SPI Master FSM returns to IDLE
static inline void spi_wait_idle(void) {
    while (!(SPI_STATUS & SPI_STATUS_IDLE));
}

// Initialize SPI Master
static inline void spi_init(uint8_t clk_div) {
    SPI_CLKDIV = (uint32_t)clk_div;
    SPI_STATUS = SPI_CMD_SWRST;  // clear FIFOs and reset FSM
    spi_wait_idle();
}

// -----------------------------------------------------------------------------
// Flash Command Implementations
// -----------------------------------------------------------------------------

// Read 24-bit JEDEC ID (Opcode 0x9F) -> Returns 24-bit ID
static inline uint32_t spi_flash_read_id(void) {
    spi_wait_idle();
    
    // Command = 0x9F (8 bits, left aligned)
    SPI_SPICMD = ((uint32_t)CMD_READ_ID) << 24;
    SPI_SPIADR = 0;
    // SPILEN: cmd_len=8, addr_len=0, data_len=24 (3 bytes)
    SPI_SPILEN = (24 << 16) | (0 << 8) | (8);
    SPI_SPIDUM = 0;
    
    // Start Read with CSN0 asserted
    SPI_STATUS = SPI_CS_0 | SPI_CMD_RD;
    
    // Read RX FIFO (hardware stalls until word is ready)
    uint32_t id = SPI_RXFIFO;
    spi_wait_idle();
    return id;
}

// Send Write Enable command (0x06)
static inline void spi_flash_write_enable(void) {
    spi_wait_idle();
    SPI_SPICMD = ((uint32_t)CMD_WRITE_ENABLE) << 24;
    SPI_SPIADR = 0;
    // SPILEN: cmd_len=8, addr_len=0, data_len=0
    SPI_SPILEN = (0 << 16) | (0 << 8) | (8);
    SPI_SPIDUM = 0;
    
    // Start Write with CSN0
    SPI_STATUS = SPI_CS_0 | SPI_CMD_WR;
    spi_wait_idle();
}

// Read Flash Status Register 1 (0x05) -> Returns status byte
static inline uint8_t spi_flash_read_status(void) {
    spi_wait_idle();
    SPI_SPICMD = ((uint32_t)CMD_READ_STATUS) << 24;
    SPI_SPIADR = 0;
    // SPILEN: cmd_len=8, addr_len=0, data_len=8 (1 byte)
    SPI_SPILEN = (8 << 16) | (0 << 8) | (8);
    SPI_SPIDUM = 0;
    
    SPI_STATUS = SPI_CS_0 | SPI_CMD_RD;
    uint32_t status = SPI_RXFIFO;
    spi_wait_idle();
    return (uint8_t)(status & 0xFF);
}

// Page Program (0x02) - Write 32-bit word to 24-bit address
static inline void spi_flash_page_program(uint32_t addr, uint32_t data) {
    spi_wait_idle();
    // Enable writes first
    spi_flash_write_enable();
    
    spi_wait_idle();
    SPI_SPICMD = ((uint32_t)CMD_PAGE_PROGRAM) << 24;
    // 24-bit address left aligned into 32-bit register
    SPI_SPIADR = (addr & 0x00FFFFFF) << 8;
    // SPILEN: cmd_len=8, addr_len=24, data_len=32
    SPI_SPILEN = (32 << 16) | (24 << 8) | (8);
    SPI_SPIDUM = 0;
    
    // Push data into TX FIFO
    SPI_TXFIFO = data;
    
    // Start Write with CSN0
    SPI_STATUS = SPI_CS_0 | SPI_CMD_WR;
    spi_wait_idle();
}

// Read Data (0x03) - Read 32-bit word from 24-bit address
static inline uint32_t spi_flash_read_data(uint32_t addr) {
    spi_wait_idle();
    SPI_SPICMD = ((uint32_t)CMD_READ_DATA) << 24;
    SPI_SPIADR = (addr & 0x00FFFFFF) << 8;
    // SPILEN: cmd_len=8, addr_len=24, data_len=32
    SPI_SPILEN = (32 << 16) | (24 << 8) | (8);
    SPI_SPIDUM = 0;
    
    // Start Read with CSN0
    SPI_STATUS = SPI_CS_0 | SPI_CMD_RD;
    
    uint32_t rdata = SPI_RXFIFO;
    spi_wait_idle();
    return rdata;
}

// Fast Read (0x0B) - Read 32-bit word with dummy cycles
static inline uint32_t spi_flash_fast_read(uint32_t addr, uint8_t dummy_cycles) {
    spi_wait_idle();
    SPI_SPICMD = ((uint32_t)CMD_FAST_READ) << 24;
    SPI_SPIADR = (addr & 0x00FFFFFF) << 8;
    // SPILEN: cmd_len=8, addr_len=24, data_len=32
    SPI_SPILEN = (32 << 16) | (24 << 8) | (8);
    // SPIDUM: dummy_rd = dummy_cycles
    SPI_SPIDUM = (uint32_t)dummy_cycles;
    
    // Start Read with CSN0
    SPI_STATUS = SPI_CS_0 | SPI_CMD_RD;
    
    uint32_t rdata = SPI_RXFIFO;
    spi_wait_idle();
    return rdata;
}

#endif /* SPI_MIN_H */

