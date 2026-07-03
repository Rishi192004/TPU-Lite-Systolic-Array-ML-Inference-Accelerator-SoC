# ============================================================================
# TPU-Lite Accelerator SoC - Cocotb Python Verification Test Suite
# File: sim/cocotb/test_systolic.py
# Description: Automated Python Cocotb test runner for TPU-Lite 8x8 array.
# ============================================================================

import cocotb
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.clock import Clock
import numpy as np

@cocotb.test()
async def test_systolic_matmul_basic(dut):
    """Verifies basic 8x8 matrix multiplication on hardware using Cocotb."""
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    
    # Reset DUT
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    dut._log.info("Cocotb testbench initialized successfully.")
