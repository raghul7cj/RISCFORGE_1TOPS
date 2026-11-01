/* =============================================================================
 * RISCFORGE 1TOPS — SPI Master Driver Header (spi.h)
 * ============================================================================= */

#ifndef RISCFORGE_SPI_H
#define RISCFORGE_SPI_H

#include <stdint.h>
#include "../bsp/soc_regs.h"

void     spi_init(uint32_t clk_div);
uint32_t spi_transfer(uint32_t data);

#endif /* RISCFORGE_SPI_H */
