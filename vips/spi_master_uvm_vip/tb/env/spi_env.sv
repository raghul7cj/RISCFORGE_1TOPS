//------------------------------------------------------------------------------
// spi_env
//------------------------------------------------------------------------------
class spi_env extends uvm_env;
    `uvm_component_utils(spi_env)

    spi_env_config        cfg;
    apb_agent             apb_agt;
    spi_agent             spi_agt;
    spi_scoreboard        sb;
    spi_coverage          cov;
    spi_virtual_sequencer vsqr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(spi_env_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("SPI_ENV", "spi_env_config not found in config_db")

        uvm_config_db#(apb_agent_config)::set(this, "apb_agt*", "cfg", cfg.apb_cfg);
        uvm_config_db#(spi_agent_config)::set(this, "spi_agt*", "cfg", cfg.spi_cfg);

        apb_agt = apb_agent::type_id::create("apb_agt", this);
        spi_agt = spi_agent::type_id::create("spi_agt", this);

        vsqr = spi_virtual_sequencer::type_id::create("vsqr", this);

        if (cfg.has_scoreboard) begin
            sb = spi_scoreboard::type_id::create("sb", this);
            // Published globally so virtual sequences can register expected
            // RX words without needing a bespoke TLM path just for that.
            uvm_config_db#(spi_scoreboard)::set(null, "*", "spi_scoreboard_handle", sb);
        end

        if (cfg.has_coverage)
            cov = spi_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        vsqr.apb_sqr = apb_agt.sqr;
        vsqr.spi_sqr = spi_agt.sqr;
        vsqr.vif     = cfg.apb_cfg.vif;
        vsqr.spi_vif = cfg.spi_cfg.vif;
        vsqr.buffer_depth = cfg.buffer_depth;

        if (cfg.has_scoreboard) begin
            apb_agt.mon.ap.connect(sb.apb_imp);
            spi_agt.mon.ap.connect(sb.spi_imp);
        end

        if (cfg.has_coverage) begin
            apb_agt.mon.ap.connect(cov.analysis_export);
            spi_agt.mon.ap.connect(cov.spi_imp);
        end
    endfunction

endclass : spi_env
