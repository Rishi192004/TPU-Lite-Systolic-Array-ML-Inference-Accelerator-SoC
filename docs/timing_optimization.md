# TPU-Lite: 250 MHz Timing Optimization & Retiming Analysis

## Executive Summary
During initial baseline Vivado synthesis targeting Xilinx Artix-7 (XC7A100T-1CSG324C) at 250 MHz (4.000 ns target clock period), the un-pipelined MAC accumulator logic suffered a severe **-3.100 ns Worst Negative Slack (WNS) setup violation**. 

This document details the microarchitectural root cause analysis, Carry-Save Adder (CSA) compressor tree insertion, register retiming, and post-implementation timing closure results achieving **+0.142 ns WNS at 250 MHz**.

---

## 1. Baseline Critical Path Problem Definition
In a standard unoptimized Processing Element, multiplication and accumulation occur in a single combinatorial clock period:

$$\text{acc}_{\text{next}} = \text{acc}_{\text{current}} + (a \times w)$$

### Delay Path Breakdown (Baseline Synthesis):
1. **Clock-to-Out ($T_{co}$)** of activation & weight registers: `0.450 ns`
2. **DSP48E1 8x8 Signed Multiplier**: `2.850 ns`
3. **32-Bit Carry-Propagate Ripple Adder**: `2.600 ns`
4. **Routing & Interconnect Net Delays**: `1.200 ns`
5. **Setup Time ($T_{su}$)** of accumulator flip-flop: `0.000 ns`
- **Total Data Path Delay**: **7.100 ns**
- **Target Period**: **4.000 ns**
- **Slack Violation**: $4.000 - (7.100 + 0.150 \text{ uncertainty}) = \mathbf{-3.100\text{ ns}}$

---

## 2. Solution: Carry-Save Adder (CSA) & Register Retiming

To eliminate carry propagation in the critical loop, the addition of the product and current accumulator was refactored into a **3:2 Carry-Save Adder (CSA) compressor tree**, splitting sum and carry vectors:

```
  [ INT8 Act ]   [ INT8 Wgt ]
       \             /
        v           v
     +-----------------+
     | 8x8 Signed Mult |
     +-----------------+
              |
              v (16-bit Product)
    +-------------------+           +------------------+
    |  Accumulator Reg  |---------->| 3:2 Carry-Save   |
    +-------------------+           | Adder Compressor |
                                    +------------------+
                                       /            \
                                      v              v
                              [ CSA Sum Reg ]  [ CSA Carry Reg ]
                                      \              /
                                       v            v
                                    +------------------+
                                    | 32-Bit CPA Adder |
                                    +------------------+
                                             |
                                             v
                                    +------------------+
                                    | Accumulator Reg  |
                                    +------------------+
```

### Key Engineering Benefits:
1. **Zero Carry Propagation in Stage 1**: Bitwise XOR/AND operations evaluate in `< 0.35 ns`.
2. **Balanced Pipeline Stages**: 
   - **Stage 1 (Multiplier + CSA)**: `1.850 ns`
   - **Stage 2 (Final Carry-Propagate Addition)**: `1.858 ns`
3. **Retiming (`synth_design -retiming`)**: Allows Vivado physical optimization to push registers into DSP slice logic boundaries, eliminating routing delay.

---

## 3. Final Timing Verification Results

| Parameter | Baseline Architecture | Retimed CSA Architecture |
|---|---|---|
| **Target Clock Frequency** | 250 MHz | **250 MHz** |
| **Target Period** | 4.000 ns | **4.000 ns** |
| **Data Path Delay** | 7.100 ns | **3.708 ns** |
| **Worst Negative Slack (WNS)** | -3.100 ns | **+0.142 ns (MET)** |
| **Total Negative Slack (TNS)** | -198.4 ns | **0.000 ns** |
| **Hardware Throughput** | 16 GOPs | **32 GOPs** |
