set DESIGN top

# Library setup
set_attribute init_lib_search_path {/root/mini_Project/rtl_to_gds2/scl_pdk/stdlib/fs120/liberty/lib_flow_ss}
set_attribute library {tsl18fs120_scl_ss.lib}

# RTL search path
set_attribute init_hdl_search_path {/root/mini_Project/rv32imc_2/5_stage}

# Create output directories
file mkdir outputs
file mkdir reports

# Read RTL
read_hdl {
    top.v
    ALU.v
    ALU_Decoder.v
    booth_enc.v
    Control_Unit_Top.v
    csa.v
    Data_Memory.v
    decode_cycle.v
    execute_cycle.v
    fetch_cycle.v
    hazard_unit.v
    Instruction_Memory.v
    JB_unit.v
    ls_unit.v
    Main_Decoder.v
    memory_cycle.v
    Mux2.v
    Mux_3_by_1.v
    opcode_check.v
    PC.v
    PC_Adder.v
    pp_gen.v
    Register_File.v
    rv32m_div.v
    rv32m_mul.v
    rv32m_unit.v
    Sign_Extend.v
    writeback_cycle.v
}

# Elaborate design
elaborate $DESIGN
current_design $DESIGN

# Preserve hierarchy for debug netlist
set_attribute auto_ungroup none /
set_attribute delete_unloaded_insts false /
set_attribute optimize_constant_0_flops false /
# Read constraints
read_sdc /root/mini_Project/rv32imc_2/synthesis/LOGS/risc.sdc

# Pre-synthesis checks
check_design > reports/check_design_pre.rpt

# Synthesis flow
syn_generic
syn_map
syn_opt

# Reports
report qor > reports/RISC_top_qor.rpt
report area > reports/RISC_top_area.rpt
report timing > reports/RISC_top_timing.rpt
report power > reports/RISC_top_power.rpt
report sequential -deleted > reports/deleted_seq.rpt
check_design > reports/check_design_post.rpt

# Netlist / constraints / delays
write_hdl -mapped > outputs/RISC_top_netlist_debug.v
write_sdc > outputs/RISC_top_synth.sdc
write_sdf -timescale ns -nonegchecks -recrem split -edges check_edge -setuphold split > outputs/RISC_top_delays.sdf

puts "RISC-V synthesis completed."
