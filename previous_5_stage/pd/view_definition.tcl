

set lib /root/mini_Project/rtl_to_gds2/scl_pdk
create_library_set -name my_min_library_set -timing [list $lib/stdlib/fs120/liberty/lib_flow_ff/tsl18fs120_scl_ff.lib $lib/iolib/cio150/synopsys/2002.05/models/tsl18cio150_min.lib] 

create_library_set -name my_max_library_set -timing [list $lib/stdlib/fs120/liberty/lib_flow_ss/tsl18fs120_scl_ss.lib $lib/iolib/cio150/synopsys/2002.05/models/tsl18cio150_max.lib]

create_library_set -name lib_180nm -timing [list $lib/stdlib/fs120/liberty/lib_flow_ss/tsl18fs120_scl_ss.lib $lib/iolib/cio150/synopsys/2002.05/models/tsl18cio150_typ.lib]
 
create_constraint_mode -name my_constraint_mode \
	-sdc_files /root/mini_Project/rv32imc_2/Physical_Design2/RISC_top_synth.sdc

create_rc_corner -name my_rc_corner_worst\
	-T 				   25

create_delay_corner -name my_delay_corner_max \
	-library_set my_max_library_set \
	-rc_corner   my_rc_corner_worst

create_delay_corner -name my_delay_corner_min \
	-library_set my_min_library_set \
	-rc_corner   my_rc_corner_worst

create_analysis_view -name my_analysis_view_setup \
	-constraint_mode my_constraint_mode \
	-delay_corner    my_delay_corner_max
 
create_analysis_view -name my_analysis_view_hold \
	-constraint_mode my_constraint_mode \
	-delay_corner    my_delay_corner_min

set_analysis_view \
	-setup [list my_analysis_view_setup] \
	-hold  [list my_analysis_view_hold]

