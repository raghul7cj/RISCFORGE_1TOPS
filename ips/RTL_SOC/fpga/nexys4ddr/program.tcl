# =============================================================================
# RISCFORGE 1TOPS — program the Nexys 4 DDR
# =============================================================================
#   program.bat                   # flash + reboot (Pong), from any folder
#   program.bat flash <fw>        # other firmware .mcs
#   program.bat jtag              # bitstream only
# or by hand: vivado -mode batch -source program.tcl [-tclargs <mode> [<fw>]]
#
# Vivado's run files (log, journal, hw_server cache) go to work/.
#
# flash : writes out/nexys4ddr_<fw>.mcs into the S25FL128S (bitstream + firmware),
#         then reconfigures the FPGA from flash. Survives power-off. Set the
#         board's MODE jumper (JP1) to QSPI so it boots from flash at power-on.
# jtag  : loads out/nexys4ddr_top.bit over JTAG. The firmware must already be
#         in the flash at 0x400000 (from an earlier "flash" run), because the
#         SoC always boots its program from the flash.
# =============================================================================

set here [file normalize [file dirname [info script]]]
set out  $here/out
file mkdir $here/work
cd $here/work
set mode [expr {[llength $argv] > 0 ? [lindex $argv 0] : "flash"}]
set fw   [expr {[llength $argv] > 1 ? [lindex $argv 1] : "pong"}]

open_hw_manager
connect_hw_server
open_hw_target

set dev [lindex [get_hw_devices xc7a100t_0] 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

if {$mode eq "jtag"} {
    set_property PROGRAM.FILE $out/nexys4ddr_top.bit $dev
    program_hw_devices $dev
    puts "program.tcl: bitstream loaded over JTAG"
} else {
    set mcs $out/nexys4ddr_${fw}.mcs
    if {![file exists $mcs]} { error "program.tcl: $mcs not found; run build.tcl first" }

    set mem [create_hw_cfgmem -hw_device $dev \
                [lindex [get_cfgmem_parts {s25fl128sxxxxxx0-spi-x1_x2_x4}] 0]]
    set_property PROGRAM.FILES          [list $mcs] $mem
    set_property PROGRAM.ADDRESS_RANGE  {use_file}  $mem
    set_property PROGRAM.BLANK_CHECK    0           $mem
    set_property PROGRAM.ERASE          1           $mem
    set_property PROGRAM.CFG_PROGRAM    1           $mem
    set_property PROGRAM.VERIFY         1           $mem
    set_property PROGRAM.CHECKSUM       0           $mem

    # The cfgmem programming core is loaded into the FPGA first
    if {![string equal [get_property PROGRAM.HW_CFGMEM_TYPE $dev] \
                       [get_property MEM_TYPE [get_property CFGMEM_PART $mem]]]} {
        create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
        program_hw_devices $dev
    }
    program_hw_cfgmem -hw_cfgmem $mem
    puts "program.tcl: flash written and verified ($mcs)"

    boot_hw_device $dev
    puts "program.tcl: FPGA reconfigured from flash - open the terminal at 115200 8N1"
}

close_hw_target
disconnect_hw_server
close_hw_manager
