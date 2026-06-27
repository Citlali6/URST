create_clock -name clk_50m -period 20.000 [get_ports {clk_50m}]
derive_clock_uncertainty

# Board-level asynchronous inputs and simple GPIO-style outputs are verified functionally.
set_false_path -from [get_ports {rst_n uart_rx}]
set_false_path -to [get_ports {uart_tx seg7_sclk seg7_dio seg7_rclk led[*]}]
