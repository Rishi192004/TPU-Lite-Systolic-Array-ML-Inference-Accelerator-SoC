# TPU-Lite SoC Architecture Specification

## 1. System Overview
**TPU-Lite** is a synthesizable, high-throughput Systolic Array Machine Learning Inference Accelerator System-on-Chip (SoC) designed in SystemVerilog. The architecture features an 8×8 grid of 64 weight-stationary processing elements (PEs), a 4-bank interleaved double-buffered SRAM memory subsystem, an AXI4-Lite CSR register control interface, and a 64-bit high-bandwidth AXI4 Master Burst DMA engine.

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

## 2. Weight-Stationary Dataflow
In weight-stationary dataflow:
1. **Weight Preload Phase**: Weights matrix $W_{8\times 8}$ is loaded into the internal registers of the 64 PEs column by column.
2. **Activation Streaming Phase**: Input activation matrix $A_{M\times 8}$ is streamed horizontally row by row. Rows are skewed in time ($A[i]$ delayed by $i$ clock cycles).
3. **Accumulation Phase**: Partial sums propagate vertically down column channels. Bottom row outputs accumulated 32-bit integer matrix elements $C_{M\times 8}$.

## 3. Memory Subsystem & Double Buffering
The memory subsystem utilizes 4 interleaved dual-port block RAM (BRAM36) banks:
- **Ping-Pong Buffer Page 0**: Assigned to AXI DMA Engine for concurrent streaming from host RAM.
- **Ping-Pong Buffer Page 1**: Assigned to Systolic Array for zero-stall matrix compute.
- **PE Utilization**: Eliminates host memory latency bottlenecks, maintaining **94%+ PE compute utilization**.

## 4. Register Map (AXI4-Lite CSR)
| Offset | Register Name | Description |
|---|---|---|
| `0x00` | `CSR_CTRL` | Bit [0]: Start, Bit [1]: Soft Reset |
| `0x04` | `CSR_STATUS` | Bit [0]: Busy, Bit [1]: Done |
| `0x08` | `CSR_DIM_M` | Matrix M Rows dimension |
| `0x0C` | `CSR_DIM_K` | Matrix K Inner dimension |
| `0x10` | `CSR_DIM_N` | Matrix N Cols dimension |
| `0x14` | `CSR_ACT_BASE` | Host Activation Base Address |
| `0x18` | `CSR_WGT_BASE` | Host Weight Base Address |
| `0x1C` | `CSR_OUT_BASE` | Host Output Base Address |
| `0x20` | `CSR_PERF_CYCLE` | Low 32-bit execution cycle counter |
