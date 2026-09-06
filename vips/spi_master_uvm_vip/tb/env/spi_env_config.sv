//------------------------------------------------------------------------------
// spi_env_config
//------------------------------------------------------------------------------
class spi_env_config extends uvm_object;
    `uvm_object_utils(spi_env_config)

    apb_agent_config apb_cfg;
    spi_agent_config spi_cfg;

    int unsigned buffer_depth = 10; // must match apb_spi_master's BUFFER_DEPTH param

    bit has_scoreboard = 1'b1;
    bit has_coverage   = 1'b1;

    function new(string name = "spi_env_config");
        super.new(name);
    endfunction

endclass : spi_env_config
