/* =============================================================================
 * RISCFORGE 1TOPS — APB SPI Master Driver (spi_driver.h)
 * Direct Register Model for ETH Zurich APB SPI Master
 * ============================================================================= */

#ifndef RISCFORGE_SPI_DRIVER_H_
#define RISCFORGE_SPI_DRIVER_H_

#include <stdint.h>
#include "soc_regs.h"

/* Register Offsets (Direct Hardware Model) */
#define SPI_STATUS_OFFSET 0x00  /* Read: Status/FIFO counts; Write: Command/CS/SWRST */
#define SPI_CLKDIV_OFFSET 0x04  /* Clock Divisor */
#define SPI_SPICMD_OFFSET 0x08  /* SPI Command Word */
#define SPI_SPIADR_OFFSET 0x0C  /* SPI Address Word */
#define SPI_SPILEN_OFFSET 0x10  /* Command/Address/Data Lengths */
#define SPI_SPIDUM_OFFSET 0x14  /* Dummy Cycles (RD / WR) */
#define SPI_TXFIFO_OFFSET 0x18  /* TX FIFO Data */
#define SPI_RXFIFO_OFFSET 0x20  /* RX FIFO Data */
#define SPI_INTCFG_OFFSET 0x24  /* Interrupt Configuration */
#define SPI_INTSTA_OFFSET 0x28  /* Interrupt Status (Read to clear) */

/* STATUS Command Bits (for writes) */
#define SPI_CMD_RD        (1 << 0)
#define SPI_CMD_WR        (1 << 1)
#define SPI_CMD_QRD       (1 << 2)
#define SPI_CMD_QWR       (1 << 3)
#define SPI_CMD_SWRST     (1 << 4)
#define SPI_STATUS_CS0    (1 << 8)
#define SPI_STATUS_CS1    (1 << 9)
#define SPI_STATUS_CS2    (1 << 10)
#define SPI_STATUS_CS3    (1 << 11)

/* Standard API */
void     spi_init(uint16_t clk_div);
void     spi_select_cs(int cs_num);
void     spi_deselect_cs(void);
int      spi_transfer_command(uint32_t cmd, uint32_t cmd_len_bits, uint32_t addr, uint32_t addr_len_bits, uint32_t dummy_bits, uint32_t data_len_bits, int is_read);
void     spi_write_tx_fifo(uint32_t data);
uint32_t spi_read_rx_fifo(void);

/* Error & Illegal State Recovery */
void     spi_recover(uint16_t clk_div);

#endif /* RISCFORGE_SPI_DRIVER_H_ */
