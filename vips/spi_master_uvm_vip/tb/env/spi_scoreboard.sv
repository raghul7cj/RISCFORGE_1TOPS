//------------------------------------------------------------------------------
// spi_scoreboard
//
// Two checks are performed automatically from bus activity alone:
//
//  1. TX path: every word written to REG_TXFIFO over APB is expected to
//     reappear, in order, as the tail of the next SPI bus capture's
//     mosi_words (the payload phase always comes last in a transfer, see
//     spi_transaction::get_last_n_words).
//
//  2. RX path: every word read back from REG_RXFIFO over APB is expected to
//     match, in order, the words the testbench told the SPI slave driver to
//     shift in for the current transaction. Since the driver only knows the
//     words a sequence *told* it to send, the sequence must register that
//     same expectation with the scoreboard via add_expected_rx_words() right
//     after starting the SPI response sequence -- this makes the reactive
//     slave model itself the reference model, which is the normal pattern
//     for this class of VIP.
//------------------------------------------------------------------------------
`uvm_analysis_imp_decl(_apb)
`uvm_analysis_imp_decl(_spi)

class spi_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(spi_scoreboard)

    uvm_analysis_imp_apb #(apb_transaction, spi_scoreboard) apb_imp;
    uvm_analysis_imp_spi #(spi_transaction, spi_scoreboard) spi_imp;

    // learned APB-side transaction configuration
    protected bit [31:0] tx_fifo_writes[$];
    protected bit [31:0] expected_rx_words[$];

    protected bit [31:0] r_spi_cmd, r_spi_addr;
    protected bit [5:0]  r_cmd_len, r_addr_len;
    protected bit [15:0] r_data_len, r_dummy_rd, r_dummy_wr;
    protected bit [7:0]  r_clk_div;
    protected bit [3:0]  r_csreg;

    int unsigned num_tx_checks, num_tx_errors;
    int unsigned num_rx_checks, num_rx_errors;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        apb_imp = new("apb_imp", this);
        spi_imp = new("spi_imp", this);
    endfunction

    // -------------------------------------------------------------------
    // Public API used by sequences: register the words the SPI slave
    // driver has been armed to send back, so REG_RXFIFO reads can be
    // checked against them.
    // -------------------------------------------------------------------
    function void add_expected_rx_words(bit [31:0] words[$]);
        foreach (words[i])
            expected_rx_words.push_back(words[i]);
    endfunction

    // -------------------------------------------------------------------
    // APB monitor callback
    // -------------------------------------------------------------------
    function void write_apb(apb_transaction tr);
        bit [3:0] wr_addr = tr.addr[5:2];

        if (tr.dir == APB_WRITE) begin
            case (wr_addr)
                `SPI_REG_TXFIFO >> 2: tx_fifo_writes.push_back(tr.wdata);
                `SPI_REG_SPICMD >> 2: r_spi_cmd  = tr.wdata;
                `SPI_REG_SPIADR >> 2: r_spi_addr = tr.wdata;
                `SPI_REG_CLKDIV >> 2: r_clk_div  = tr.wdata[7:0];
                `SPI_REG_SPILEN >> 2: begin
                    r_cmd_len  = tr.wdata[5:0];
                    r_addr_len = tr.wdata[13:8];
                    r_data_len = {tr.wdata[31:24], tr.wdata[23:16]};
                end
                `SPI_REG_SPIDUM >> 2: begin
                    r_dummy_rd = {tr.wdata[15:8], tr.wdata[7:0]};
                    r_dummy_wr = {tr.wdata[31:24], tr.wdata[23:16]};
                end
                `SPI_REG_STATUS >> 2: r_csreg = tr.wdata[11:8];
                default: ; // interrupt config / others not needed for checking
            endcase
        end
        else begin // APB_READ
            if (wr_addr == (`SPI_REG_RXFIFO >> 2)) begin
                num_rx_checks++;
                if (expected_rx_words.size() == 0) begin
                    `uvm_warning("SB_RX", $sformatf(
                        "RXFIFO read (0x%08h) with no outstanding expected word queued -- did the test forget add_expected_rx_words()?",
                        tr.rdata))
                end
                else begin
                    bit [31:0] exp = expected_rx_words.pop_front();
                    if (tr.rdata !== exp) begin
                        num_rx_errors++;
                        `uvm_error("SB_RX", $sformatf(
                            "RXFIFO mismatch: got=0x%08h exp=0x%08h", tr.rdata, exp))
                    end
                    else
                        `uvm_info("SB_RX", $sformatf(
                            "RXFIFO match: 0x%08h", tr.rdata), UVM_MEDIUM)
                end
            end
        end
    endfunction

    // -------------------------------------------------------------------
    // SPI monitor callback
    // -------------------------------------------------------------------
    function void write_spi(spi_transaction tr);
        bit [31:0] tail[$];
        int        n;

        if (tr.kind != SPI_ITEM_BUS_CAPTURE)
            return;

        if (tx_fifo_writes.size() == 0)
            return; // nothing queued on the TX side for this burst

        n = tx_fifo_writes.size();
        tr.get_last_n_words(n, tail);

        if (tail.size() != n) begin
            `uvm_warning("SB_TX", $sformatf(
                "Captured burst has only %0d word(s), expected at least %0d queued TXFIFO word(s)",
                tail.size(), n))
        end

        foreach (tx_fifo_writes[i]) begin
            num_tx_checks++;
            if (i >= tail.size()) continue;
            if (tail[i] !== tx_fifo_writes[i]) begin
                num_tx_errors++;
                `uvm_error("SB_TX", $sformatf(
                    "MOSI mismatch word[%0d]: got=0x%08h exp=0x%08h",
                    i, tail[i], tx_fifo_writes[i]))
            end
            else
                `uvm_info("SB_TX", $sformatf(
                    "MOSI match word[%0d]: 0x%08h", i, tail[i]), UVM_MEDIUM)
        end
        tx_fifo_writes.delete();
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SB_SUMMARY", $sformatf(
            "TX checks=%0d errors=%0d | RX checks=%0d errors=%0d",
            num_tx_checks, num_tx_errors, num_rx_checks, num_rx_errors), UVM_LOW)
        if (num_tx_errors || num_rx_errors)
            `uvm_error("SB_SUMMARY", "Scoreboard reported mismatches -- see log above")
    endfunction

endclass : spi_scoreboard
