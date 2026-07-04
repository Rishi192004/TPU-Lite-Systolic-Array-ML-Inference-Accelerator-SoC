# TPU-Lite: Systolic-Array ML Inference Accelerator SoC

[![Board Target](https://img.shields.io/badge/FPGA-Xilinx_Artix--7-00599C.svg)](synth/constraints/tpu_lite_artix7.xdc)
[![Clock Frequency](https://img.shields.io/badge/Clock-250_MHz-brightgreen.svg)](synth/reports/timing_summary.rpt)
[![Verification Status](https://img.shields.io/badge/Vectors-10%2C000%2B_PASSED-success.svg)](sim/reference/generate_vectors.py)
[![Assertions](https://img.shields.io/badge/SVA-Formal_Checked-blue.svg)](rtl/assertions/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**TPU-Lite** is a synthesizable, high-performance **8×8 Systolic Array Machine Learning Inference Accelerator System-on-Chip (SoC)** written in SystemVerilog. Built around a **weight-stationary INT8 dataflow**, the design integrates 64 retimed Processing Elements (PEs), a 4-bank double-buffered SRAM memory subsystem, an AXI4-Lite CSR register file, and a 64-bit high-bandwidth AXI4 Master Burst DMA engine.

Synthesized on Xilinx Artix-7 (XC7A100T) via Vivado at **250 MHz**, TPU-Lite resolves an initial **3.1 ns critical path timing violation** through **Carry-Save Adder (CSA) compressor tree insertion** and **register retiming**, achieving full timing closure with a positive Worst Negative Slack (+0.142 ns WNS).

---

## 🏛️ System Architecture

```
                  +-----------------------------------+
                  |        Host CPU / AXI Master      |
                  +-----------------------------------+
                                   | (AXI4-Lite CSRs)
                                   v
+-------------------------------------------------------------------+
| TPU-Lite SoC Top                                                 |
|                                                                   |
|  +-------------------+        +--------------------------------+  |
|  | AXI4 Burst DMA    |<------>| 4-Bank Interleaved SRAM        |  |
|  | Engine (64-bit)   |        | Double-Buffered Ping-Pong RAM  |  |
|  +-------------------+        +--------------------------------+  |
|                                                | (Activations/Wgt)|
|                                                v                  |
|                               +--------------------------------+  |
|                               | 8x8 Systolic Array Compute Core|  |
|                               | (64 Retimed CSA PEs @ 250 MHz) |  |
|                               +--------------------------------+  |
+-------------------------------------------------------------------+
```

### Key Highlights
- **8×8 Weight-Stationary Systolic Array**: 64 PEs processing INT8 weights and INT8 activations with 32-bit INT32 accumulation.
- **250 MHz Timing Closure**: Solved a 3.1 ns setup violation (-3.100 ns WNS baseline) using bitwise 3:2 Carry-Save Adders (CSA) and Vivado register retiming (`+0.142 ns WNS`).
- **Double-Buffered Memory Subsystem**: 4-bank interleaved SRAM with ping-pong buffering allowing concurrent DMA host streaming and systolic array computation, eliminating stall cycles and achieving **94%+ PE compute utilization**.
- **AXI4 High-Bandwidth Interface**: AXI4-Lite for CSR host control and 64-bit AXI4 Master DMA engine supporting burst lengths up to 256 beats.
- **Formal Property Checking (SVA)**: SystemVerilog Assertions verifying FSM state transitions, AXI4 handshake compliance, and buffer bounds.
- **Python Golden Reference & Quantization**: NumPy cycle-accurate reference model and automated test suite validating **10,000+ randomized matrix test vectors with zero mismatches**.

---

## ⚡ Critical Path Resolution & Retiming

| Parameter | Baseline Architecture | Retimed CSA Architecture |
|---|---|---|
| **Target Frequency** | 250 MHz | **250 MHz** |
| **Clock Period** | 4.000 ns | **4.000 ns** |
| **Data Path Delay** | 7.100 ns | **3.708 ns** |
| **Worst Negative Slack (WNS)** | -3.100 ns (VIOLATION) | **+0.142 ns (TIMING MET)** |
| **Throughput** | 16 GOPs | **32 GOPs** |

> For a complete architectural deep-dive into the CSA tree logic and pipeline stage balancing, read [`docs/timing_optimization.md`](docs/timing_optimization.md).

---

## 📊 Synthesis & Hardware Resource Breakdown

Synthesized for Xilinx Artix-7 (`xc7a100tcsg324-1`) via Vivado:

| Resource | Used | Available | Utilization |
|---|---|---|---|
| **Slice LUTs** | 4,820 | 63,400 | 7.6% |
| **Slice Flip-Flops** | 5,120 | 126,800 | 4.0% |
| **DSP48E1 Slices** | 64 | 240 | 26.6% |
| **BRAM Tile (BRAM36)** | 8 | 135 | 5.9% |

---

## 🧪 Verification & Coverage

The design was verified using a UVM-style SystemVerilog testbench connected to a Python NumPy cycle-accurate golden reference model:

- **10,000+ Randomized Test Vectors**: Including edge cases (all zeros, max/min INT8 values, alternating bit sign patterns).
- **Zero Mismatches**: Passed with 100% data integrity check.
- **SystemVerilog Assertions (SVA)**:
  - Protocol rules: `AWVALID`/`AWREADY`, `WVALID`/`WREADY`, `ARVALID`/`ARREADY`.
  - FSM safety: Deadlock detection & reset recovery checks.
  - Memory integrity: SRAM pointer bound checkers.

---

## 📁 Repository Structure

```
TPU-Lite/
├── rtl/                        # Synthesizable SystemVerilog Code
│   ├── pe/                     # Processing Element & Retimed CSA MAC
│   │   ├── pe_mac_csa.sv
│   │   └── processing_element.sv
│   ├── systolic/               # 8x8 Systolic Array Grid
│   │   └── systolic_array_8x8.sv
│   ├── memory/                 # Interleaved SRAM & Ping-Pong Controller
│   │   ├── sram_bank.sv
│   │   ├── double_buffer_ctrl.sv
│   │   └── memory_subsystem.sv
│   ├── bus/                    # AXI4-Lite CSR & AXI4 Master DMA Engine
│   │   ├── axi4_lite_slave.sv
│   │   ├── axi4_dma_engine.sv
│   │   └── axi_defines.svh
│   ├── assertions/             # SystemVerilog Assertions (SVA)
│   │   ├── sva_axi4_checker.sv
│   │   ├── sva_fsm_checker.sv
│   │   └── sva_fifo_checker.sv
│   └── tpu_lite_top.sv         # Top-Level SoC Wrapper
├── sim/                        # Verification & Testbenches
│   ├── tb/                     # SV / UVM Testbench & Scoreboard
│   │   ├── tb_tpu_lite_top.sv
│   │   ├── tpu_scoreboard.sv
│   │   └── tpu_coverage.sv
│   ├── cocotb/                 # Cocotb Python Framework
│   │   ├── test_systolic.py
│   │   └── Makefile
│   └── reference/              # Python Golden Model & Vector Gen
│       ├── golden_model.py
│       ├── quantizer.py
│       └── generate_vectors.py
├── synth/                      # Vivado Synthesis & Timing Reports
│   ├── constraints/
│   │   └── tpu_lite_artix7.xdc
│   ├── scripts/
│   │   ├── synth.tcl
│   │   └── run_vivado.bat
│   └── reports/
│       ├── timing_summary.rpt
│       └── utilization.rpt
├── docs/                       # Technical Documentation
│   ├── architecture.md
│   ├── timing_optimization.md
│   └── verification_plan.md
├── Makefile                    # Unified Build System
├── LICENSE                     # MIT License
└── README.md
```

---

## 🛠️ Quickstart & Reproduction

### 1. Test Golden Model & Generate 10,000+ Vectors
```bash
make vectors
```

### 2. Run Python Reference Model
```bash
make golden
```

### 3. Run Cocotb / SystemVerilog Simulation
```bash
make sim
```

### 4. Run Vivado Synthesis (Artix-7 @ 250 MHz)
```bash
make synth
```

---

## 📜 License
This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.
