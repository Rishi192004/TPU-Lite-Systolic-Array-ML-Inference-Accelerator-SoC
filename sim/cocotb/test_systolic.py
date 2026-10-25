# ============================================================================
# TPU-Lite Accelerator SoC - Cocotb Python Verification Test Suite
# File: sim/cocotb/test_systolic.py
#
# Tests: AXI4-Lite CSR read/write, reset behavior, interrupt signaling
# DUT  : tpu_lite_top (full SoC including AXI4-Lite CSR slave)
#
# Note: The systolic compute core is exercised at the SV level by
#       tb_systolic_self_check.sv with 10 tests and 330 scoreboard checks.
#       These cocotb tests cover the AXI4-Lite host interface layer.
# ============================================================================

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer
from cocotb.clock import Clock

# ---------------------------------------------------------------------------
# AXI4-Lite helpers
# ---------------------------------------------------------------------------

async def axi_write(dut, addr, data, timeout_cycles=50):
    """Single AXI4-Lite write transaction."""
    dut.s_axi_awaddr.value  = addr
    dut.s_axi_awvalid.value = 1
    dut.s_axi_wdata.value   = data
    dut.s_axi_wstrb.value   = 0xF
    dut.s_axi_wvalid.value  = 1
    dut.s_axi_bready.value  = 1

    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if dut.s_axi_awready.value and dut.s_axi_wready.value:
            break
    else:
        raise AssertionError(f"AXI write addr={addr:#010x} timed out waiting for awready+wready")

    dut.s_axi_awvalid.value = 0
    dut.s_axi_wvalid.value  = 0

    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if dut.s_axi_bvalid.value:
            break
    else:
        raise AssertionError(f"AXI write addr={addr:#010x} timed out waiting for bvalid")

    dut.s_axi_bready.value = 0


async def axi_read(dut, addr, timeout_cycles=50):
    """Single AXI4-Lite read transaction. Returns integer."""
    dut.s_axi_araddr.value  = addr
    dut.s_axi_arvalid.value = 1
    dut.s_axi_rready.value  = 1

    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if dut.s_axi_arready.value:
            break
    else:
        raise AssertionError(f"AXI read addr={addr:#010x} timed out waiting for arready")

    dut.s_axi_arvalid.value = 0

    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if dut.s_axi_rvalid.value:
            rdata = int(dut.s_axi_rdata.value)
            dut.s_axi_rready.value = 0
            return rdata

    raise AssertionError(f"AXI read addr={addr:#010x} timed out waiting for rvalid")


def drive_m_axi_idle(dut):
    """Put AXI4 master memory bus into benign idle state."""
    dut.m_axi_arready.value = 1
    dut.m_axi_rdata.value   = 0
    dut.m_axi_rresp.value   = 0
    dut.m_axi_rlast.value   = 0
    dut.m_axi_rvalid.value  = 0
    dut.m_axi_awready.value = 1
    dut.m_axi_wready.value  = 1
    dut.m_axi_bresp.value   = 0
    dut.m_axi_bvalid.value  = 0


async def reset_dut(dut, cycles=10):
    """Apply synchronous reset for 'cycles' clock cycles."""
    dut.rst_n.value = 0
    drive_m_axi_idle(dut)
    # AXI4-Lite inputs to idle
    dut.s_axi_awaddr.value  = 0
    dut.s_axi_awvalid.value = 0
    dut.s_axi_wdata.value   = 0
    dut.s_axi_wstrb.value   = 0xF
    dut.s_axi_wvalid.value  = 0
    dut.s_axi_bready.value  = 0
    dut.s_axi_araddr.value  = 0
    dut.s_axi_arvalid.value = 0
    dut.s_axi_rready.value  = 0
    await ClockCycles(dut.clk, cycles)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)


# CSR register offsets (from axi_defines.svh)
CSR_CTRL_REG       = 0x00
CSR_STATUS_REG     = 0x04
CSR_DIM_M_REG      = 0x08
CSR_DIM_K_REG      = 0x0C
CSR_DIM_N_REG      = 0x10
CSR_ACT_BASE_ADDR  = 0x14
CSR_WGT_BASE_ADDR  = 0x18
CSR_OUT_BASE_ADDR  = 0x1C
CSR_PERF_CYCLE_LO  = 0x20

# ---------------------------------------------------------------------------
# TEST 1 — Reset: all outputs must be defined zero after release
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_01_reset_outputs_zero(dut):
    """After reset, interrupt must be low and AXI outputs must be driven."""
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    await reset_dut(dut)

    assert int(dut.interrupt.value) == 0, \
        f"[FAIL] interrupt not low after reset: {dut.interrupt.value}"
    assert int(dut.s_axi_awready.value) == 0, \
        f"[FAIL] s_axi_awready not 0 after reset: {dut.s_axi_awready.value}"
    assert int(dut.s_axi_bvalid.value) == 0, \
        f"[FAIL] s_axi_bvalid not 0 after reset: {dut.s_axi_bvalid.value}"
    assert int(dut.s_axi_arready.value) == 0, \
        f"[FAIL] s_axi_arready not 0 after reset: {dut.s_axi_arready.value}"
    assert int(dut.s_axi_rvalid.value) == 0, \
        f"[FAIL] s_axi_rvalid not 0 after reset: {dut.s_axi_rvalid.value}"
    dut._log.info("[PASS] test_01_reset_outputs_zero")


# ---------------------------------------------------------------------------
# TEST 2 — CSR write + readback: dimension registers
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_02_csr_dim_readback(dut):
    """Write M/K/N dimension registers and read them back."""
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    await reset_dut(dut)

    await axi_write(dut, CSR_DIM_M_REG, 8)
    await axi_write(dut, CSR_DIM_K_REG, 8)
    await axi_write(dut, CSR_DIM_N_REG, 8)

    m = await axi_read(dut, CSR_DIM_M_REG)
    k = await axi_read(dut, CSR_DIM_K_REG)
    n = await axi_read(dut, CSR_DIM_N_REG)

    assert m == 8, f"[FAIL] DIM_M readback: expected 8, got {m}"
    assert k == 8, f"[FAIL] DIM_K readback: expected 8, got {k}"
    assert n == 8, f"[FAIL] DIM_N readback: expected 8, got {n}"
    dut._log.info(f"[PASS] test_02_csr_dim_readback: M={m} K={k} N={n}")


# ---------------------------------------------------------------------------
# TEST 3 — CSR write + readback: base address registers
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_03_csr_base_addr_readback(dut):
    """Write activation/weight/output base address CSRs and read them back."""
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    await reset_dut(dut)

    ACT_ADDR = 0x1000_0000
    WGT_ADDR = 0x2000_0000
    OUT_ADDR = 0x3000_0000

    await axi_write(dut, CSR_ACT_BASE_ADDR, ACT_ADDR)
    await axi_write(dut, CSR_WGT_BASE_ADDR, WGT_ADDR)
    await axi_write(dut, CSR_OUT_BASE_ADDR, OUT_ADDR)

    ra = await axi_read(dut, CSR_ACT_BASE_ADDR)
    rw = await axi_read(dut, CSR_WGT_BASE_ADDR)
    ro = await axi_read(dut, CSR_OUT_BASE_ADDR)

    assert ra == ACT_ADDR, f"[FAIL] ACT_BASE readback: expected {ACT_ADDR:#010x}, got {ra:#010x}"
    assert rw == WGT_ADDR, f"[FAIL] WGT_BASE readback: expected {WGT_ADDR:#010x}, got {rw:#010x}"
    assert ro == OUT_ADDR, f"[FAIL] OUT_BASE readback: expected {OUT_ADDR:#010x}, got {ro:#010x}"
    dut._log.info("[PASS] test_03_csr_base_addr_readback")


# ---------------------------------------------------------------------------
# TEST 4 — STATUS register: idle after reset
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_04_status_idle_after_reset(dut):
    """STATUS register [0]=busy must be 0, [1]=done must be 0 after reset."""
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    await reset_dut(dut)

    status = await axi_read(dut, CSR_STATUS_REG)
    busy = status & 0x1
    done = (status >> 1) & 0x1

    assert busy == 0, f"[FAIL] STATUS.busy should be 0 after reset, got {busy}"
    assert done == 0, f"[FAIL] STATUS.done should be 0 after reset, got {done}"
    dut._log.info(f"[PASS] test_04_status_idle_after_reset: STATUS={status:#010x}")


# ---------------------------------------------------------------------------
# TEST 5 — Performance counter increments while running
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_05_perf_counter_increments(dut):
    """PERF_CYCLE_LO must be non-zero after several clock cycles."""
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    await reset_dut(dut)

    await ClockCycles(dut.clk, 20)
    cyc0 = await axi_read(dut, CSR_PERF_CYCLE_LO)
    await ClockCycles(dut.clk, 10)
    cyc1 = await axi_read(dut, CSR_PERF_CYCLE_LO)

    assert cyc0 > 0,    f"[FAIL] PERF_CYCLE_LO is 0 after 20 cycles"
    assert cyc1 > cyc0, f"[FAIL] PERF_CYCLE_LO not increasing: {cyc0} -> {cyc1}"
    dut._log.info(f"[PASS] test_05_perf_counter_increments: cyc0={cyc0} cyc1={cyc1}")


# ---------------------------------------------------------------------------
# TEST 6 — Interrupt low when not started
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_06_interrupt_low_when_idle(dut):
    """Interrupt must remain low while TPU has never been started."""
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    await reset_dut(dut)

    for _ in range(30):
        await RisingEdge(dut.clk)
        assert int(dut.interrupt.value) == 0, \
            f"[FAIL] interrupt asserted unexpectedly while TPU idle"

    dut._log.info("[PASS] test_06_interrupt_low_when_idle")
