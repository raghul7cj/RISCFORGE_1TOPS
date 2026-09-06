//------------------------------------------------------------------------------
// spi_seq_lib : sequences that run on spi_sequencer to program the VIP's
// reactive SPI slave behaviour.
//------------------------------------------------------------------------------

// -----------------------------------------------------------------------
// spi_slave_resp_seq : arms the driver to shift `resp_words` back MSB-first
// as soon as spi_csn[cs_index] goes low. Mirrors spi_slave_bfm's
// inject_word()/inject_burst() tasks, generalised to quad mode.
// -----------------------------------------------------------------------
class spi_slave_resp_seq extends uvm_sequence #(spi_transaction);
    `uvm_object_utils(spi_slave_resp_seq)

    int unsigned cs_index         = 0;
    bit          quad             = 1'b0;
    int unsigned preamble_symbols = 0;
    bit [31:0]   resp_words[$];

    function new(string name = "spi_slave_resp_seq");
        super.new(name);
    endfunction

    task body();
        spi_transaction tr = spi_transaction::type_id::create("tr");
        start_item(tr);
        tr.kind             = SPI_ITEM_SLAVE_RESP;
        tr.cs_index         = cs_index;
        tr.quad             = quad;
        tr.preamble_symbols = preamble_symbols;
        tr.resp_words       = resp_words;
        finish_item(tr);
    endtask

endclass : spi_slave_resp_seq
