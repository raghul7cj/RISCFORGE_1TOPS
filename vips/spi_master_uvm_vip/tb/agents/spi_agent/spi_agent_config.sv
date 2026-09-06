//------------------------------------------------------------------------------
// spi_agent_config
//------------------------------------------------------------------------------
class spi_agent_config extends uvm_object;
    `uvm_object_utils(spi_agent_config)

    uvm_active_passive_enum is_active = UVM_ACTIVE;
    virtual spi_if vif;

    function new(string name = "spi_agent_config");
        super.new(name);
    endfunction
endclass : spi_agent_config
