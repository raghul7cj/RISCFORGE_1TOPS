`ifndef SPI_REG_DEFINES_SVH
`define SPI_REG_DEFINES_SVH
//------------------------------------------------------------------------------
// Register byte offsets (word aligned, PADDR[5:2] selects the register)
// Mirrors spi_master_apb_if.sv `REG_* defines in the DUT.
//------------------------------------------------------------------------------
`define SPI_REG_STATUS 12'h00
`define SPI_REG_CLKDIV 12'h04
`define SPI_REG_SPICMD 12'h08
`define SPI_REG_SPIADR 12'h0C
`define SPI_REG_SPILEN 12'h10
`define SPI_REG_SPIDUM 12'h14
`define SPI_REG_TXFIFO 12'h18
`define SPI_REG_RXFIFO 12'h20
`define SPI_REG_INTCFG 12'h24
`define SPI_REG_INTSTA 12'h28

// STATUS register write-side bit map
`define STATUS_BIT_RD    0
`define STATUS_BIT_WR    1
`define STATUS_BIT_QRD   2
`define STATUS_BIT_QWR   3
`define STATUS_BIT_SWRST 4
// spi_csreg occupies [11:8]

// spi_mode encoding (from spi_master_controller.sv)
`define SPI_MODE_STD     2'b00
`define SPI_MODE_QUAD_TX 2'b01
`define SPI_MODE_QUAD_RX 2'b10

`endif // SPI_REG_DEFINES_SVH
