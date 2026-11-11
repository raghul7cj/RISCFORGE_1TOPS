open_vcd {C:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/Verification/artifacts/csr_trap_closure_check_20261111/run_170540/external_activity_171321/tb_csr_corner_unit/activity.vcd}
set signal [get_objects {/tb_csr_corner_unit/clk}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_csr_corner_unit/clk"}
log_vcd $signal
set signal [get_objects {/tb_csr_corner_unit/dut/rst_n_i}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_csr_corner_unit/dut/rst_n_i"}
log_vcd $signal
set signal [get_objects {/tb_csr_corner_unit/dut/csr_write_en_normal_i}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_csr_corner_unit/dut/csr_write_en_normal_i"}
log_vcd $signal
set signal [get_objects {/tb_csr_corner_unit/dut/trap_valid_i}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_csr_corner_unit/dut/trap_valid_i"}
log_vcd $signal
set signal [get_objects {/tb_csr_corner_unit/dut/mret_commit_i}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_csr_corner_unit/dut/mret_commit_i"}
log_vcd $signal
set signal [get_objects {/tb_csr_corner_unit/dut/instr_retired_i}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_csr_corner_unit/dut/instr_retired_i"}
log_vcd $signal
set signal [get_objects {/tb_csr_corner_unit/dut/fast_intr_i}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_csr_corner_unit/dut/fast_intr_i"}
log_vcd $signal
set signal [get_objects {/tb_csr_corner_unit/dut/timer_intr_i}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_csr_corner_unit/dut/timer_intr_i"}
log_vcd $signal
set signal [get_objects {/tb_csr_corner_unit/dut/ext_intr_i}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_csr_corner_unit/dut/ext_intr_i"}
log_vcd $signal
set signal [get_objects {/tb_csr_corner_unit/dut/msft_intr_i}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_csr_corner_unit/dut/msft_intr_i"}
log_vcd $signal
run all
close_vcd
puts "ACTIVITY_CAPTURE_COMPLETE"
quit
