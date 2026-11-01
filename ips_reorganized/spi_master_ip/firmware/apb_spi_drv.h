/* =============================================================================
 * RISCFORGE APB SPI Master Driver & Register Definitions
 * Base Address: SPI_BASE = 0x40004000
 * Verified directly against RTL: spi_master_ip/spi_master/spi_master_apb_if.sv
 * ============================================================================= */

#ifndef APB_SPI_DRV_H
#define APB_SPI_DRV_H

#include <stdint.h>

#define SPI_REG32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))

#define SPI_REG_STATUS(base)  SPI_REG32((base) + 0x00) /* Status: [0]=BUSY, [1]=RX_EMPTY, [2]=TX_FULL */
#define SPI_REG_CLKDIV(base)  SPI_REG32((base) + 0x04) /* Clock Divider */
#define SPI_REG_SPICMD(base)  SPI_REG32((base) + 0x08) /* Command Register */
#define SPI_REG_SPIADR(base)  SPI_REG32((base) + 0x0C) /* Address Register */
#define SPI_REG_SPILEN(base)  SPI_REG32((base) + 0x10) /* Transfer Lengths */
#define SPI_REG_SPIDUM(base)  SPI_REG32((base) + 0x14) /* Dummy Cycles */
#define SPI_REG_TXFIFO(base)  SPI_REG32((base) + 0x18) /* TX FIFO Data */
#define SPI_REG_RXFIFO(base)  SPI_REG32((base) + 0x20) /* RX FIFO Data */
#define SPI_REG_INTCFG(base)  SPI_REG32((base) + 0x24) /* Interrupt Configuration */
#define SPI_REG_INTSTA(base)  SPI_REG32((base) + 0x28) /* Interrupt Status */

#define SPI_STATUS_BUSY       (1U << 0)
#define SPI_STATUS_RX_EMPTY   (1U << 1)
#define SPI_STATUS_TX_FULL    (1U << 2)

static inline void spi_init(uintptr_t base, uint32_t clk_div) {
    SPI_REG_CLKDIV(base) = clk_div;
}

static inline void spi_write_fifo(uintptr_t base, uint32_t data) {
    while (SPI_REG_STATUS(base) & SPI_STATUS_TX_FULL);
    SPI_REG_TXFIFO(base) = data;
}

static inline uint32_t spi_read_fifo(uintptr_t base) {
    while (SPI_REG_STATUS(base) & SPI_STATUS_RX_EMPTY);
    return SPI_REG_RXFIFO(base);
}

static inline void spi_wait_idle(uintptr_t base) {
    while (SPI_REG_STATUS(base) & SPI_STATUS_BUSY);
}

#endif /* APB_SPI_DRV_H */
