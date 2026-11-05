# =============================================================================
# RISCFORGE 1TOPS — Nexys 4 DDR build (Vivado, non-project batch flow)
# =============================================================================
#   build.bat                     # Pong, firmware mem/pong (from any folder)
#   build.bat <fw_dir>            # other firmware, relative to ips/RTL_SOC/mem
# or by hand:
#   vivado -mode batch -source build.tcl [-tclargs <fw_dir> [win|linux]]
#
# This folder is self-contained for the Pong board test: top_pong.sv,
# pong.xdc, these scripts, win_sources.f, tb/, and its own out/ and work/.
#
# Sources are taken from the same filelists the Xcelium flow uses
# (filelists/inc.f, ip.f, core.f, soc_rtl.f, in that order, so `define order
# matches the simulation). Those paths are relative to ips/RTL_SOC/sim/.
#
# Outputs in out/:
#   top_pong.bit             bitstream (JTAG load, lost at power-off)
#   <fw>.bin                 firmware image, raw bytes of <fw>_flash.mem
#   nexys4ddr_<fw>.mcs       flash image: bitstream @0x000000, firmware @0x400000
#   reports: utilization, timing summary, DRC
#
# Everything else Vivado produces (.Xil cache, crash dumps, post_synth.dcp /
# post_route.dcp checkpoints) goes to work/, which is safe to delete. The
# script changes into work/ first; build.bat also starts Vivado there, so its
# vivado.log / .jou land in work/ too.
#
# The firmware must be the BOARD build (python build.py, not --sim): the word
# counts in <fw_dir>/fw_params.svh set the bootloader's image length.
# =============================================================================

set here    [file normalize [file dirname [info script]]]
set soc     [file normalize $here/../../..]
set simdir  $soc/sim
set out     $here/out
set work    $here/work
set part    xc7a100tcsg324-1
set test    pong
set top     top_pong

set fw_rel  [expr {[llength $argv] > 0 ? [lindex $argv 0] : "pong"}]
set fw_dir  [file normalize $soc/mem/$fw_rel]
set fw_name [file tail $fw_dir]
set image_addr 0x00400000

file mkdir $out $work
cd $work

# -----------------------------------------------------------------------------
# Filelist reader: +incdir+X, -f X, // comments, plain paths (relative to sim/)
# -----------------------------------------------------------------------------
set srcs    {}
set incdirs {}

proc read_f {path} {
    global srcs incdirs simdir
    set fh [open $path r]
    foreach line [split [read $fh] "\n"] {
        regsub {//.*$} $line "" line
        set line [string trim $line]
        if {$line eq ""} continue
        if {[string match "+incdir+*" $line]} {
            lappend incdirs [file normalize $simdir/[string range $line 8 end]]
        } elseif {[string match "-f *" $line]} {
            read_f [file normalize $simdir/[string trim [string range $line 3 end]]]
        } elseif {[string index $line 0] in {- +}} {
            puts "build.tcl: ignoring option '$line' in $path"
        } else {
            lappend srcs [file normalize $simdir/$line]
        }
    }
    close $fh
}

# The Windows checkout has a different IP layout from the Linux tree the
# shared filelists describe; win_sources.f maps the same files for it.
# Override with a second -tclargs word: "linux" or "win".
set srcset [expr {[llength $argv] > 1 ? [lindex $argv 1] :
                  ($::tcl_platform(platform) eq "windows" ? "win" : "linux")}]
puts "build.tcl: test '$test', firmware '$fw_rel', source set '$srcset'"
if {$srcset eq "win"} {
    read_f $here/win_sources.f
} else {
    foreach f {inc.f ip.f core.f soc_rtl.f} {
        read_f $soc/filelists/$f
    }
}
lappend srcs    $here/$top.sv
lappend incdirs $fw_dir

foreach f $srcs {
    if {![file exists $f]} { error "build.tcl: source not found: $f" }
    if {[file extension $f] eq ".v"} {
        read_verilog $f
    } else {
        read_verilog -sv $f
    }
}
read_xdc $here/$test.xdc

# -----------------------------------------------------------------------------
# Firmware image -> raw binary for write_cfgmem
# -----------------------------------------------------------------------------
set fw_mem $fw_dir/${fw_name}_flash.mem
set fw_bin $out/${fw_name}.bin
if {![file exists $fw_mem]}               { error "build.tcl: $fw_mem not found; run build.py in $fw_dir" }
if {![file exists $fw_dir/fw_params.svh]} { error "build.tcl: $fw_dir/fw_params.svh not found" }

set fh [open $fw_mem r]
set bytes {}
foreach tok [split [read $fh]] {
    if {$tok ne ""} { lappend bytes [scan $tok %x] }
}
close $fh
set fh [open $fw_bin wb]
puts -nonewline $fh [binary format c* $bytes]
close $fh
puts "build.tcl: $fw_name image [llength $bytes] bytes -> $fw_bin"

set bootrom [file normalize $soc/mem/common/riscforge_bootrom.hex]
if {![file exists $bootrom]} { error "build.tcl: boot ROM image $bootrom not found" }

# -----------------------------------------------------------------------------
# Synthesis and implementation
# -----------------------------------------------------------------------------
# FLASH_IMAGE_ADDR keeps its default (24'h40_0000 in top_pong.sv), which
# must equal image_addr above. The defparam'd values appear in the log as
#   Parameter FLASH_START_ADDR bound to: 24'b010000000000000000000000
# under "Synthesizing module 'bootloader'" - check it after the first build.
synth_design -top $top -part $part -include_dirs $incdirs \
    -generic "BOOTROM_HEX=\"$bootrom\""

write_checkpoint -force $work/post_synth.dcp
report_utilization -file $out/utilization_synth.rpt

opt_design
place_design
phys_opt_design
route_design

write_checkpoint -force $work/post_route.dcp
report_utilization    -file $out/utilization.rpt
report_timing_summary -file $out/timing_summary.rpt -max_paths 20
report_drc            -file $out/drc.rpt

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "build.tcl: worst setup slack = $wns ns"
if {$wns < 0} {
    puts "build.tcl: WARNING - timing NOT met at 100 MHz, see out/timing_summary.rpt"
}

write_bitstream -force $out/$top.bit

# -----------------------------------------------------------------------------
# Flash image: bitstream at 0, firmware at image_addr (16 MB S25FL128S, SPI x1)
# -----------------------------------------------------------------------------
write_cfgmem -force -format mcs -size 16 -interface SPIx1 \
    -loadbit  "up 0x00000000 $out/$top.bit" \
    -loaddata "up $image_addr $fw_bin" \
    -file $out/nexys4ddr_${fw_name}.mcs

puts "============================================================"
puts " Nexys 4 DDR build done (test $test)"
puts "   bitstream : $out/$top.bit"
puts "   flash     : $out/nexys4ddr_${fw_name}.mcs  (bit @0x0, $fw_name @$image_addr)"
puts "   timing    : WNS $wns ns"
puts " Program with: program.bat"
puts "============================================================"
