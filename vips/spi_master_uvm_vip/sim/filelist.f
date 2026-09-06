
+incdir+../tb
+incdir+../tb/agents/apb_agent
+incdir+../tb/agents/spi_agent
+incdir+../tb/env
+incdir+../tb/seq_lib
+incdir+../tb/tests

// DUT

../rtl/spi_master_clkgen.sv
../rtl/spi_master_fifo.sv
../rtl/spi_master_apb_if.sv
../rtl/spi_master_tx.sv
../rtl/spi_master_rx.sv
../rtl/spi_master_controller.sv
../rtl/apb_spi_master.sv

// VIP interfaces

../tb/interfaces/apb_if.sv
../tb/interfaces/spi_if.sv 

../tb/spi_uvm_pkg.sv

../tb/top/spi_tb_top.sv
