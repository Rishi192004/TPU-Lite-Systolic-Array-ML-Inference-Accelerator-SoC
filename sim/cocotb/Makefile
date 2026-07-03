# TPU-Lite Cocotb Makefile
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

VERILOG_SOURCES += $(PWD)/../../rtl/bus/axi_defines.svh \
                   $(PWD)/../../rtl/pe/pe_mac_csa.sv \
                   $(PWD)/../../rtl/pe/processing_element.sv \
                   $(PWD)/../../rtl/systolic/systolic_array_8x8.sv \
                   $(PWD)/../../rtl/memory/sram_bank.sv \
                   $(PWD)/../../rtl/memory/double_buffer_ctrl.sv \
                   $(PWD)/../../rtl/memory/memory_subsystem.sv \
                   $(PWD)/../../rtl/bus/axi4_lite_slave.sv \
                   $(PWD)/../../rtl/bus/axi4_dma_engine.sv \
                   $(PWD)/../../rtl/tpu_lite_top.sv

TOPLEVEL = tpu_lite_top
MODULE = test_systolic

include $(shell cocotb-config --makefiles)/Makefile.sim
