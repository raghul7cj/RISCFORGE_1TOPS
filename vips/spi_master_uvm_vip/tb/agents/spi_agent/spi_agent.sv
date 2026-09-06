//------------------------------------------------------------------------------
// spi_agent
//------------------------------------------------------------------------------
class spi_agent extends uvm_agent;
    `uvm_component_utils(spi_agent)

    spi_agent_config cfg;
    spi_sequencer    sqr;
    spi_driver       drv;
    spi_monitor      mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(spi_agent_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("SPI_AGT", "spi_agent_config not found in config_db")

        is_active = cfg.is_active;

        mon = spi_monitor::type_id::create("mon", this);
        uvm_config_db#(spi_agent_config)::set(this, "mon", "cfg", cfg);

        if (is_active == UVM_ACTIVE) begin
            sqr = spi_sequencer::type_id::create("sqr", this);
            drv = spi_driver::type_id::create("drv", this);
            uvm_config_db#(spi_agent_config)::set(this, "drv", "cfg", cfg);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (is_active == UVM_ACTIVE)
            drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass : spi_agent
