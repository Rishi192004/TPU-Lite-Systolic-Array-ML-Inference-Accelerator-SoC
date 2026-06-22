# ============================================================================
# TPU-Lite Accelerator SoC - Xilinx Vivado XDC Constraints
# Target Device: Artix-7 XC7A100T-1CSG324C
# Target Clock Frequency: 250 MHz (Period: 4.000 ns)
# ============================================================================

# Primary System Clock (250 MHz)
create_clock -period 4.000 -name clk -waveform {0.000 2.000} [get_ports clk]

# Clock Uncertainty & Jitter
set_clock_uncertainty -setup 0.150 [get_clocks clk]
set_clock_uncertainty -hold  0.050 [get_clocks clk]

# Input / Output Delay Constraints
set_input_delay  -clock clk -max 1.000 [get_ports {s_axi_* m_axi_* rst_n}]
set_input_delay  -clock clk -min 0.200 [get_ports {s_axi_* m_axi_* rst_n}]

set_output_delay -clock clk -max 1.000 [get_ports {s_axi_* m_axi_* interrupt}]
set_output_delay -clock clk -min 0.200 [get_ports {s_axi_* m_axi_* interrupt}]

# False Paths for Async Reset
set_false_path -from [get_ports rst_n]

# Synthesis Retiming & Optimization Directives
set_property BLOCK_SYNTH.RETIMING 1 [get_cells u_systolic_core]
