//------------------------------------------------------------------------------
// apb_seq_lib : building-block sequences for the APB register interface.
// All of them run on apb_sequencer.
//------------------------------------------------------------------------------

// -----------------------------------------------------------------------
// apb_base_seq : common start_item/finish_item write/read helpers.
// -----------------------------------------------------------------------
class apb_base_seq extends uvm_sequence #(apb_transaction);
    `uvm_object_utils(apb_base_seq)

    function new(string name = "apb_base_seq");
        super.new(name);
    endfunction

    task automatic do_write(bit [11:0] addr, bit [31:0] data);
        apb_transaction tr = apb_transaction::type_id::create("tr");
        start_item(tr);
        if (!tr.randomize() with { this.addr == local::addr; wdata == local::data; dir == APB_WRITE; })
            `uvm_fatal(get_type_name(), "randomize failed")
        finish_item(tr);
    endtask

    task automatic do_read(bit [11:0] addr, output bit [31:0] data, output bit error);
        apb_transaction tr = apb_transaction::type_id::create("tr");
        start_item(tr);
        if (!tr.randomize() with { this.addr == local::addr; dir == APB_READ; })
            `uvm_fatal(get_type_name(), "randomize failed")
        finish_item(tr);
        // The driver mutates this same transaction handle in place (rdata/
        // error/wait_states) before calling item_done(), so no separate
        // get_response() round trip is needed.
        data  = tr.rdata;
        error = tr.error;
    endtask

    task body(); endtask

endclass : apb_base_seq

// -----------------------------------------------------------------------
// apb_cfg_spi_seq : programs CLKDIV/SPICMD/SPIADR/SPILEN/SPIDUM, mirroring
// the legacy cfg_spi() task.
// -----------------------------------------------------------------------
class apb_cfg_spi_seq extends apb_base_seq;
    `uvm_object_utils(apb_cfg_spi_seq)

    bit [7:0]  clk_div;
    bit [31:0] cmd_val;
    bit [5:0]  cmd_bits;
    bit [31:0] adr_val;
    bit [5:0]  adr_bits;
    bit [15:0] data_bits;
    bit [15:0] dum_rd;
    bit [15:0] dum_wr;

    function new(string name = "apb_cfg_spi_seq");
        super.new(name);
    endfunction

    task body();
        do_write(`SPI_REG_CLKDIV, {24'h0, clk_div});
        do_write(`SPI_REG_SPICMD, cmd_val);
        do_write(`SPI_REG_SPIADR, adr_val);
        do_write(`SPI_REG_SPILEN, {data_bits, 2'b00, adr_bits, 2'b00, cmd_bits});
        do_write(`SPI_REG_SPIDUM, {dum_wr, dum_rd});
    endtask

endclass : apb_cfg_spi_seq

// -----------------------------------------------------------------------
// apb_trigger_seq : writes REG_STATUS to kick off rd/wr/qrd/qwr and select
// the chip-select mask.
// -----------------------------------------------------------------------
class apb_trigger_seq extends apb_base_seq;
    `uvm_object_utils(apb_trigger_seq)

    bit         rd, wr, qrd, qwr, swrst;
    bit [3:0]   csreg = 4'b0001;

    function new(string name = "apb_trigger_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] w;
        w = '0;
        w[`STATUS_BIT_RD]    = rd;
        w[`STATUS_BIT_WR]    = wr;
        w[`STATUS_BIT_QRD]   = qrd;
        w[`STATUS_BIT_QWR]   = qwr;
        w[`STATUS_BIT_SWRST] = swrst;
        w[11:8]              = csreg;
        do_write(`SPI_REG_STATUS, w);
    endtask

endclass : apb_trigger_seq

// -----------------------------------------------------------------------
// apb_txfifo_write_seq : pushes a queue of 32-bit words into REG_TXFIFO.
// -----------------------------------------------------------------------
class apb_txfifo_write_seq extends apb_base_seq;
    `uvm_object_utils(apb_txfifo_write_seq)

    bit [31:0] words[$];

    function new(string name = "apb_txfifo_write_seq");
        super.new(name);
    endfunction

    task body();
        foreach (words[i])
            do_write(`SPI_REG_TXFIFO, words[i]);
    endtask

endclass : apb_txfifo_write_seq

// -----------------------------------------------------------------------
// apb_rxfifo_read_seq : pops `num_words` words from REG_RXFIFO. Each read
// naturally stalls on PREADY until the SPI side has produced data, exactly
// like the DUT's backpressure mechanism intends.
// -----------------------------------------------------------------------
class apb_rxfifo_read_seq extends apb_base_seq;
    `uvm_object_utils(apb_rxfifo_read_seq)

    int unsigned num_words = 1;
    bit [31:0]   words_read[$];

    function new(string name = "apb_rxfifo_read_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] d;
        bit        err;
        words_read.delete();
        for (int i = 0; i < num_words; i++) begin
            do_read(`SPI_REG_RXFIFO, d, err);
            words_read.push_back(d);
        end
    endtask

endclass : apb_rxfifo_read_seq

// -----------------------------------------------------------------------
// apb_read_status_seq : single REG_STATUS read.
// -----------------------------------------------------------------------
class apb_read_status_seq extends apb_base_seq;
    `uvm_object_utils(apb_read_status_seq)

    bit [31:0] status;

    function new(string name = "apb_read_status_seq");
        super.new(name);
    endfunction

    task body();
        bit err;
        do_read(`SPI_REG_STATUS, status, err);
    endtask

endclass : apb_read_status_seq
