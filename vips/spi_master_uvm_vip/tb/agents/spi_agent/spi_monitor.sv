//------------------------------------------------------------------------------
// spi_monitor : passively watches the SPI bus. For every period where at
// least one spi_csn line is low it reconstructs the bit stream shifted out
// on the MOSI lane(s) into 32-bit words and publishes one spi_transaction
// (kind = SPI_ITEM_BUS_CAPTURE) per burst on completion (CS returns high).
//
// Lane usage mirrors the DUT (spi_master_tx.sv):
//   spi_mode == STD (2'b00)     -> 1 bit/clock on spi_sdo[0]
//   spi_mode == QUAD_TX(2'b01)  -> 4 bits/clock, nibble = {sdo3,sdo2,sdo1,sdo0}
//   spi_mode == QUAD_RX(2'b10)  -> master isn't transmitting real data
//                                   (dummy/read phase); noted for coverage
//                                   only, not packed into mosi_words.
//------------------------------------------------------------------------------
class spi_monitor extends uvm_monitor;
    `uvm_component_utils(spi_monitor)

    spi_agent_config cfg;
    uvm_analysis_port #(spi_transaction) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(spi_agent_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("SPI_MON", "spi_agent_config not found in config_db")
    endfunction

    function int unsigned active_cs_index();
        for (int i = 0; i < 4; i++)
            if (cfg.vif.spi_csn[i] === 1'b0)
                return i;
        return 0;
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            wait (cfg.vif.spi_csn !== 4'b1111);
            capture_burst();
        end
    endtask

    task automatic capture_burst();
        spi_transaction tr;
        bit [31:0] shreg;
        int         bits_in_word;
        bit         prev_clk;

        tr = spi_transaction::type_id::create("tr");
        tr.kind              = SPI_ITEM_BUS_CAPTURE;
        tr.cs_seen           = active_cs_index();
        tr.cs_assert_time    = $time;
        tr.mode_seen_quad_tx = 1'b0;
        tr.mode_seen_quad_rx = 1'b0;
        tr.mosi_bit_count    = 0;
        tr.mosi_words.delete();

        shreg        = '0;
        bits_in_word = 0;
        prev_clk     = cfg.vif.spi_clk;

        while (cfg.vif.spi_csn !== 4'b1111) begin
            @(cfg.vif.spi_clk or cfg.vif.spi_csn);

            if (cfg.vif.spi_csn === 4'b1111)
                break;

            if (cfg.vif.spi_clk === 1'b1 && prev_clk === 1'b0) begin
                // rising edge -> sample, matching spi_master_rx sampling point
                unique case (cfg.vif.spi_mode)
                    2'b01: begin // QUAD_TX
                        bit [3:0] nib;
                        nib = {cfg.vif.spi_sdo[3], cfg.vif.spi_sdo[2],
                               cfg.vif.spi_sdo[1], cfg.vif.spi_sdo[0]};
                        shreg                = {shreg[27:0], nib};
                        bits_in_word        += 4;
                        tr.mosi_bit_count   += 4;
                        tr.mode_seen_quad_tx = 1'b1;
                    end
                    2'b10: begin // QUAD_RX: master not transmitting real data
                        tr.mode_seen_quad_rx = 1'b1;
                    end
                    default: begin // STD
                        shreg              = {shreg[30:0], cfg.vif.spi_sdo[0]};
                        bits_in_word      += 1;
                        tr.mosi_bit_count += 1;
                    end
                endcase

                if (bits_in_word >= 32) begin
                    tr.mosi_words.push_back(shreg);
                    shreg        = '0;
                    bits_in_word = 0;
                end
            end
            prev_clk = cfg.vif.spi_clk;
        end

        if (bits_in_word > 0)
            tr.mosi_words.push_back(shreg); // trailing partial word, left-justified

        tr.cs_deassert_time = $time;
        `uvm_info("SPI_MON", tr.convey(), UVM_HIGH)
        ap.write(tr);
    endtask

endclass : spi_monitor
