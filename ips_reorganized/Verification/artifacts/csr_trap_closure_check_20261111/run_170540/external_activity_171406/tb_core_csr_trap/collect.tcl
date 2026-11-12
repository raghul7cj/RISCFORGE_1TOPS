open_vcd {C:/Users/cj/AppData/Local/Temp/csrcheck_9mi5njrz/tb_core_csr_trap/external_activity_171406/activity.vcd}
set signal [get_objects {/tb_core_csr_trap/clk}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_core_csr_trap/clk"}
log_vcd $signal
set signal [get_objects {/tb_core_csr_trap/core/rst}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_core_csr_trap/core/rst"}
log_vcd $signal
set signal [get_objects {/tb_core_csr_trap/core/trap_commit_valid}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_core_csr_trap/core/trap_commit_valid"}
log_vcd $signal
set signal [get_objects {/tb_core_csr_trap/core/mret_commit}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_core_csr_trap/core/mret_commit"}
log_vcd $signal
set signal [get_objects {/tb_core_csr_trap/core/valid_W}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_core_csr_trap/core/valid_W"}
log_vcd $signal
set signal [get_objects {/tb_core_csr_trap/core/exc_valid_W}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_core_csr_trap/core/exc_valid_W"}
log_vcd $signal
set signal [get_objects {/tb_core_csr_trap/core/RegWriteW_gated}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_core_csr_trap/core/RegWriteW_gated"}
log_vcd $signal
set signal [get_objects {/tb_core_csr_trap/core/csr_write_en_W_gated}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_core_csr_trap/core/csr_write_en_W_gated"}
log_vcd $signal
set signal [get_objects {/tb_core_csr_trap/core/lsu_mem_req}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_core_csr_trap/core/lsu_mem_req"}
log_vcd $signal
set signal [get_objects {/tb_core_csr_trap/core/lsu_mem_we}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_core_csr_trap/core/lsu_mem_we"}
log_vcd $signal
set signal [get_objects {/tb_core_csr_trap/core/fast_irq_i}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_core_csr_trap/core/fast_irq_i"}
log_vcd $signal
set signal [get_objects {/tb_core_csr_trap/core/timer_irq_i}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_core_csr_trap/core/timer_irq_i"}
log_vcd $signal
set signal [get_objects {/tb_core_csr_trap/core/ext_irq_i}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_core_csr_trap/core/ext_irq_i"}
log_vcd $signal
set signal [get_objects {/tb_core_csr_trap/core/sw_irq_i}]
if {[llength $signal] != 1} {error "Missing observation signal: /tb_core_csr_trap/core/sw_irq_i"}
log_vcd $signal
run all
close_vcd
puts "ACTIVITY_CAPTURE_COMPLETE"
quit
