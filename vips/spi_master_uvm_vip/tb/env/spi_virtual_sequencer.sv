//------------------------------------------------------------------------------
// spi_virtual_sequencer : gives virtual sequences a single handle from which
// to reach both the APB register sequencer and the SPI reactive-slave
// sequencer, so a single sequence can e.g. program registers on the APB
// side while simultaneously arming the SPI slave response on the other.
//------------------------------------------------------------------------------
class spi_virtual_sequencer extends uvm_sequencer;
    `uvm_component_utils(spi_virtual_sequencer)

    apb_sequencer   apb_sqr;
    spi_sequencer   spi_sqr;

    // Handle to the APB-side virtual interface so virtual sequences can
    // poll sideband status (e.g. events_o[1] end-of-transaction pulse)
    // without needing a dedicated TLM path just for that.
    virtual apb_if vif;

    // Mirrors spi_env_config.buffer_depth so virtual sequences can decode
    // the STATUS register's elements_tx/elements_rx fields, which are
    // BUFFER_DEPTH-parameter-dependent (LOG_BUFFER_DEPTH = $clog2(depth)).
    // Handle to the SPI-side virtual interface, mainly for diagnostics
    // (e.g. dumping spi_csn/spi_mode when a wait_eot() times out).
    virtual spi_if spi_vif;

    int unsigned buffer_depth = 10;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

endclass : spi_virtual_sequencer
