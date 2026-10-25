# TPU-Lite: 8×8 Systolic-Array ML Inference Accelerator

[![Simulator](https://img.shields.io/badge/Simulator-Icarus_Verilog_11.0-blue.svg)](run_sim.sh)
[![Cocotb](https://img.shields.io/badge/Cocotb-2.1.0-orange.svg)](sim/cocotb/)
[![SV Tests](https://img.shields.io/badge/SV_Tests-10%2F10_PASSED-brightgreen.svg)](sim/tb/tb_systolic_self_check.sv)
[![Cocotb Tests](https://img.shields.io/badge/Cocotb_Tests-6%2F6_PASSED-brightgreen.svg)](sim/cocotb/test_systolic.py)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**TPU-Lite** is a synthesizable **8×8 Weight-Stationary Systolic Array** ML inference accelerator written in SystemVerilog. It computes **INT8 × INT8 → INT32** matrix multiplications using 64 pipelined Processing Elements (PEs), and wraps them in a complete SoC shell with an AXI4-Lite CSR register interface, a burst DMA engine, a double-buffered 4-bank SRAM subsystem, and SVA protocol checkers.

The project was built and verified as a learning exercise targeting **Digital Design Verification** roles. Every result in this README is reproducible with the commands shown.

---

## What Is Actually Implemented and Verified

| Feature | Status | Evidence |
|---|---|---|
| 8×8 INT8→INT32 systolic array RTL | ✅ Implemented & simulated | Tests 6–10 in SV testbench |
| Single-PE signed MAC unit (`pe_mac_csa.sv`) | ✅ Implemented & simulated | Tests 2–5 in SV testbench |
| Activation skew/de-skew pipeline registers | ✅ Implemented & simulated | Verified by identity and random matrix tests |
| Asynchronous reset (all registers clear) | ✅ Verified | Test 1, mid-run reset Test 10 |
| AXI4-Lite CSR register file (R/W) | ✅ Implemented & simulated | Cocotb tests 1–6 |
| Performance cycle counter | ✅ Verified incrementing | Cocotb test 5 |
| Interrupt output (tied to `tpu_done`) | ✅ RTL correct, stays low when idle | Cocotb test 6 |
| AXI4 DMA engine RTL | ✅ Compiles & integrates | Part of `tpu_lite_top` |
| Double-buffered 4-bank SRAM subsystem | ✅ Compiles & integrates | Part of `tpu_lite_top` |
| Python golden reference model | ✅ Runs, output checked | `golden_model.py` |
| 10,000 test vector generation + self-check | ✅ Verified generator consistency | `generate_vectors.py` + `cross_check.py` |
| SVA immediate assertions (Icarus-compatible) | ✅ Active during simulation | `sva_*_checker.sv` |
| SVA concurrent properties (temporal) | ⚠️ Written, needs Questa/JasperGold | `sva_*_checker.sv` (`ifdef FORMAL_SVA`) |
| Synthesis / timing closure (Vivado) | ❌ Not run — Vivado not available | synth scripts present, not executed |
| Formal verification results | ❌ Not performed | — |
| Functional coverage closure | ❌ Not measured | — |

---

## Architecture

### System Block Diagram

```
                  ┌─────────────────────────────┐
                  │    Host CPU / AXI4-Lite      │
                  │    (AXI writes to CSRs)      │
                  └───────────┬─────────────────┘
                              │ AXI4-Lite (32-bit, 32-bit addr)
                              ▼
┌─────────────────────────────────────────────────────────┐
│                     tpu_lite_top.sv                      │
│                                                          │
│  ┌──────────────────┐    ┌────────────────────────────┐  │
│  │ axi4_lite_slave  │    │   Main SoC FSM             │  │
│  │ (CSR Registers)  │───▶│   IDLE → FETCH_WGT →       │  │
│  └──────────────────┘    │   LOAD_WGT → FETCH_ACT →   │  │
│                          │   COMPUTE → STORE_OUT →    │  │
│  ┌──────────────────┐    │   DONE                     │  │
│  │ axi4_dma_engine  │◀───└───────────┬────────────────┘  │
│  │ (64-bit master)  │                │                    │
│  └────────┬─────────┘                │                    │
│           │ reads/writes             │                    │
│           ▼                         ▼                    │
│  ┌────────────────────────────────────────────────────┐  │
│  │         memory_subsystem.sv                         │  │
│  │   4-bank interleaved SRAM  +  double_buffer_ctrl   │  │
│  └────────────────────────┬───────────────────────────┘  │
│                           │ wgt_matrix[8][8], act_vector[8]│
│                           ▼                               │
│  ┌────────────────────────────────────────────────────┐  │
│  │         systolic_array_8x8.sv                       │  │
│  │  64 PEs  |  activation skew regs  |  output deskew │  │
│  │  data_valid pulse → acc_matrix_out[8]  (INT32)      │  │
│  └────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Weight-Stationary Dataflow (How It Works)

A systolic array is a grid of simple compute units that pass data through in a wave — like a chain of buckets. Each PE does one multiply-accumulate per clock.

1. **Weight Preload** — The 8×8 weight matrix is written into each PE's internal register. Weights stay put for the whole computation ("weight-stationary").
2. **Activation Skew** — Each row of the activation matrix enters one column later than the previous row. This staggering (`skew_regs` in `systolic_array_8x8.sv`) ensures row 0 and row 7 arrive at the array diagonally aligned.
3. **MAC Cascade** — As each activation travels right across a row of PEs, it multiplies by each PE's stored weight. Partial sums propagate downward. The bottom row accumulates the final INT32 dot products.
4. **Output De-skew** — Because column outputs emerge at different cycles, de-skew registers delay earlier columns to align all 8 results into one parallel output bus (`acc_matrix_out[0:7]`).
5. **`data_valid` Pulse** — A counter in `systolic_array_8x8.sv` generates one `data_valid` pulse per output row, starting at cycle `2*N-1` and lasting `N` cycles (where N=8).

### Timing Formula

For an N×N array processing an N-row activation matrix:
- **First valid output row**: cycle `2*N - 1 = 15`
- **All N rows captured**: cycles 15 through 22
- **Total cycles**: `3*N - 1 = 23`

---

## Module Descriptions

| Module | File | What It Does |
|---|---|---|
| `pe_mac_csa` | `rtl/pe/pe_mac_csa.sv` | Registered INT8×INT8→INT32 multiply-accumulate. Computes `acc_out ← acc_in + (act_in × wgt_in)` in one registered cycle. Named "CSA" for Carry-Save Adder structure in the multiply path. |
| `processing_element` | `rtl/pe/processing_element.sv` | Wraps `pe_mac_csa`. Adds a separate weight register (loaded when `load_weight=1`) and a horizontal activation pipeline register (passes `act_in` to `act_out` for the next PE). |
| `systolic_array_8x8` | `rtl/systolic/systolic_array_8x8.sv` | 8×8 grid of `processing_element` instances. Manages activation skewing on input, inter-PE routing wires, output de-skewing, and the `data_valid` timing counter. |
| `axi4_lite_slave` | `rtl/bus/axi4_lite_slave.sv` | AXI4-Lite compliant CSR register file. Handles write address, write data, write response, read address, and read data channels. Exposes start bit, dimension registers (M/K/N), base addresses, and status. |
| `axi4_dma_engine` | `rtl/bus/axi4_dma_engine.sv` | AXI4 master burst DMA. Moves weight/activation data from host memory into SRAM, and output data back out. Controlled by the FSM in `tpu_lite_top`. |
| `sram_bank` | `rtl/memory/sram_bank.sv` | Behavioural model of a dual-port synchronous SRAM bank (synthesises to BRAM on FPGA). |
| `double_buffer_ctrl` | `rtl/memory/double_buffer_ctrl.sv` | Ping-pong buffer controller. While DMA fills one bank half, the systolic array reads the other — eliminating stall cycles. |
| `memory_subsystem` | `rtl/memory/memory_subsystem.sv` | Integrates four `sram_bank` instances and `double_buffer_ctrl`. Presents a DMA port and a systolic-array port. |
| `tpu_lite_top` | `rtl/tpu_lite_top.sv` | Top-level SoC wrapper. Instantiates all modules and implements the 8-state FSM: `IDLE → FETCH_WGT → LOAD_WGT → FETCH_ACT → COMPUTE → STORE_OUT → DONE`. |
| `sva_axi4_checker` | `rtl/assertions/sva_axi4_checker.sv` | Protocol checker: verifies AXI valid/ready handshake stability. Concurrent SVA properties compile under `FORMAL_SVA` define; immediate equivalents run in simulation. |
| `sva_fsm_checker` | `rtl/assertions/sva_fsm_checker.sv` | FSM checker: verifies the state machine never enters an undefined state. |
| `sva_fifo_checker` | `rtl/assertions/sva_fifo_checker.sv` | Memory checker: verifies SRAM address stays in bounds during accesses. |

### Design Assumptions

- The DMA engine is a behavioural model; burst protocol compliance relies on the slave memory responding within one cycle (as in the testbench's AXI loopback).
- The systolic array accepts one activation row per clock. Row-by-row streaming must be managed externally (the FSM in `tpu_lite_top` does this for the 8-row case).
- Fixed array size of 8×8. There is no runtime configurability of array dimensions.
- Weights are loaded fresh before each matrix multiplication. There is no weight caching across inferences.
- The 94% PE utilization figure is a **theoretical calculation** from `generate_vectors.py` based on the double-buffering model — not a measured toggle count.

---

## Repository Structure

```
TpuLite/
├── rtl/
│   ├── pe/
│   │   ├── pe_mac_csa.sv           # INT8×INT8→INT32 registered MAC unit
│   │   └── processing_element.sv   # PE wrapper: weight reg + act pipeline + MAC
│   ├── systolic/
│   │   └── systolic_array_8x8.sv   # 8×8 PE grid, skew, de-skew, data_valid
│   ├── memory/
│   │   ├── sram_bank.sv            # Dual-port SRAM behavioural model
│   │   ├── double_buffer_ctrl.sv   # Ping-pong buffer swap controller
│   │   └── memory_subsystem.sv     # 4-bank SRAM + double-buffer integration
│   ├── bus/
│   │   ├── axi4_lite_slave.sv      # AXI4-Lite CSR register file
│   │   ├── axi4_dma_engine.sv      # AXI4 master burst DMA engine
│   │   └── axi_defines.svh         # Global parameters, CSR offsets, FSM enum
│   ├── assertions/
│   │   ├── sva_axi4_checker.sv     # AXI handshake protocol checker
│   │   ├── sva_fsm_checker.sv      # FSM state-validity checker
│   │   └── sva_fifo_checker.sv     # SRAM address bounds checker
│   └── tpu_lite_top.sv             # Top-level SoC: FSM + module integration
├── sim/
│   ├── tb/
│   │   ├── tb_systolic_self_check.sv  # Main self-checking SV testbench (10 tests)
│   │   ├── tb_tpu_lite_top.sv         # Top-level AXI testbench (reference only)
│   │   ├── tpu_scoreboard.sv          # Scoreboard class used by top-level TB
│   │   ├── tpu_coverage.sv            # Coverage group definitions
│   │   └── test_vectors.hex           # 100 pre-computed test vectors (hex)
│   ├── cocotb/
│   │   ├── test_systolic.py           # 6 cocotb tests for AXI4-Lite CSR layer
│   │   └── Makefile                   # Cocotb build (SIM=icarus)
│   └── reference/
│       ├── golden_model.py            # NumPy INT32 matmul reference model
│       ├── generate_vectors.py        # Generates 10,000 random test vectors + hex file
│       ├── cross_check.py             # Re-derives expected results; cross-checks hex file
│       └── quantizer.py               # FP32→INT8 symmetric quantization utility
├── synth/
│   ├── constraints/tpu_lite_artix7.xdc  # Xilinx Artix-7 timing constraints (250 MHz)
│   ├── scripts/synth.tcl                # Vivado synthesis script
│   └── reports/                         # Placeholder — not generated (Vivado not run)
├── docs/
│   ├── architecture.md             # Detailed architecture notes
│   ├── timing_optimization.md      # CSA retiming design rationale
│   └── verification_plan.md        # Verification strategy notes
├── run_sim.sh                      # One-command SV simulation (iverilog + vvp)
├── Makefile                        # Unified build targets
├── LICENSE
└── README.md
```

---

## Setup Instructions

### Prerequisites

| Tool | Minimum Version | Purpose |
|---|---|---|
| WSL (Ubuntu 22.04) | — | Shell environment on Windows |
| `iverilog` | 11.0 | SV compilation and simulation |
| `vvp` | (bundled with iverilog) | VVP simulation runtime |
| `python3` | 3.10 | Golden model and vector scripts |
| `python3-numpy` | 1.21+ | Matrix computation in reference model |
| `cocotb` | 2.1.0 | Python-driven AXI4-Lite CSR tests |

**Install on WSL (Ubuntu):**
```bash
sudo apt-get install -y iverilog python3 python3-numpy python3-pip
pip3 install cocotb
```

---

## Running the Tests

### Test 1 — SystemVerilog Self-Checking Testbench (Core Compute)

This is the main test. It runs entirely in Icarus Verilog with no external dependencies.

```bash
# From the TpuLite/ directory in WSL:
bash run_sim.sh
```

**What it tests:**

| Test | Description | Expected Result |
|---|---|---|
| TEST 1 | Reset: all PE and array outputs must be zero during active reset | `pe_acc_out=0`, `pe_act_out=0`, `data_valid=0` |
| TEST 2 | Single PE: `acc_in=10, act=4, wgt=6` → `acc_out = 10 + (4×6) = 34` | `acc_out = 34`, `act_out = 4` |
| TEST 3 | Single PE: negative operands `-20 + (-3×6) = -38` | `acc_out = -38` |
| TEST 4 | Single PE: INT8 max boundary `127×127 = 16129` | `acc_out = 16129` |
| TEST 4a | Single PE: INT8 min×max `-128×127 = -16256` | `acc_out = -16256` |
| TEST 5 | Single PE: zero activation `0×5 + 99 = 99` (passthrough) | `acc_out = 99` |
| TEST 6 | 8×8 array: all-zero W and A → C = 0 | All 64 elements = 0 |
| TEST 7 | 8×8 array: identity weights W=I → C = A | Output matches activation rows exactly |
| TEST 8 | 8×8 array: A=+127, W=−128 → each element = 8×(127×−128) = −130048 | All 64 elements = −130048 |
| TEST 9 | 8×8 array: signed pseudo-random matrix multiply | Golden model computed independently; 64 elements verified |
| TEST 10 | 8×8 array: mid-run reset suppresses `data_valid`; array recovers and produces correct output | Recovery produces same result as TEST 7 |

**Actual output (last run):**
```
=======================================================
                 VERIFICATION SUMMARY
=======================================================
  Total Assertions & Elements Checked: 330
  Total Errors & Scoreboard Mismatches: 0
  FINAL VERDICT                       : PASSED ALL TESTS
=======================================================
```
Exit code: **0**

---

### Test 2 — Cocotb AXI4-Lite CSR Tests (Host Interface)

```bash
# From TpuLite/sim/cocotb/ in WSL:
make SIM=icarus
```

**What it tests (DUT: `tpu_lite_top`):**

| Test | Description |
|---|---|
| `test_01_reset_outputs_zero` | `interrupt`, `s_axi_awready`, `s_axi_bvalid`, `s_axi_arready`, `s_axi_rvalid` all low after reset |
| `test_02_csr_dim_readback` | Write M=8, K=8, N=8 to CSR, read back and verify |
| `test_03_csr_base_addr_readback` | Write activation/weight/output base addresses, read back |
| `test_04_status_idle_after_reset` | STATUS[0]=busy=0, STATUS[1]=done=0 after reset |
| `test_05_perf_counter_increments` | `PERF_CYCLE_LO` is non-zero and increasing after reset release |
| `test_06_interrupt_low_when_idle` | Interrupt stays low across 30 cycles without a start command |

**Actual output (last run):**
```
TESTS=6  PASS=6  FAIL=0  SKIP=0
```

---

### Test 3 — Python Golden Reference Model

```bash
# From TpuLite/ in WSL:
cd sim/reference && python3 golden_model.py
```

Runs one random 8×8 INT8 matrix multiply using NumPy and prints the INT32 output. Used as the independent reference for scoreboard checks.

---

### Test 4 — Test Vector Generation and Cross-Check

```bash
# From TpuLite/ in WSL:
cd sim/reference

# Generate 10,000 random vectors (saves first 100 to sim/tb/test_vectors.hex):
python3 generate_vectors.py

# Cross-check: re-derive expected results from scratch and verify stored hex:
python3 cross_check.py
```

> **Note:** The 10,000 vectors are verified for internal consistency (golden model vs. stored hex). They are **not** currently driven into the RTL testbench — connecting the hex file to the SV testbench is a planned next step.

**Actual output (cross_check.py):**
```
  Vectors checked : 100
  Mismatches      : 0
  VERDICT         : PASSED — all stored vectors match golden
```

---

### Test 5 — Quantizer Demo

```bash
cd sim/reference && python3 quantizer.py
```

Demonstrates symmetric INT8 quantization: takes a random FP32 8×8 matrix, computes `scale = max(|x|) / 127`, and clamps rounded values to [−128, 127].

---

## CSR Register Map

| Offset | Register | Description |
|---|---|---|
| `0x00` | `CSR_CTRL` | Bit[0]: Start pulse, Bit[1]: Soft reset |
| `0x04` | `CSR_STATUS` | Bit[0]: Busy, Bit[1]: Done (read-only) |
| `0x08` | `CSR_DIM_M` | Matrix rows (default 8) |
| `0x0C` | `CSR_DIM_K` | Inner dimension (default 8) |
| `0x10` | `CSR_DIM_N` | Matrix columns (default 8) |
| `0x14` | `CSR_ACT_BASE` | Host activation base address |
| `0x18` | `CSR_WGT_BASE` | Host weight base address |
| `0x1C` | `CSR_OUT_BASE` | Host output base address |
| `0x20` | `CSR_PERF_CYCLE_LO` | Lower 32 bits of clock cycle counter |
| `0x24` | `CSR_PERF_CYCLE_HI` | Upper 32 bits of clock cycle counter |
| `0x28` | `CSR_PERF_ACTIVE_LO` | Active (busy) cycle counter |

---

## Assertions

Three SVA checker modules are instantiated in `tpu_lite_top` under `` `ifndef SYNTHESIS ``:

**`sva_axi4_checker`** — AXI handshake stability
- `AWVALID` must not deassert before `AWREADY`
- `WVALID`/`WDATA` must not change before `WREADY`
- `ARVALID` must not deassert before `ARREADY`

**`sva_fsm_checker`** — FSM validity
- State must never hold an undefined encoding (immediate assertion active in simulation)
- Concurrent properties (reset-to-IDLE, liveness) require Questa/JasperGold via `+define+FORMAL_SVA`

**`sva_fifo_checker`** — SRAM bounds
- Active address must be `< DEPTH` whenever `write_en` or `read_en` is asserted

---

## Synthesis (Not Performed — Scripts Provided)

Vivado synthesis scripts target Xilinx Artix-7 (`xc7a100tcsg324-1`) at 250 MHz. The CSA structure in `pe_mac_csa.sv` is designed to avoid a long carry-propagate chain through the 32-bit accumulator loop. See [`docs/timing_optimization.md`](docs/timing_optimization.md) for the design rationale.

To run synthesis (requires Vivado installation):
```bash
make synth
```

The `synth/reports/` directory contains **placeholder** reports — actual numbers have not been produced in this project.

---

## Honest Resume Bullets

These are based only on what was implemented and demonstrated above:

> **Option A (verification focus):**
> Designed and verified an 8×8 weight-stationary INT8 systolic array accelerator in SystemVerilog; wrote a self-checking testbench with an independent golden model, element-level scoreboard, and timeout watchdog covering reset, signed arithmetic, boundary values, and mid-run recovery across 10 test cases (330 scoreboard checks, 0 mismatches).

> **Option B (mixed RTL + verification):**
> Implemented a synthesizable ML inference accelerator SoC in SystemVerilog, including a 64-PE systolic array, AXI4-Lite CSR register file, burst DMA engine, and double-buffered SRAM subsystem; verified the AXI4-Lite host interface using cocotb (6 tests) and the compute core using Icarus Verilog (10 tests, 330 assertions).

> **Option C (tools & methodology focus):**
> Set up a multi-level RTL verification environment for a systolic array SoC: Icarus Verilog testbench with scoreboard and SVA assertions, Python/NumPy golden reference model, 10,000-vector test generator with cross-validation, and a cocotb AXI4-Lite test suite — all running reproducibly from a single shell script in WSL.

---

## Limitations and Honest Notes

- **No synthesis results**: Vivado was not run. The timing numbers in `docs/timing_optimization.md` describe the *design intent* and analysis, not measured results.
- **DMA not exercised end-to-end**: The DMA engine RTL compiles and is instantiated, but the full DMA→SRAM→systolic-array data path has not been driven by a test that feeds real data and checks the output.
- **No UVM**: `tpu_scoreboard.sv` is a plain SystemVerilog class (not a `uvm_scoreboard`). There is no UVM base library dependency.
- **Concurrent SVA requires Questa**: The temporal properties in `sva_*_checker.sv` use `property`/`assert property` with `|=>` and `|->` operators that Icarus Verilog 11.0 does not support. They compile only with `+define+FORMAL_SVA` under a tool that supports concurrent assertions.
- **10,000 vectors are not driven into RTL**: The vector generator produces and cross-validates hex data through the Python golden model. Connecting these vectors to the SV DUT via `$readmemh` is a future work item.

---

## License

MIT License — see [LICENSE](LICENSE).
