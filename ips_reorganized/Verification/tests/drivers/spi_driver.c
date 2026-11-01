/* =============================================================================
 * RISCFORGE 1TOPS — APB SPI Master Driver (spi_driver.c)
 * Direct Register Model for ETH Zurich APB SPI Master
 * ============================================================================= */

#include "spi_driver.h"

#define SPI_DEFAULT_TIMEOUT_CYCLES 500000UL

void spi_init(uint16_t clk_div) {
    REG32_WRITE(APB_SPI_BASE + SPI_CLKDIV_OFFSET, clk_div);
}

void spi_select_cs(int cs_num) {
    uint32_t val = (cs_num == 0) ? SPI_STATUS_CS0 :
                   (cs_num == 1) ? SPI_STATUS_CS1 :
                   (cs_num == 2) ? SPI_STATUS_CS2 : SPI_STATUS_CS3;
    REG32_WRITE(APB_SPI_BASE + SPI_STATUS_OFFSET, val);
}

void spi_deselect_cs(void) {
    REG32_WRITE(APB_SPI_BASE + SPI_STATUS_OFFSET, 0);
}

int spi_transfer_command(uint32_t cmd, uint32_t cmd_len_bits, uint32_t addr, uint32_t addr_len_bits, uint32_t dummy_bits, uint32_t data_len_bits, int is_read) {
    REG32_WRITE(APB_SPI_BASE + SPI_SPICMD_OFFSET, cmd);
    REG32_WRITE(APB_SPI_BASE + SPI_SPIADR_OFFSET, addr);
    REG32_WRITE(APB_SPI_BASE + SPI_SPIDUM_OFFSET, dummy_bits);
    
    uint32_t len = (cmd_len_bits & 0x3F) |
                   ((addr_len_bits & 0x3F) << 8) |
                   ((data_len_bits & 0xFFFF) << 16);
    REG32_WRITE(APB_SPI_BASE + SPI_SPILEN_OFFSET, len);
    
    /* Trigger transfer (RD or WR bit in STATUS) */
    uint32_t trigger = is_read ? SPI_CMD_RD : SPI_CMD_WR;
    REG32_WRITE(APB_SPI_BASE + SPI_STATUS_OFFSET, trigger);
    
    /* Wait for transfer completion with bounded cycle timeout */
    uint32_t start_cycle = csr_read_mcycle();
    while (REG32_READ(APB_SPI_BASE + SPI_STATUS_OFFSET) & 0x1) {
        if ((csr_read_mcycle() - start_cycle) > SPI_DEFAULT_TIMEOUT_CYCLES) {
            return -1; /* Timeout */
        }
    }
    return 0;
}

void spi_write_tx_fifo(uint32_t data) {
    REG32_WRITE(APB_SPI_BASE + SPI_TXFIFO_OFFSET, data);
}

uint32_t spi_read_rx_fifo(void) {
    return REG32_READ(APB_SPI_BASE + SPI_RXFIFO_OFFSET);
}

/* Recover from stuck transfer / FIFO overflow / slave hang */
void spi_recover(uint16_t clk_div) {
    /* 1. Deselect all chip selects */
    REG32_WRITE(APB_SPI_BASE + SPI_STATUS_OFFSET, 0);
    
    /* 2. Issue Software Reset via STATUS[4] */
    REG32_WRITE(APB_SPI_BASE + SPI_STATUS_OFFSET, SPI_CMD_SWRST);
    
    /* 3. Re-apply clock divisor */
    REG32_WRITE(APB_SPI_BASE + SPI_CLKDIV_OFFSET, clk_div);
    
    /* 4. Clear interrupt status by reading INTSTA */
    volatile uint32_t dummy_sta = REG32_READ(APB_SPI_BASE + SPI_INTSTA_OFFSET);
    (void)dummy_sta;
}
