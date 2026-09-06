//------------------------------------------------------------------------------
// spi_uvm_pkg : single compile unit for the whole SPI master UVM VIP.
// Interfaces (apb_if, spi_if) are NOT part of this package -- they are
// plain SystemVerilog interfaces compiled ahead of it and referenced here
// only via "virtual apb_if" / "virtual spi_if" typed handles.
//------------------------------------------------------------------------------
package spi_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "spi_reg_defines.svh"

    // ---- APB agent ----------------------------------------------------
    `include "apb_transaction.sv"
    `include "apb_sequencer.sv"
    `include "apb_agent_config.sv"
    `include "apb_driver.sv"
    `include "apb_monitor.sv"
    `include "apb_agent.sv"

    // ---- SPI agent ------------------------------------------------------
    `include "spi_transaction.sv"
    `include "spi_sequencer.sv"
    `include "spi_agent_config.sv"
    `include "spi_driver.sv"
    `include "spi_monitor.sv"
    `include "spi_agent.sv"

    // ---- Environment ----------------------------------------------------
    `include "spi_env_config.sv"
    `include "spi_virtual_sequencer.sv"
    `include "spi_scoreboard.sv"
    `include "spi_coverage.sv"
    `include "spi_env.sv"

    // ---- Sequences --------------------------------------------------------
    `include "apb_seq_lib.sv"
    `include "spi_seq_lib.sv"
    `include "virtual_seq_lib.sv"

    // ---- Tests --------------------------------------------------------
    `include "spi_base_test.sv"
    `include "spi_tests.sv"

endpackage : spi_uvm_pkg
