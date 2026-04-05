create_clock -name clk -period 10 [get_ports clk]

set_clock_uncertainty -setup 0.15 [get_clocks clk]
set_clock_uncertainty -hold 0.08 [get_clocks clk]
set_clock_transition 0.1 [get_clocks clk]
set_clock_latency 0.2 [get_clocks clk]

set_false_path -from [get_ports rst]

set INPUT_PORTS [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay -max 1.5 -clock clk $INPUT_PORTS
set_input_delay -min 0.2 -clock clk $INPUT_PORTS

set_output_delay -max 1.5 -clock clk [all_outputs]
set_output_delay -min 0.2 -clock clk [all_outputs]

# Instead of set_driving_cell, use transition directly
set_input_transition 0.1 $INPUT_PORTS
set_load 0.01 [all_outputs]
