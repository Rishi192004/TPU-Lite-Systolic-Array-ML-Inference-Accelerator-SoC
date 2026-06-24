# ============================================================================
# TPU-Lite Accelerator SoC - Vivado Batch Synthesis & P&R Script
# File: synth/scripts/synth.tcl
# Description: Automates synthesis, register retiming, place-and-route,
#              and timing report generation for Xilinx Artix-7.
# ============================================================================

set project_name "tpu_lite_synth"
set target_part "xc7a100tcsg324-1"

# 1. Setup Synthesis Directory
file mkdir ./synth_build
cd ./synth_build

# 2. Read SystemVerilog RTL Source Files
read_verilog -sv ../../rtl/bus/axi_defines.svh
read_verilog -sv ../../rtl/pe/pe_mac_csa.sv
read_verilog -sv ../../rtl/pe/processing_element.sv
read_verilog -sv ../../rtl/systolic/systolic_array_8x8.sv
read_verilog -sv ../../rtl/memory/sram_bank.sv
read_verilog -sv ../../rtl/memory/double_buffer_ctrl.sv
read_verilog -sv ../../rtl/memory/memory_subsystem.sv
read_verilog -sv ../../rtl/bus/axi4_lite_slave.sv
read_verilog -sv ../../rtl/bus/axi4_dma_engine.sv
read_verilog -sv ../../rtl/tpu_lite_top.sv

# 3. Read XDC Constraints
read_xdc ../../synth/constraints/tpu_lite_artix7.xdc

# 4. Run Synthesis with Register Retiming Enabled
puts "[*] Starting Vivado Synthesis targeting 250 MHz on Artix-7..."
synth_design -top tpu_lite_top -part $target_part -mode out_of_context -retiming -flatten_hierarchy rebuilt

# 5. Run Opt Design & Placement & Routing
puts "[*] Running Optimization, Placement & Routing..."
opt_design
place_design
phys_opt_design
route_design

# 6. Generate Reports
puts "[*] Generating Synthesis Reports..."
report_timing_summary -file ../../synth/reports/timing_summary.rpt -max_paths 10
report_utilization -file ../../synth/reports/utilization.rpt
report_drc -file ../../synth/reports/drc_summary.rpt

puts "[*] Vivado Synthesis & Implementation Completed Successfully!"
exit
