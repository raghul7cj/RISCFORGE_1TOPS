//------------------------------------------------------------------------------
// spi_if : pin level interface matching apb_spi_master's spi_* port group.
//
// spi_sdo[3:0] are driven by the DUT (master output pins). spi_sdi[3:0] are
// driven by the VIP acting as one or more SPI slave devices. spi_csn[3:0]
// are active-low chip selects, one per potential slave.
//------------------------------------------------------------------------------
interface spi_if;

    logic       spi_clk;
    logic [3:0] spi_csn;   // spi_csn[0]=csn0 ... spi_csn[3]=csn3
    logic [1:0] spi_mode;  // 00=STD, 01=QUAD_TX(master drives), 10=QUAD_RX(master samples)
    logic [3:0] spi_sdo;   // driven by DUT
    logic [3:0] spi_sdi;   // driven by VIP (slave response)

    // Convenience aliases matching the DUT port names, useful in the hookup.
    // (kept as functions instead of extra signals to avoid duplicated drivers)

    modport dut (
        output spi_clk, spi_csn, spi_mode, spi_sdo,
        input  spi_sdi
    );

    modport slave_drv (
        input  spi_clk, spi_csn, spi_mode, spi_sdo,
        output spi_sdi
    );

    modport monitor (
        input spi_clk, spi_csn, spi_mode, spi_sdo, spi_sdi
    );

endinterface : spi_if
