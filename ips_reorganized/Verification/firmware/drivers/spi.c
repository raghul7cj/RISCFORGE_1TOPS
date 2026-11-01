/* =============================================================================
 * RISCFORGE 1TOPS — SPI Master Driver Implementation (spi.c)
 * ============================================================================= */

#include "spi.h"

void spi_init(uint32_t clk_div) {
    SPI_REG_CLKDIV = clk_div;
}

uint32_t spi_transfer(uint32_t data) {
    SPI_REG_TXFIFO = data;
    while (SPI_REG_STATUS & 0x1); /* Wait while busy */
    return SPI_REG_RXFIFO;
}
