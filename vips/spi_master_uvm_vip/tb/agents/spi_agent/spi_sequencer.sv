//------------------------------------------------------------------------------
// spi_sequencer
//------------------------------------------------------------------------------
class spi_sequencer extends uvm_sequencer #(spi_transaction);
    `uvm_component_utils(spi_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass : spi_sequencer
