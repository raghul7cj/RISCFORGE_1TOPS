//------------------------------------------------------------------------------
// spi_transaction
//
// Dual purpose item:
//  - Driven into the spi_sequencer to program the VIP's reactive slave
//    behaviour: which CS index to respond on and which 32-bit words to shift
//    back MSB-first as soon as that CS goes active (mirrors the legacy
//    spi_slave_bfm inject_word/inject_burst tasks, generalised to quad mode).
//  - Produced by spi_monitor for every completed CS burst it observes on the
//    bus: captured MOSI words (what the master shifted out) and the mode/CS
//    used, so the scoreboard/coverage can cross-check against APB activity.
//------------------------------------------------------------------------------
typedef enum { SPI_ITEM_SLAVE_RESP, SPI_ITEM_BUS_CAPTURE } spi_item_kind_e;

class spi_transaction extends uvm_sequence_item;

    spi_item_kind_e kind;

    // ---- fields used when kind == SPI_ITEM_SLAVE_RESP (driven by sequences)
    rand int unsigned  cs_index;         // 0-3, which spi_csn this response answers
    rand bit [31:0]    resp_words[$];    // words shifted back MSB-first, one per SPI word
    rand bit           quad;             // drive on sdi[3:0] (1) or sdi[1] only (0)
    rand int unsigned  preamble_symbols; // symbols before slave response data starts

    // ---- fields filled in by spi_monitor when kind == SPI_ITEM_BUS_CAPTURE
    int unsigned        cs_seen;
    bit                 mode_seen_quad_tx; // burst included at least one QUAD_TX nibble
    bit                 mode_seen_quad_rx; // burst included at least one QUAD_RX nibble
    bit [31:0]          mosi_words[$];     // 32-bit words reconstructed from sdo bit stream
    int unsigned        mosi_bit_count;    // total bits captured on the MOSI side
    time                cs_assert_time;
    time                cs_deassert_time;

    `uvm_object_utils_begin(spi_transaction)
        `uvm_field_int(cs_index, UVM_ALL_ON)
        `uvm_field_int(quad,             UVM_ALL_ON)
        `uvm_field_int(preamble_symbols, UVM_ALL_ON)
        `uvm_field_int(cs_seen,  UVM_ALL_ON)
        `uvm_field_int(mosi_bit_count, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "spi_transaction");
        super.new(name);
        preamble_symbols = 0;
    endfunction

    constraint c_cs_index_range { cs_index inside {[0:3]}; }

    // Returns the last `n` reconstructed 32-bit MOSI words, in transfer
    // order. Since command/address/dummy phases precede the data phase and
    // are usually configured to 0 length in most SPI-flash style
    // transactions, the data payload always lands at the tail of
    // mosi_words -- this is the slice the scoreboard checks TXFIFO writes
    // against.
    function void get_last_n_words(input int n, output bit [31:0] words_q[$]);
        int total, start;
        words_q.delete();
        total = mosi_words.size();
        start = (n >= total) ? 0 : (total - n);
        for (int i = start; i < total; i++)
            words_q.push_back(mosi_words[i]);
    endfunction

    function string convey();
        if (kind == SPI_ITEM_SLAVE_RESP)
            return $sformatf("SPI SLAVE_RESP cs=%0d quad=%0b nwords=%0d",
                              cs_index, quad, resp_words.size());
        else
            return $sformatf("SPI CAPTURE cs=%0d nwords=%0d nbits=%0d qtx=%0b qrx=%0b",
                              cs_seen, mosi_words.size(), mosi_bit_count,
                              mode_seen_quad_tx, mode_seen_quad_rx);
    endfunction

endclass : spi_transaction
