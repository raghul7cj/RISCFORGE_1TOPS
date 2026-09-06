//------------------------------------------------------------------------------
// spi_coverage : functional coverage on register-level intent (from the APB
// monitor) and on the resulting SPI bus activity (from the SPI monitor).
//------------------------------------------------------------------------------
class spi_coverage extends uvm_subscriber #(apb_transaction);
    `uvm_component_utils(spi_coverage)

    uvm_analysis_imp_spi #(spi_transaction, spi_coverage) spi_imp;

    protected apb_transaction apb_tr;
    protected spi_transaction spi_tr;

    covergroup cg_apb_reg with function sample(bit [3:0] reg_idx, bit is_write);
        option.per_instance = 1;
        cp_reg   : coverpoint reg_idx {
            bins status = {0};
            bins clkdiv = {1};
            bins spicmd = {2};
            bins spiadr = {3};
            bins spilen = {4};
            bins spidum = {5};
            bins txfifo = {6};
            bins rxfifo = {8};
            bins intcfg = {9};
            bins intsta = {10};
        }
        cp_dir   : coverpoint is_write { bins wr = {1}; bins rd = {0}; }
        cx_reg_dir : cross cp_reg, cp_dir;
    endgroup

    covergroup cg_status_cmd with function sample(bit rd, bit wr, bit qrd, bit qwr, bit [3:0] csreg);
        option.per_instance = 1;
        cp_op : coverpoint {rd, wr, qrd, qwr} {
            bins std_rd  = {4'b1000};
            bins std_wr  = {4'b0100};
            bins quad_rd = {4'b0010};
            bins quad_wr = {4'b0001};
            bins none    = {4'b0000};
            illegal_bins multi_op = default;
        }
        cp_csreg : coverpoint csreg {
            bins cs0 = {4'b0001};
            bins cs1 = {4'b0010};
            bins cs2 = {4'b0100};
            bins cs3 = {4'b1000};
            bins others = default;
        }
    endgroup

    covergroup cg_spi_burst with function sample(int unsigned nwords, bit quad_tx, bit quad_rx, int unsigned cs);
        option.per_instance = 1;
        cp_nwords : coverpoint nwords {
            bins zero = {0};
            bins one = {1};
            bins small_words = {[2:4]};
            bins large_words = {[5:$]};
        }
        cp_mode : coverpoint {quad_tx, quad_rx} {
            bins std_only  = {2'b00};
            bins had_qtx   = {2'b10};
            bins had_qrx   = {2'b01};
            bins had_both  = {2'b11};
        }
        cp_cs : coverpoint cs { bins cs[4] = {[0:3]}; }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        spi_imp     = new("spi_imp", this);
        cg_apb_reg    = new();
        cg_status_cmd = new();
        cg_spi_burst  = new();
    endfunction

    // uvm_subscriber#(apb_transaction) callback
    function void write(apb_transaction t);
        cg_apb_reg.sample(t.addr[5:2], t.dir == APB_WRITE);
        if (t.dir == APB_WRITE && t.addr[5:2] == 4'b0000) // REG_STATUS
            cg_status_cmd.sample(t.wdata[0], t.wdata[1], t.wdata[2], t.wdata[3], t.wdata[11:8]);
    endfunction

    function void write_spi(spi_transaction t);
        if (t.kind == SPI_ITEM_BUS_CAPTURE)
            cg_spi_burst.sample(t.mosi_words.size(), t.mode_seen_quad_tx,
                                 t.mode_seen_quad_rx, t.cs_seen);
    endfunction

endclass : spi_coverage
