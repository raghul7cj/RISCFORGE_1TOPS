// =============================================================================
// RISCFORGE 1TOPS — GPIO directed testbench compilation filelist
// =============================================================================
// Cadence Xcelium:  xrun -f tb_gpio_apb_directed.f
//
// PATHS TARGET THE VLSI CentOS TREE (/home/iiita/MALAY_SOC/rtl/).
// They are relative to the tool's WORKING DIRECTORY, which MUST be
// gpio-master/ — not to the location of this file. So:
//     <file>          -> MALAY_SOC/rtl/gpio-master/<file>
//     ../<dir>/<file> -> MALAY_SOC/rtl/<dir>/<file>
//
// The RTL list below is Section 10 of ../RTL_SOC/soc_subsystem.f (the GPIO
// section), plus the packages and common cells that section depends on. Every
// path is one soc_subsystem.f already compiles successfully on this tree.
//
// Layout notes for this tree:
//     common_cells (sync, assertions.svh) -> ../axi_lite_xbar/include/
//     apb / register_interface            -> ../SOC_FILES/include/
// =============================================================================

-sv
-timescale 1ns/1ps
-access +rwc

// Top module
-top tb_gpio_apb_directed

// =============================================================================
// Section 1: Include paths
// =============================================================================
// The `include directives name their containing directory, e.g.
//   "register_interface/typedef.svh", "common_cells/assertions.svh",
//   "apb/typedef.svh"
// so the PARENT directories must be on the path as well as the leaf ones.
+incdir+../SOC_FILES/include/apb
+incdir+../SOC_FILES/include/register_interface
+incdir+../SOC_FILES/include/common_cells
+incdir+../SOC_FILES/include
+incdir+../axi_lite_xbar/include/common_cells
+incdir+../axi_lite_xbar/include

// =============================================================================
// Section 2: Packages (compile order matters — packages before modules)
// =============================================================================
// GPIO register package (GPIOCount, reg2hw/hw2reg structs, register offsets)
gpio_reg_pkg.sv

// APB package (apb_pkg::prot_t, used by the APB_TYPEDEF_* macros)
../SOC_FILES/include/apb/apb_pkg.sv

// =============================================================================
// Section 3: Common cells
// =============================================================================
// 2-stage synchroniser instantiated by gpio_input_stage
../axi_lite_xbar/include/common_cells/sync.sv

// =============================================================================
// Section 4: PULP register_interface (REG_BUS, apb_to_reg, reggen primitives)
// =============================================================================
../SOC_FILES/include/register_interface/reg_intf.sv
../SOC_FILES/include/register_interface/apb_to_reg.sv
../SOC_FILES/include/register_interface/prim_subreg_arb.sv
../SOC_FILES/include/register_interface/prim_subreg.sv
../SOC_FILES/include/register_interface/prim_subreg_ext.sv

// =============================================================================
// Section 5: GPIO RTL
// =============================================================================
// NOTE: the _no_clk_gates variant declares the SAME module name
// (gpio_input_stage) but drops the tc_clk_gating dependency, which no
// technology cell library is bound in this flow to provide. This is the
// variant the SoC compiles, so it is the one the testbench verifies.
gpio_input_stage_no_clk_gates.sv
gpio_reg_top.sv
gpio.sv
gpio_apb_wrap.sv

// =============================================================================
// Section 6: Testbench
// =============================================================================
tb_gpio_apb_directed.sv
