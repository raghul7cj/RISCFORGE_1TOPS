//------------------------------------------------------------------------------
// spi_driver : acts as a reactive SPI slave. Each item taken from the
// sequencer describes a burst of 32-bit response words that should be
// shifted MSB-first onto spi_sdi as soon as the addressed spi_csn[cs_index]
// goes low, generalising the legacy spi_slave_bfm inject_word/inject_burst
// tasks to also support quad mode (4 lanes, nibble per clock).
//
// Mode 0 timing (matches spi_master_clkgen / spi_master_rx in the DUT):
// idle-low clock, master samples on the rising edge, so the slave must
// present new data by the falling edge (negedge spi_clk) -- exactly as the
// original BFM did.
//------------------------------------------------------------------------------
class spi_driver extends uvm_driver #(spi_transaction);
    `uvm_component_utils(spi_driver)

    spi_agent_config cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(spi_agent_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("SPI_DRV", "spi_agent_config not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        cfg.vif.spi_sdi = 4'b0000;
        forever begin
            spi_transaction req;
            seq_item_port.get_next_item(req);
            drive_response(req);
            seq_item_port.item_done();
        end
    endtask

    // Flattens resp_words MSB-first into a bit queue, then shifts it out
    // 1 bit (STD) or 4 bits (quad) per clock, presenting the first symbol
    // immediately when CS asserts and one new symbol per negedge after that.
    task automatic drive_response(spi_transaction req);
        bit stream[$];
        int total_bits;
        int step;
        int idx;

        stream.delete();

        foreach (req.resp_words[w])
            for (int b = 31; b >= 0; b--)
                stream.push_back(req.resp_words[w][b]);

        total_bits = stream.size();
        step       = req.quad ? 4 : 1;
        idx        = 0;

        cfg.vif.spi_sdi = 4'b0000;

        `uvm_info("SPI_DRV",
            $sformatf("waiting for csn[%0d], preamble_symbols=%0d quad=%0b",
                      req.cs_index, req.preamble_symbols, req.quad),
            UVM_HIGH)

        wait (cfg.vif.spi_csn[req.cs_index] === 1'b0);

        // Wait through command/address/dummy phase.
        repeat (req.preamble_symbols) begin
            @(negedge cfg.vif.spi_clk);

            if (cfg.vif.spi_csn[req.cs_index] === 1'b1) begin
                cfg.vif.spi_sdi = 4'b0000;
                return;
            end
        end

        // Start returning slave data after the preamble.
        if ((total_bits > 0) &&
            (cfg.vif.spi_csn[req.cs_index] === 1'b0)) begin

            drive_symbol(stream, idx, req.quad);
            idx += step;

            while ((idx < total_bits) &&
                   (cfg.vif.spi_csn[req.cs_index] === 1'b0)) begin

                @(negedge cfg.vif.spi_clk);

                if (cfg.vif.spi_csn[req.cs_index] === 1'b0) begin
                    drive_symbol(stream, idx, req.quad);
                    idx += step;
                end
            end
        end

        wait (cfg.vif.spi_csn[req.cs_index] === 1'b1);
        cfg.vif.spi_sdi = 4'b0000;
    endtask

    function automatic void drive_symbol(ref bit stream[$], input int idx, input bit quad);
        if (quad) begin
            cfg.vif.spi_sdi[3] = stream[idx+0];
            cfg.vif.spi_sdi[2] = stream[idx+1];
            cfg.vif.spi_sdi[1] = stream[idx+2];
            cfg.vif.spi_sdi[0] = stream[idx+3];
        end
        else begin
            cfg.vif.spi_sdi[1] = stream[idx];
        end
    endfunction

endclass : spi_driver
