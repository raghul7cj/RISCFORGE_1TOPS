// =============================================================================
// RISCFORGE 1TOPS - Include paths (for `include directives in IP source files)
// =============================================================================
// All paths are relative to the run directory ips/RTL_SOC/sim/.
// Pulled in by ../run.f. The firmware include path (+incdir+../mem/<fw>) is
// NOT here - it is selected in run.f.
// =============================================================================

+incdir+../../axi_lite_xbar/include/axi
+incdir+../../axi_lite_xbar/include/common_cells
+incdir+../../axi_lite_xbar/include
+incdir+../../SOC_FILES/include/apb
+incdir+../../SOC_FILES/include/obi
+incdir+../../SOC_FILES/include/common_cells
+incdir+../../SOC_FILES/include/axi

// PULP register_interface + OBI UART sources are under SOC_FILES/include/.
// The `include directives are of the form "register_interface/assign.svh",
// so the include path must be the PARENT directory.
+incdir+../../SOC_FILES/include

// I2C and SPI master local includes
+incdir+../../apb_i2c-master/rtl
+incdir+../../spi/spi_master
