/* =============================================================================
 * APB SPI Master Verification Example (Flash JEDEC ID Read)
 * ============================================================================= */

#include "apb_spi_drv.h"

#define SOC_SPI_BASE 0x40004000UL

uint32_t test_spi_read_jedec_id(void) {
    uint32_t id = 0;
    
    /* Set clock divider */
    spi_init(SOC_SPI_BASE, 4);
    
    /* Assert CS0 */
    spi_cs_assert(SOC_SPI_BASE, 0x01);
    
    /* Send Read JEDEC ID opcode: 0x9F */
    spi_write_byte(SOC_SPI_BASE, 0x9F);
    
    /* Clock out 3 dummy bytes to receive Manufacturer, Memory Type, Capacity */
    spi_write_byte(SOC_SPI_BASE, 0x00);
    spi_write_byte(SOC_SPI_BASE, 0x00);
    spi_write_byte(SOC_SPI_BASE, 0x00);
    
    spi_wait_idle(SOC_SPI_BASE);
    
    /* Read response */
    (void)spi_read_byte(SOC_SPI_BASE); /* discard 0x9F echo */
    id |= ((uint32_t)spi_read_byte(SOC_SPI_BASE) << 16);
    id |= ((uint32_t)spi_read_byte(SOC_SPI_BASE) << 8);
    id |= ((uint32_t)spi_read_byte(SOC_SPI_BASE) << 0);
    
    /* Deassert CS */
    spi_cs_deassert(SOC_SPI_BASE);
    
    return id;
}
