# constraints.tcl

create_clock -name clk -period 4.2 [get_ports clk_i]
set_clock_uncertainty 0.100 [get_clocks clk]

# Always set the input/output delay as half periods for clock setup checks
set_input_delay  2.1 -max -clock [get_clocks clk] [all_inputs]
set_output_delay 2.1 -max -clock [get_clocks clk] [remove_from_collection [all_outputs] [get_ports clk_o]]

# Always set the input/output delay as 0 for clock hold checks
set_input_delay  0.0 -min -clock [get_clocks clk] [all_inputs]
set_output_delay 0.0 -min -clock [get_clocks clk] [remove_from_collection [all_outputs] [get_ports clk_o]]

