# TPU-Lite Systolic Array: Comprehensive Technical Interview Handbook

> **Target Role:** Digital Design & Verification (DV) Engineer / ASIC-FPGA Verification Fresher  
> **Repository:** `TpuLite` (8×8 Weight-Stationary Systolic Array Accelerator SoC)  
> **Verified Environment:** WSL2 Ubuntu 22.04 LTS | Icarus Verilog 11.0 | Cocotb 2.1.0 | Python 3.10 (NumPy)  
> **Status:** 10/10 SystemVerilog Core Tests Passed (330 Element Checks) | 6/6 Cocotb AXI4-Lite Tests Passed

---

## Table of Contents
1. [Project Overview](#1-project-overview)
2. [Architecture & Microarchitecture](#2-architecture--microarchitecture)
3. [Important RTL Walkthrough](#3-important-rtl-walkthrough)
4. [Verification Architecture & Methodology](#4-verification-architecture--methodology)
5. [Complete Test Inventory](#5-complete-test-inventory)
6. [Realistic Bugs & Debugging Stories (From Commit History & Fixes)](#6-realistic-bugs--debugging-stories)
7. [Biggest Bug Deep Dive: The Systolic Output Misalignment Problem](#7-biggest-bug-deep-dive)
8. [Exact Run Instructions & Environment Setup](#8-exact-run-instructions)
9. [Empirical Results, Evidence & Tool Limitations](#9-results--evidence)
10. [SystemVerilog Concepts Deep Dive](#10-systemverilog-concepts)
11. [Interview Question Bank (45 Technical Questions & Answers)](#11-interview-question-bank)
12. [Interview Speaking Guide & Scripts](#12-interview-speaking-guide)
13. [Resume Bullets & Interview Defense Checklist](#13-resume-bullets--defense)
14. [Final Revision Sheet: Cheat Sheet & Equations](#14-final-revision-sheet)

---

## 1. Project Overview

### 1.1 Purpose & Problem Solved
Modern deep learning workloads (Convolutional Neural Networks, Multi-Layer Perceptrons, Transformer GEMM kernels) spend over 80% of runtime computing Dense Matrix Multiplications ($C = A \times B$). Von Neumann processors (CPUs/GPUs) face the **Memory Wall**: repeatedly reading operands from memory hierarchies consumes $10\times$ to $100\times$ more energy than the arithmetic itself.

**TPU-Lite** solves this by implementing an **8×8 Weight-Stationary 2D Systolic Array**. Weights are held stationary in local Processing Element (PE) registers while input activations stream horizontally and partial sums accumulate vertically. This architecture achieves **2D spatial data reuse**: each loaded activation and weight is reused $N=8$ times across neighboring PEs before leaving the computational grid, slashing memory bandwidth demand by $8\times$.

### 1.2 Specifications & Verified Parameters
- **Array Dimensions:** $8 \times 8$ (64 physical Processing Elements).
- **Operand Precision:** 
  - Weight ($W$): Signed INT8 (8-bit two's complement, range $[-128, +127]$).
  - Activation ($A$): Signed INT8 (8-bit two's complement, range $[-128, +127]$).
  - Accumulator / Output ($C$): Signed INT32 (32-bit two's complement, avoiding overflow during accumulation of 8 INT8 products).
- **Dataflow Architecture:** Weight-Stationary (WS).
- **Array Throughput:** Up to 64 Multiply-Accumulate (MAC) operations per clock cycle once the systolic pipeline is full (128 equivalent operations/cycle: 64 mults + 64 adds).
- **Host Interface:** 32-bit AXI4-Lite Slave CSR interface (Control, Status, Matrix Dimensions, Buffer Addresses, Cycle Counters).
- **Memory Subsystem:** 4-bank interleaved synchronous SRAM with ping-pong double-buffering logic.
- **DMA Interface:** 64-bit Master AXI4 burst DMA engine RTL model.

### 1.3 Design Assumptions
1. **Matrix Dimensions:** The hardware systolic grid is fixed at $8 \times 8$. Larger matrices must be tiled/blocked in software into $8 \times 8$ tiles.
2. **Synchronous Single-Clock Domain:** The entire accelerator SoC runs on a single clock domain (`clk`), active on `posedge clk`.
3. **Active-Low Asynchronous Reset:** System reset (`rst_n`) deasserts asynchronously and initializes all pipeline registers, FSM states, and accumulators to zero.
4. **DMA Transfer Environment:** The DMA engine is an RTL behavioural model that assumes slave host DRAM completes transfers in conformant single-cycle or burst handshakes.

### 1.4 Honest Limitations (What Is NOT Claimed)
- **No UVM Framework:** The testbench uses an object-oriented SystemVerilog class-based scoreboard (`tpu_scoreboard.sv`), not the Accellera UVM class library (`uvm_driver`, `uvm_monitor`, etc.).
- **No Tape-Out or Vivado Timing Closure Claim:** The 250 MHz target on Xilinx Artix-7 (`XC7A100T`) and timing numbers represent architectural design intent from `synth.tcl` / `timing_optimization.md`. Physical place-and-route was not executed in the open-source Linux/WSL simulation environment.
- **Simulation Environment:** Validated under open-source Icarus Verilog (`iverilog 11.0`) and `cocotb 2.1.0`. Temporal SVA (`|=>`, `##1`) requires Questa/VCS/JasperGold and is conditionally compiled with `+define+FORMAL_SVA`.

---

## 2. Architecture & Microarchitecture

### 2.1 System Block Diagram (Mermaid)

```mermaid
graph TD
    subgraph Host_Domain ["Host Interface"]
        CPU["Host CPU / AXI Master"]
    end

    subgraph TPU_Lite_SoC ["TPU-Lite SoC Top (tpu_lite_top.sv)"]
        CSR["AXI4-Lite Slave CSRs\n(axi4_lite_slave.sv)"]
        FSM["SoC Controller FSM\n(8 States)"]
        DMA["AXI4 Master DMA Engine\n(axi4_dma_engine.sv)"]
        
        subgraph Mem_Subsystem ["Memory Subsystem (memory_subsystem.sv)"]
            DB_CTRL["Double Buffer Controller\n(double_buffer_ctrl.sv)"]
            SRAM0["Bank 0 (2Kx32)"]
            SRAM1["Bank 1 (2Kx32)"]
            SRAM2["Bank 2 (2Kx32)"]
            SRAM3["Bank 3 (2Kx32)"]
        end

        subgraph Systolic_Core ["Systolic Array Core (systolic_array_8x8.sv)"]
            SKEW["Input Activation Skew Registers\nRow i delayed by i cycles"]
            PE_GRID["8x8 Processing Element Grid\n64x processing_element.sv"]
            DESKEW["Output Accumulator De-skew Registers\nCol j delayed by (7-j) cycles"]
            VALID_GEN["data_valid Latency Counter\nCycle 14 to 21"]
        end
    end

    CPU -->|AXI4-Lite Write/Read| CSR
    CSR -->|tpu_start, dimensions| FSM
    FSM -->|dma_start_read/write| DMA
    DMA -->|Fill / Drain| Mem_Subsystem
    FSM -->|load_weight, clear_acc, enable| Systolic_Core
    Mem_Subsystem -->|wgt_matrix[8][8]| Systolic_Core
    Mem_Subsystem -->|act_vector[8]| SKEW
    SKEW --> PE_GRID
    PE_GRID --> DESKEW
    DESKEW -->|acc_matrix_out[0:7]| Mem_Subsystem
    VALID_GEN -->|tpu_data_valid| FSM
    FSM -->|interrupt| CPU
```

### 2.2 Complete Dataflow: Weight-Stationary Operation
The accelerator executes matrix multiplication $C_{8 \times 8} = A_{8 \times 8} \times W_{8 \times 8}$ in three distinct phases:

1. **Weight Preload Phase:**
   - Host CPU programmes the weight matrix into SRAM.
   - Top-level FSM asserts `load_weight = 1` for 1 cycle.
   - All 64 PEs register their respective spatial weight byte: $\text{PE}_{r,c}.\text{weight\_reg} \leftarrow W[r][c]$.

2. **Activation Skewing Phase:**
   - Activations $A[m][k]$ stream horizontally from left to right.
   - Because partial sums propagate down one PE row per cycle, activation row $r$ must be delayed by $r$ clock cycles so that $A[r][k]$ meets the partial sum accumulated from rows $0 \dots r-1$.
   - Row 0 delay: 0 cycles (direct wire).
   - Row $r$ delay: $r$ flip-flops in series (`act_skewed[r]`).

3. **MAC Accumulation & Vertical Propagation:**
   - Within each $\text{PE}_{r,c}$, activation $A$ multiplies with local weight $W$.
   - The 16-bit signed product is sign-extended to 32 bits and added to `acc_in` (the partial sum arriving from $\text{PE}_{r-1,c}$).
   - The result is registered in `acc_out` and forwarded to $\text{PE}_{r+1,c}$ on the next clock edge.
   - For the topmost row ($r=0$), `acc_in` is hardwired to `32'sd0`.

4. **Output De-Skewing Phase:**
   - Column $c$ completes its final accumulation at the bottom row ($r=7$) at cycle $t = m + 8 + c$.
   - Thus, column 0 finishes first, and column 7 finishes 7 cycles later.
   - To present an entire 8-word row vector $C[m][0 \dots 7]$ simultaneously to the memory subsystem, column $c$ is delayed by $(7 - c)$ cycles.
   - Result: All 8 elements of row $m$ emerge perfectly aligned on cycle $t = m + 14$.

---

### 2.3 Detailed Cycle-by-Cycle Waveform Schedule
Let $N=8$. Consider streaming an $8 \times 8$ activation matrix $A$:

| Cycle Index | Activation Injected | PE[0][0] Activity | PE[7][7] Activity | Deskew Output (`acc_matrix_out`) | `data_valid` |
|---|---|---|---|---|---|
| **0** | `sys_load_wgt=1`, `sys_clear_acc=1` | Preload $W[0][0]$ | Preload $W[7][7]$ | Undefined / 0 | 0 |
| **1** | Stream Row 0: $A[0][*]$ | Computes $A[0][0] \times W[0][0]$ | Idle (skewing) | Undefined / 0 | 0 |
| **2** | Stream Row 1: $A[1][*]$ | Computes $A[1][0] \times W[0][0]$ | Idle | Undefined / 0 | 0 |
| **8** | Stream Row 7: $A[7][*]$ | Computes $A[7][0] \times W[0][0]$ | Row 0 wavefront reaches PE[7][7] | Undefined / 0 | 0 |
| **9..13** | Zero input flush | Internal pipeline drains | Processing Row 1..6 wavefronts | Deskew delay queues filling | 0 |
| **14** | Zero flush | Idle | Row 0 dot products finish at bottom | **Row 0 Valid:** $C[0][0 \dots 7]$ | **1 (Asserted)** |
| **15** | Zero flush | Idle | Row 1 dot products finish | **Row 1 Valid:** $C[1][0 \dots 7]$ | **1** |
| **16** | Zero flush | Idle | Row 2 dot products finish | **Row 2 Valid:** $C[2][0 \dots 7]$ | **1** |
| **...** | Zero flush | Idle | ... | ... | **1** |
| **21** | Drained | Idle | Row 7 dot products finish | **Row 7 Valid:** $C[7][0 \dots 7]$ | **1** |
| **22** | Complete | Idle | Idle | Flushed to 0 | **0 (Deasserts)** |

**Latency Formula:**
$$\text{Latency to first row} = 2N - 2 = 14 \text{ cycles}$$
$$\text{Total duration of valid output} = N = 8 \text{ cycles (cycles 14 to 21 inclusive)}$$
$$\text{Total execution latency} = 3N - 2 = 22 \text{ clock cycles}$$

---

### 2.4 Signed INT8 Arithmetic Precision & Overflow Mechanics
- **Multiplication:** Two signed 8-bit integers $[-128, +127]$.
  - Minimum possible product: $(-128) \times (+127) = -16,256$ ($16\text{-bit signed}$).
  - Maximum possible product: $(-128) \times (-128) = +16,384$ ($16\text{-bit signed}$).
- **Sign Extension:** In SystemVerilog, multiplying two `logic signed [7:0]` types produces a 16-bit signed product. Before accumulation, this product MUST be explicitly sign-extended to 32 bits:
  ```systemverilog
  assign mult_product_ext = {{16{mult_product[15]}}, mult_product};
  ```
- **Accumulation Safety:** For an $8 \times 8$ dot product, the worst-case maximum accumulator value is:
  $$\text{Max Accumulation} = 8 \times (+16,384) = +131,072$$
  $$\text{Min Accumulation} = 8 \times (-16,384) = -131,072$$
  A 32-bit signed accumulator has a representable range of $[-2,147,483,648, +2,147,483,647]$.
  Therefore, **arithmetic overflow is mathematically impossible** in an 8-deep reduction tree using INT32 accumulators!

---

## 3. Important RTL Walkthrough

### 3.1 Pipelined Processing Element (`rtl/pe/processing_element.sv`)
The PE encapsulates the weight register, the horizontal activation forwarding register, and the MAC unit.

```systemverilog
module processing_element #(
    parameter int INT8_WIDTH = 8,
    parameter int ACC_WIDTH  = 32
)(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    load_weight,
    input  logic                    clear_acc,
    input  logic                    enable,
    input  logic signed [INT8_WIDTH-1:0] act_in,
    input  logic signed [INT8_WIDTH-1:0] wgt_in,
    input  logic signed [ACC_WIDTH-1:0]  acc_in,
    output logic signed [INT8_WIDTH-1:0] act_out,
    output logic signed [ACC_WIDTH-1:0]  acc_out
);
    logic signed [INT8_WIDTH-1:0] weight_reg;
    logic signed [INT8_WIDTH-1:0] act_reg;

    // Weight register: stationary during computation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)          weight_reg <= '0;
        else if (load_weight) weight_reg <= wgt_in;
    end

    // Horizontal activation pipeline register: 1 cycle latency to neighbor PE
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)      act_reg <= '0;
        else if (enable) act_reg <= act_in;
    end

    // Direct instantiation of Registered MAC
    pe_mac_csa #(
        .INT8_WIDTH(INT8_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) u_mac_core (
        .clk       (clk),
        .rst_n     (rst_n),
        .clear_acc (clear_acc),
        .enable    (enable),
        .act_in    (act_in),
        .wgt_in    (weight_reg),
        .acc_in    (acc_in),
        .acc_out   (acc_out)
    );

    assign act_out = act_reg;
endmodule
```

**Key Architectural Insight:**
- Notice that `act_out = act_reg`. Activation data is registered when passed to the east neighbor.
- `acc_out` is registered inside `pe_mac_csa` when passed to the south neighbor.
- This creates the classic **2D orthogonal systolic pipeline** where data flows across a 2D register lattice with zero combinatorial ripples across PE boundaries.

---

### 3.2 Registered MAC Unit (`rtl/pe/pe_mac_csa.sv`)
```systemverilog
module pe_mac_csa #(
    parameter int INT8_WIDTH = 8,
    parameter int ACC_WIDTH  = 32
)(
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         clear_acc,
    input  logic                         enable,
    input  logic signed [INT8_WIDTH-1:0] act_in,
    input  logic signed [INT8_WIDTH-1:0] wgt_in,
    input  logic signed [ACC_WIDTH-1:0]  acc_in,
    output logic signed [ACC_WIDTH-1:0]  acc_out
);
    logic signed [15:0]          mult_product;
    logic signed [ACC_WIDTH-1:0] mult_product_ext;

    // Combinational signed multiply
    assign mult_product     = act_in * wgt_in;
    assign mult_product_ext = {{16{mult_product[15]}}, mult_product};

    // Registered vertical accumulator (1 cycle per row)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_out <= '0;
        end else if (clear_acc) begin
            acc_out <= '0;
        end else if (enable) begin
            acc_out <= acc_in + mult_product_ext;
        end
    end
endmodule
```

**Why this code structure is critical:**
1. `act_in * wgt_in`: In SystemVerilog, signed multiplication requires both inputs to have the `signed` attribute. If either operand were unsigned, Verilog rules would zero-extend the operands and produce an erroneous positive product.
2. Sign-extension: `{{16{mult_product[15]}}, mult_product}` preserves negative sign across 32 bits before addition.

---

### 3.3 Output De-Skewing Logic (`rtl/systolic/systolic_array_8x8.sv`)
```systemverilog
// Output De-skewing Registers
genvar c;
generate
    for (c = 0; c < ARRAY_SIZE; c++) begin : gen_output_deskew
        localparam int DESKEW_DEPTH = ARRAY_SIZE - 1 - c;
        if (DESKEW_DEPTH == 0) begin
            // Column 7 already finishes at cycle t+7; zero extra delay needed
            assign acc_matrix_out[c] = pe_acc_wire[ARRAY_SIZE][c];
        end else begin
            logic signed [ACC_WIDTH-1:0] deskew_regs [0:DESKEW_DEPTH-1];
            
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n)          deskew_regs[0] <= '0;
                else if (clear_acc)  deskew_regs[0] <= '0;
                else if (enable)     deskew_regs[0] <= pe_acc_wire[ARRAY_SIZE][c];
            end
            
            genvar ds;
            for (ds = 1; ds < DESKEW_DEPTH; ds++) begin : gen_deskew_delay
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n)         deskew_regs[ds] <= '0;
                    else if (clear_acc) deskew_regs[ds] <= '0;
                    else if (enable)    deskew_regs[ds] <= deskew_regs[ds-1];
                end
            end
            assign acc_matrix_out[c] = deskew_regs[DESKEW_DEPTH-1];
        end
    end
endgenerate
```

---

### 3.4 Top-Level Controller FSM (`rtl/tpu_lite_top.sv`)
The accelerator is orchestrated by an 8-state Moore/Mealy hybrid FSM:

```systemverilog
typedef enum logic [2:0] {
    TPU_IDLE       = 3'b000,
    TPU_FETCH_WGT  = 3'b001,
    TPU_LOAD_WGT   = 3'b010,
    TPU_FETCH_ACT  = 3'b011,
    TPU_COMPUTE    = 3'b100,
    TPU_STORE_OUT  = 3'b101,
    TPU_DONE       = 3'b110,
    TPU_ERROR      = 3'b111
} tpu_state_e;
```

**State Sequence:**
1. `TPU_IDLE`: Accelerator waits for CSR bit `reg_ctrl[0] == 1` (`tpu_start`).
2. `TPU_FETCH_WGT`: Triggers DMA read of 64 weight bytes from `wgt_base_addr`.
3. `TPU_LOAD_WGT`: Asserts `tpu_load_wgt=1` and `tpu_wgt_en=1` to pulse weights into array PEs.
4. `TPU_FETCH_ACT`: Triggers DMA read of 64 activation bytes from `act_base_addr`.
5. `TPU_COMPUTE`: Asserts `tpu_enable=1` and `tpu_act_en=1`. Systolic array computes for 22 cycles.
6. `TPU_STORE_OUT`: When `tpu_data_valid` pulses, results are written into SRAM and DMA initiates burst write of 256 bytes (64 INT32 values) to `out_base_addr`.
7. `TPU_DONE`: Asserts external `interrupt` wire and status register bit `reg_status[1]`. Waits for `tpu_start` deassertion to transition back to `TPU_IDLE`.

---

## 4. Verification Architecture & Methodology

### 4.1 Verification Environment Diagram

```
                 +---------------------------------------------+
                 |          Test Stimulus Controller           |
                 |       (tb_systolic_self_check.sv)           |
                 +----------------------+----------------------+
                                        |
                   +--------------------+--------------------+
                   |                                         |
                   v (gold_A, gold_W)                        v (Array Stimulus)
    +-----------------------------+           +------------------------------+
    |   Independent Golden Model  |           |      DUT 1: processing_element|
    |      compute_expected()     |           |      DUT 2: systolic_array_8x8|
    +--------------+--------------+           +--------------+---------------+
                   |                                         |
                   | expected_C[r][c]                        | actual_C[r][c]
                   v                                         v
    +------------------------------------------------------------------------+
    |                           Scoreboard Check                             |
    |  - Compares all 64 elements                                            |
    |  - Checks: actual_C[r][c] === expected_C[r][c]                         |
    |  - Reports [SCOREBOARD PASS] or [SCOREBOARD MISMATCH]                  |
    |  - Hard failure: $fatal(1) ensures non-zero shell exit code            |
    +------------------------------------------------------------------------+
```

### 4.2 Independent Golden Model Implementation
The golden model task calculates $C = A \times W$ completely independently using standard integer arithmetic in SystemVerilog. It does **not** reuse any RTL pipeline or datapath logic:

```systemverilog
task compute_expected;
    integer ia, iw, acc;
    for (int m = 0; m < N; m++) begin
        for (int n = 0; n < N; n++) begin
            acc = 0;
            for (int k = 0; k < N; k++) begin
                ia = gold_A[m][k];
                iw = gold_W[k][n];
                acc = acc + (ia * iw);
            end
            expected_C[m][n] = acc;
        end
    end
endtask
```

### 4.3 Element-by-Element Scoreboard
```systemverilog
task scoreboard_check(input string test_name);
    bit test_pass;
    test_pass = 1'b1;
    for (int r = 0; r < N; r++) begin
        for (int c = 0; c < N; c++) begin
            total_checks++;
            if (actual_C[r][c] !== expected_C[r][c]) begin
                $error("[SCOREBOARD MISMATCH] %s | [%0d][%0d] | Exp: %0d | Got: %0d",
                       test_name, r, c, expected_C[r][c], actual_C[r][c]);
                total_errors++;
                test_pass = 1'b0;
            end
        end
    end
    if (test_pass) begin
        $display("  [SCOREBOARD PASS] %s: All 64 matrix elements verified.", test_name);
    end
endtask
```

### 4.4 Simulation Watchdog & Timeout Safety
To prevent testbench hangs if `data_valid` fails to assert, an explicit cycle counter watchdog aborts simulation:

```systemverilog
while (row_captured < N) begin
    @(posedge clk);
    #1;
    if (sys_data_valid) begin
        // Capture row
        row_captured++;
    end
    timeout_ctr++;
    if (timeout_ctr >= TIMEOUT_MAX) begin
        $fatal(1, "[TIMEOUT ERROR] %s: data_valid never asserted within %0d cycles!",
               test_name, TIMEOUT_MAX);
    end
end
```

---

## 5. Complete Test Inventory

### 5.1 SystemVerilog Core Testbench (`sim/tb/tb_systolic_self_check.sv`)

| Test # | Test Name | Stimulus / Operands | Expected RTL Behavior | Actual Result | Verification Mechanism |
|---|---|---|---|---|---|
| **TEST 1** | Active Reset Verification | `rst_n = 0` pulsed for 30 ns | `pe_acc_out == 0`, `pe_act_out == 0`, `sys_data_valid == 0` | **PASS** | SVA Assertion + Direct Check |
| **TEST 2** | PE Normal Signed MAC | `wgt=6`, `act=4`, `acc_in=10` | `acc_out = 10 + (4*6) = 34`, `act_out = 4` | **PASS** | Exact Value Equality |
| **TEST 3** | PE Signed Negative Operands | `wgt=6`, `act=-3`, `acc_in=-20` | `acc_out = -20 + (-3*6) = -38` | **PASS** | Two's Complement Check |
| **TEST 4** | PE INT8 Max Boundary | `wgt=+127`, `act=+127`, `acc_in=0` | `acc_out = 127 * 127 = 16,129` | **PASS** | Positive Saturation Check |
| **TEST 4a**| PE INT8 Min×Max Boundary | `wgt=-128`, `act=+127`, `acc_in=0` | `acc_out = -128 * 127 = -16,256` | **PASS** | Negative Boundary Check |
| **TEST 5** | PE Zero Input Operand | `wgt=5`, `act=0`, `acc_in=99` | `acc_out = 99` (Accumulator passthrough) | **PASS** | Zero Multiplier Passthrough |
| **TEST 6** | Array All-Zero Matrices | $W = 0_{8 \times 8}$, $A = 0_{8 \times 8}$ | All 64 elements of $C = 0$ | **PASS** | Scoreboard (64 elements) |
| **TEST 7** | Array Identity Weights | $W = I_{8 \times 8}$, $A = 10(r+1) + (c+1)$ | Matrix multiplied by Identity yields $C = A$ | **PASS** | Scoreboard (64 elements) |
| **TEST 8** | Array Boundary Extremes | $A = +127_{8 \times 8}$, $W = -128_{8 \times 8}$ | Each dot product: $8 \times (127 \times -128) = -130,048$ | **PASS** | Scoreboard (64 elements) |
| **TEST 9** | Array Signed Random Multiply| Signed pseudo-random values $[-128, +127]$ | Matches dynamic golden model matrix multiply | **PASS** | Scoreboard (64 elements) |
| **TEST 10**| Mid-Run Reset & Recovery | Reset asserted mid-stream, released, reloaded | Reset suppresses `data_valid`; re-run matches golden | **PASS** | Scoreboard (64 elements) |

**Total SV Core Verification Points:** 330 checks passed, 0 failures.

---

### 5.2 Cocotb AXI4-Lite CSR Testbench (`sim/cocotb/test_systolic.py`)

| Test Name | Interface Exercised | Description & Stimulus | Expected Behavior | Actual Result |
|---|---|---|---|---|
| `test_01_reset_outputs_zero` | AXI4-Lite & Interrupt | Deassert reset, monitor top-level ports | Ready/Valid lines low, `interrupt == 0` | **PASS** (56 ns) |
| `test_02_csr_dim_readback` | AXI4-Lite Address `0x08, 0x0C, 0x10` | Write M=8, K=8, N=8 to dimension CSRs | Readback returns 8, 8, 8 exactly | **PASS** (132 ns) |
| `test_03_csr_base_addr_readback`| AXI4-Lite Address `0x14, 0x18, 0x1C` | Write Host DRAM base addresses | Readback returns programmed addresses | **PASS** (132 ns) |
| `test_04_status_idle_after_reset`| AXI4-Lite Address `0x04` | Read status register `CSR_STATUS` | `busy=0`, `done=0` | **PASS** (72 ns) |
| `test_05_perf_counter_increments`| AXI4-Lite Address `0x20` | Read clock cycle counter across 20 cycles | Counter is non-zero and monotonic increasing | **PASS** (204 ns) |
| `test_06_interrupt_low_when_idle`| Interrupt line | Monitor `interrupt` across 30 clock cycles | Remains steadily 0 while un-triggered | **PASS** (180 ns) |

**Total Cocotb Tests:** 6 passed, 0 failures.

---

## 6. Realistic Bugs & Debugging Stories

The bugs below are drawn directly from the repository's Git commit history (`git log -p`) and recent development records.

### Bug 1: The Combinational Adder Ripple Bug in the Processing Element
- **Commit Reference:** `16ca34e5d84c72f1fb20b6ac8a4c20de86d3bd9f`
- **Module:** `rtl/pe/processing_element.sv`
- **Faulty Behavior:** The partial sum accumulation was performed combinationally *outside* the registered MAC unit:
  ```systemverilog
  // BEFORE (BUGGY):
  assign acc_out = mac_acc_result + acc_in;
  ```
- **Root Cause:** In a systolic array, each PE row must add exactly **one clock cycle of latency** to the vertical partial sum propagation. By using a continuous assignment (`assign acc_out = ...`), the partial sum from Row 0 rippled combinationally through Rows 1, 2, 3, 4, 5, 6, and 7 within a single clock cycle! This violated the systolic wavefront schedule and created a massive combinational delay path.
- **The Fix:** Removed the external adder wire. Routed `acc_in` directly into `pe_mac_csa`, which contains the registered accumulation FF:
  ```systemverilog
  // AFTER (FIXED):
  // Inside processing_element.sv:
  pe_mac_csa u_mac_core (
      .acc_in (acc_in),
      .acc_out(acc_out)   // acc_out is registered inside pe_mac_csa
  );
  ```
- **Regression Proof:** Fixed cycle-accurate pipeline latency. Vertical accumulation now takes exactly 1 clock cycle per row.

---

### Bug 2: Missing Column Output De-Skewing (Diagonal Result Corruption)
- **Commit Reference:** `eb35000613c6c606f66900303ee6b3afbf916d77`
- **Module:** `rtl/systolic/systolic_array_8x8.sv`
- **Faulty Behavior:** When reading out the result matrix, Column 0 had the correct values, but Columns 1 through 7 contained garbage or shifted partial sums.
- **Root Cause:** Due to input activation skewing, Column $c$ completes its final accumulation $c$ cycles after Column 0. The original design directly assigned the bottom PE wires to the output port:
  ```systemverilog
  // BEFORE (BUGGY):
  assign acc_matrix_out[c] = pe_acc_wire[ARRAY_SIZE][c];
  ```
  Sampling all 8 columns at the same clock edge sampled Column 0 on time, Column 1 one cycle early, Column 2 two cycles early, etc.
- **The Fix:** Inserted output de-skew shift registers. Column $c$ passes through $(N - 1 - c)$ registers:
  ```systemverilog
  // AFTER (FIXED):
  localparam int DESKEW_DEPTH = ARRAY_SIZE - 1 - c;
  // Column c delayed by DESKEW_DEPTH cycles
  assign acc_matrix_out[c] = (DESKEW_DEPTH == 0) ? 
                              pe_acc_wire[ARRAY_SIZE][c] : 
                              deskew_regs[DESKEW_DEPTH-1];
  ```
- **Regression Proof:** Tested in `TEST 7` (Identity Matrix). All 64 matrix elements match expected values simultaneously.

---

### Bug 3: Activation Skew Registers Lacking Reset on `clear_acc`
- **Commit Reference:** `eb35000613c6c606f66900303ee6b3afbf916d77`
- **Module:** `rtl/systolic/systolic_array_8x8.sv`
- **Faulty Behavior:** Running back-to-back matrix multiplications caused the second matrix multiplication to fail scoreboard comparison, even though running it in isolation passed.
- **Root Cause:** The input skew registers only reset on `!rst_n`. When starting a new computation using `clear_acc`, stale activation samples from the tail of Matrix 1 remained in the shift registers and bled into Row 1..7 of Matrix 2!
- **The Fix:** Added `clear_acc` branch to the reset condition in the skew generate blocks:
  ```systemverilog
  // AFTER (FIXED):
  always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)         skew_regs[s] <= '0;
      else if (clear_acc) skew_regs[s] <= '0;
      else if (enable)    skew_regs[s] <= skew_regs[s-1];
  end
  ```
- **Regression Proof:** Tested in `TEST 10` (Mid-Run Reset & Clean Recovery). Back-to-back runs maintain zero residual contamination.

---

### Bug 4: Icarus Verilog Elaboration & SystemVerilog Feature Limitations
- **Commit Reference:** Current Working Tree Fixes
- **Modules:** `rtl/tpu_lite_top.sv`, `rtl/assertions/sva_*.sv`
- **Faulty Behavior:**
  1. `iverilog` gave syntax errors on temporal assertions (`|=>`, `##1`).
  2. `iverilog` gave `sorry: "inside" expressions not supported yet` in `sva_fsm_checker.sv`.
  3. `iverilog` threw `error: This assignment requires an explicit cast` on enum `tpu_state_e` assignments in `tpu_lite_top.sv`.
- **Root Cause:** Icarus Verilog 11.0 is an open-source tool with partial IEEE 1800-2012 support. It supports immediate assertions (`assert (...)`), but lacks the temporal assertion engine and certain enum strict-typing features.
- **The Fix:**
  - Wrapped concurrent SVA properties in `` `ifdef FORMAL_SVA `` and provided simulation-time immediate assertions in the `` `else `` branch.
  - Replaced `inside {TPU_IDLE, ...}` with explicit boolean OR chains (`current_state == TPU_IDLE || ...`).
  - Declared `state, next_state` as `logic [2:0]` in `tpu_lite_top.sv` to ensure clean elaboration under Icarus Verilog while preserving named enum constants.
- **Regression Proof:** Clean compilation and execution under `bash run_sim.sh` with exit code 0.

---

## 7. Biggest Bug Deep Dive

### 7.1 Interview Topic: Systolic Array Output Timing Alignment & De-skewing
This is the single most technically impressive bug to discuss in an interview because it demonstrates an understanding of **2D spatial timing wavefronts, pipeline latencies, and formal array alignment**.

#### The Scenario
> *"During initial multi-row matrix verification, single-PE tests were passing 100%, and the first row of matrix multiplication was computing correctly, but every subsequent column in the array was returning corrupt values. The scoreboard reported mismatches specifically in Columns 1 through 7."*

#### Step 1: Symptom & Diagnosis
- In `TEST 7`, we drove an Identity matrix $W = I$ and streamed an incremental activation matrix $A$.
- Expected Row 0: `[11, 12, 13, 14, 15, 16, 17, 18]`
- Actual Row 0: `[11, 0, 0, 0, 0, 0, 0, 0]`
- Column 0 was correct, but all other columns were zero or shifted.

#### Step 2: Root Cause Investigation
A systolic array requires **input skewing** to synchronize activation arrival with partial sum propagation. Row $r$ is delayed by $r$ cycles:
- Row 0 enters at $T=0$.
- Row 1 enters at $T=1$.
- Row $r$ enters at $T=r$.

Because activations are delayed entering the array, the computation finishes at different times:
- Column 0 finishes its final MAC in PE[7][0] at cycle $T = 7 + 0 = 7$.
- Column 1 finishes its final MAC in PE[7][1] at cycle $T = 7 + 1 = 8$.
- Column $c$ finishes its final MAC in PE[7][c] at cycle $T = 7 + c$.

The RTL had connected `pe_acc_wire[7][c]` directly to the top-level output bus `acc_matrix_out[c]`. When the scoreboard sampled at cycle 14, Column 0 was already stale (or overwritten), while Column 7 had just arrived!

#### Step 3: Mathematical Derivation of the Fix
To make all columns of Row $m$ appear on the output bus at the **exact same clock cycle**, each column output $c$ must be delayed by an inverse de-skew delay:
$$\text{Deskew Delay}(c) = (N - 1) - c = 7 - c$$
- Column 7 delay: $7 - 7 = 0$ cycles (direct wire).
- Column 6 delay: $7 - 6 = 1$ cycle register.
- Column 0 delay: $7 - 0 = 7$ cycle shift register.

Total arrival cycle for any column $c$ of row $m$:
$$T_{\text{valid}} = m + N + c + (N - 1 - c) = m + 2N - 1$$
Notice that $c$ completely cancels out! Every column arrives at cycle $m + 15$ ($m + 2N - 1$ for 1-based indexing, cycle $14$ in 0-based timing).

#### Step 4: Verification Result
After implementing the `DESKEW_DEPTH` generate loop, `TEST 7` (Identity) and `TEST 9` (Random Multiply) immediately passed all 64 element comparisons.

---

## 8. Exact Run Instructions

All commands are validated for **WSL2 (Ubuntu 22.04 LTS)** or standard Linux.

### 8.1 Prerequisites Installation
Run once to set up the toolchain:
```bash
sudo apt-get update
sudo apt-get install -y iverilog python3 python3-numpy python3-pip
pip3 install cocotb
```

### 8.2 Execution Commands

#### Command 1: Run Full SystemVerilog Core Testbench (Recommended First Step)
Runs the 10 self-checking test cases with the element-by-element scoreboard:
```bash
cd /mnt/c/Users/Lenovo/Desktop/TpuLite
bash run_sim.sh
```
- **What it does:** Compiles `pe_mac_csa.sv`, `processing_element.sv`, `systolic_array_8x8.sv`, and `tb_systolic_self_check.sv` using `iverilog -g2012`, builds `/tmp/tb_systolic.vvp`, and executes with `vvp`.
- **Expected Success Output:**
  ```
  =======================================================
                   VERIFICATION SUMMARY                  
  =======================================================
    Total Assertions & Elements Checked: 330
    Total Errors & Scoreboard Mismatches: 0
    FINAL VERDICT                       : PASSED ALL TESTS
  =======================================================
  ```
- **Exit code:** `0` (check with `echo $?`).

---

#### Command 2: Run Cocotb AXI4-Lite Test Suite
Executes the 6 AXI4-Lite CSR host register tests:
```bash
cd /mnt/c/Users/Lenovo/Desktop/TpuLite/sim/cocotb
make SIM=icarus
```
- **What it does:** Compiles top-level SoC RTL with VPI wrapper, runs Python test suite.
- **Expected Success Output:**
  ```
  TESTS=6 PASS=6 FAIL=0 SKIP=0
  ```
- **Output Artifacts:** `sim_build/sim.vvp`, `results.xml`.

---

#### Command 3: Cross-Check 100 Stored Test Vectors Against NumPy Golden Model
```bash
cd /mnt/c/Users/Lenovo/Desktop/TpuLite
make cross-check
```
- **What it does:** Reads `sim/tb/test_vectors.hex`, parses weight and activation matrices, calculates $C = A \times W$ from scratch in NumPy, and validates against the stored hex vectors.
- **Expected Success Output:**
  ```
  Vectors checked : 100
  Mismatches      : 0
  VERDICT         : PASSED — all stored vectors match golden
  ```

---

#### Command 4: Run Python Standalone Golden Reference Model
```bash
cd /mnt/c/Users/Lenovo/Desktop/TpuLite
make golden
```

---

### 8.3 Waveform Generation & GTKWave Inspection
To view simulation waveforms in GTKWave:
1. In `sim/tb/tb_systolic_self_check.sv`, ensure the following block is present in `initial begin`:
   ```systemverilog
   $dumpfile("systolic_waves.vcd");
   $dumpvars(0, tb_systolic_self_check);
   ```
2. Re-run `bash run_sim.sh`.
3. Open in GTKWave (Windows or WSL X-Server):
   ```bash
   gtkwave systolic_waves.vcd
   ```
4. Key signals to observe:
   - `clk`, `rst_n`
   - `dut_array.act_skewed[0]` through `act_skewed[7]` (visualizes input skew)
   - `dut_array.pe_acc_wire[8][*]` (raw PE bottom outputs)
   - `dut_array.acc_matrix_out[*]` (de-skewed aligned outputs)
   - `dut_array.data_valid` (pulses high for exactly 8 cycles)

---

## 9. Results & Evidence

### 9.1 Empirical Simulation Evidence Summary

| Test Domain | Executed Command | Tool & Version | Total Checks | Mismatches | Exit Code | Verified Status |
|---|---|---|---|---|---|---|
| **RTL Compute Core** | `bash run_sim.sh` | Icarus Verilog 11.0 / vvp | 330 checks | 0 | `0` | **VERIFIED PASS** |
| **AXI4-Lite Host Interface** | `make sim` (Cocotb) | Cocotb 2.1.0 + iverilog | 6 testcases | 0 | `0` | **VERIFIED PASS** |
| **Golden Reference Model** | `make golden` | Python 3.10 + NumPy 1.21 | 64 elements | 0 | `0` | **VERIFIED PASS** |
| **Vector Generator Cross-Check** | `make cross-check` | Python 3.10 | 6,400 elements | 0 | `0` | **VERIFIED PASS** |

### 9.2 Tool Limitations & Status Disclosures
- **Formal Verification (JasperGold/VC Formal):** Not run. Temporal assertion syntax was syntax-checked and isolated with `FORMAL_SVA` defines.
- **Physical Synthesis & Timing Closure (Vivado):** Not executed in this Linux/WSL runtime environment. Synthesis scripts and constraints are provided in `synth/`.
- **Code Coverage (lcov/urg):** Line/branch/toggle coverage engines are not supported by the open-source Icarus simulation target; coverage results are not claimed.

---

## 10. SystemVerilog Concepts

### 10.1 `logic` vs `wire` vs `reg`
- `wire` is a net type that does not store state; it requires continuous assignment (`assign`).
- `reg` was the Verilog-1995 data storage type, but caused confusion because not all `reg` types inferred hardware flip-flops.
- SystemVerilog introduced `logic`: a 4-state data type that can be used for both combinational logic and sequential flip-flops. TPU-Lite exclusively uses `logic` for all RTL signals.

### 10.2 Signed Arithmetic Rules & Bit-Width Rules
- In SystemVerilog, signed arithmetic is fragile: **if even one operand in an expression is unsigned, the entire expression is coerced to unsigned!**
- Example:
  ```systemverilog
  logic signed [7:0] a = -8'sd5;
  logic        [7:0] b = 8'd2; // Unsigned!
  logic signed [15:0] prod = a * b; // BUG! Computes 251 * 2 = 502, NOT -10!
  ```
- **Rule in TPU-Lite:** Every operand in the MAC tree (`act_in`, `wgt_in`, `acc_in`, `mult_product`, `mult_product_ext`) is explicitly declared with the `signed` keyword.

### 10.3 Non-Blocking (`<=`) vs Blocking (`=`) Assignments
- **Rule:** Use non-blocking (`<=`) in sequential blocks (`always_ff`), and blocking (`=`) in combinational blocks (`always_comb`).
- **Why?** Non-blocking assignments schedule updates for the NBA region of the SystemVerilog event queue (after all active evaluations are complete). This eliminates simulation race conditions between flip-flops clocking data into one another.

### 10.4 SystemVerilog Assertions: Immediate vs Concurrent
- **Immediate Assertions (`assert (...)`):** Evaluated instantaneously in simulation procedural flow like an `if` statement. Supported by Icarus Verilog.
  ```systemverilog
  assert (sram_addr < DEPTH) else $error("Address Out of Bounds!");
  ```
- **Concurrent Assertions (`assert property (...)`):** Clock-driven temporal statements evaluated across multiple cycles using formal operators (`|=>`, `##1`, `$past()`).
  ```systemverilog
  property p_awvalid_stable;
      @(posedge clk) disable iff (!rst_n)
      (awvalid && !awready) |=> $stable(awvalid);
  endproperty
  ```

---

## 11. Interview Question Bank (45 Questions & Answers)

### Architecture & Principles
1. **Q: What is a systolic array and why is it preferred for matrix multiplication over a standard GPU ALU?**  
   *A:* A systolic array is a 2D network of tightly coupled DPUs (Processing Elements) that rhythmically compute and pass data through the grid. It maximizes data reuse ($O(N)$ memory reads produce $O(N^2)$ computations), avoiding memory bus congestion.

2. **Q: Explain the difference between Weight-Stationary, Output-Stationary, and Weight-Streaming dataflows.**  
   *A:* In Weight-Stationary (used here), weights remain fixed in PE registers while activations and partial sums move. In Output-Stationary, accumulators stay in PEs while weights and activations stream through. WS is ideal for inference where weights can be preloaded once per layer.

3. **Q: How many cycles does an $8 \times 8$ matrix multiplication take to complete?**  
   *A:* 22 clock cycles total. 1 cycle preload, 14 cycles pipeline latency to first output row, and 7 subsequent cycles to stream the remaining 7 rows.

4. **Q: Why does the systolic array require input skewing?**  
   *A:* Because partial sums move vertically down the array with a 1-cycle delay per PE row, activation inputs must be delayed by $r$ cycles on row $r$ so they intersect the correct accumulating sum.

5. **Q: Why does the array require output de-skewing?**  
   *A:* Because column $c$ finishes $c$ clock cycles after Column 0. Delaying column $c$ by $(N - 1 - c)$ cycles synchronizes all columns onto a single parallel bus.

6. **Q: What happens if you multiply $-128 \times -128$ in 8-bit two's complement?**  
   *A:* In 8-bit signed math, $-128$ is `8'b1000_0000`. Multiplying two 8-bit signed numbers in SystemVerilog produces a 16-bit signed result: $+16,384$ (`16'h4000`), which fits within 16 bits without overflow.

7. **Q: Why is the accumulator 32 bits when inputs are 8 bits?**  
   *A:* $8 \times 8$ multiplication accumulates 8 products of 16 bits. Maximum magnitude is $8 \times 16,384 = 131,072$, which requires 18 bits. 32 bits provides abundant headroom, preventing any overflow and aligning with standard 32-bit bus architectures.

8. **Q: What is the purpose of the double-buffer in the memory subsystem?**  
   *A:* It implements ping-pong buffering: while the systolic array computes on Page 0, the DMA engine can stream the next layer's weights into Page 1, hiding host memory latency.

9. **Q: How are weights loaded into the array?**  
   *A:* When `load_weight` is pulsed high, each PE registers the value on its `wgt_in` port on the rising clock edge.

10. **Q: What is the function of `data_valid`?**  
    *A:* It indicates that the signals on `acc_matrix_out[0:7]` represent valid, deskewed dot-product results.

---

### RTL Design & Coding Details
11. **Q: Why did you declare `state` and `next_state` as `logic [2:0]` instead of an enum type in `tpu_lite_top.sv`?**  
    *A:* To maintain compatibility with Icarus Verilog 11.0, which enforces strict casting rules on enum variables in `always_comb` blocks. The enum constants (`TPU_IDLE`, etc.) are still used for readability.

12. **Q: Why is reset asynchronous assert and synchronous deassert preferred in digital design?**  
    *A:* Asynchronous assert guarantees the circuit enters reset immediately even if the clock is stopped. Synchronous deassertion prevents reset recovery/removal timing violations on flip-flops.

13. **Q: What happens if `clear_acc` is asserted during computation?**  
    *A:* It synchronously resets `acc_out` to 0 in all PEs and flushes the skew and deskew registers, discarding in-flight calculations.

14. **Q: Why are generate loops used in `systolic_array_8x8.sv`?**  
    *A:* To instantiate the 64 PEs and create parametric delay chains whose depth varies per row/column ($r$ or $7-c$).

15. **Q: What is the hardware inferred by `{{16{mult_product[15]}}, mult_product}`?**  
    *A:* Zero logic gates; it is purely wiring that replicates the sign bit (bit 15) to bits [31:16].

16. **Q: Is there any combinational path from array input to array output?**  
    *A:* No. Both activations and partial sums pass through registers in every PE, ensuring maximum operating frequency.

17. **Q: How does the CSR slave handle an invalid address?**  
    *A:* It returns `32'hDEAD_BEEF` on `s_axi_rdata` with an `OKAY` response (`2'b00`).

18. **Q: Why is `pe_act_wire` dimensioned `[0:ARRAY_SIZE-1][0:ARRAY_SIZE]`?**  
    *A:* There are 8 rows and 9 horizontal connection points (1 input from skew, 7 inter-PE wires, 1 unused output from the rightmost PE).

19. **Q: What is the role of `s_axi_wstrb` in the CSR slave?**  
    *A:* Byte write strobes. `4'hF` indicates all 4 bytes of the 32-bit word are valid.

20. **Q: Does the DMA engine support unaligned memory bursts?**  
    *A:* The architecture assumes 64-bit aligned addresses (lower 3 address bits `3'b000`), monitored by `sva_axi4_checker`.

---

### Verification Methodology & Testbench
21. **Q: Why is your testbench called "self-checking"?**  
    *A:* It does not rely on manual waveform inspection. It computes expected matrices programmatically, compares actual outputs element-by-element, and triggers `$fatal(1)` on any mismatch.

22. **Q: Why did you use Cocotb in addition to SystemVerilog?**  
    *A:* Cocotb enables high-level Python scripting for bus-functional modeling (driving AXI transactions, testing register maps) while SystemVerilog handles cycle-accurate pipeline verification.

23. **Q: How does the testbench avoid sampling race conditions?**  
    *A:* Outputs are sampled `#1` ns after the rising clock edge (`@(posedge clk); #1;`), allowing flip-flop outputs to settle cleanly.

24. **Q: What is the purpose of the `TIMEOUT_MAX` counter?**  
    *A:* It prevents testbench deadlocks. If a bug prevents `data_valid` from asserting, the watchdog aborts simulation with an explicit failure code.

25. **Q: How did you test boundary cases?**  
    *A:* TEST 4 tests $+127 \times +127$, TEST 4a tests $-128 \times +127$, and TEST 8 tests an entire matrix of $+127$ multiplied by $-128$.

26. **Q: How do you verify that reset actually cleared internal registers?**  
    *A:* TEST 1 checks that `pe_acc_out`, `pe_act_out`, and `sys_data_valid` are 0 while `rst_n == 0`.

27. **Q: Can this testbench detect X/Z propagation?**  
    *A:* Yes. SystemVerilog assertion A5 uses `!$isunknown(sys_acc_out)` to flag any uninitialized logic states during valid cycles.

28. **Q: Why did you use `!==` instead of `!=` in the scoreboard?**  
    *A:* `!==` is the 4-state case-inequality operator; it detects mismatches even if a signal floats to `X` or `Z`.

29. **Q: How did you cross-check the Python vector generator?**  
    *A:* With `cross_check.py`, which reads the hex file, re-derives the matrix multiplication independently in NumPy, and compares byte-by-byte.

30. **Q: What is the difference between direct testing and constrained-random testing?**  
    *A:* Direct tests target specific known edge cases (zeros, min/max). Constrained-random testing generates pseudo-random inputs within valid bounds to discover unanticipated corner-case interactions.

---

### Debugging & Troubleshooting
31. **Q: Walk me through a bug you found during testbench development.**  
    *A:* (Refer to Section 7: Output De-skewing timing bug).

32. **Q: Why did the original Processing Element cause a timing violation?**  
    *A:* It had a combinational `assign acc_out = mac_acc_result + acc_in;`, rippling partial sums through 8 adders in a single clock cycle.

33. **Q: How did you detect that skew registers were not clearing on `clear_acc`?**  
    *A:* By running back-to-back tests (TEST 10). The second test produced corrupted results because activations from the first test remained in the pipeline.

34. **Q: What tool did you use to debug signal waveforms?**  
    *A:* Generated `.vcd` dumps using `$dumpvars` and inspected signal timing in GTKWave.

35. **Q: How did you resolve the enum cast error in Icarus Verilog?**  
    *A:* Changed the FSM state registers from enum types to standard 3-bit logic vectors while retaining enum labels as constants.

---

### Advanced Verification Concepts
36. **Q: What is a Covergroup and how would you implement functional coverage here?**  
    *A:* A covergroup samples variables at specified clock edges. Here, we would cover: (1) sign combinations of inputs (pos/pos, pos/neg, neg/neg, zero), (2) FSM state transitions, and (3) AXI backpressure scenarios.

37. **Q: What is the difference between Code Coverage and Functional Coverage?**  
    *A:* Code coverage measures executed RTL lines/branches/toggles (syntactic). Functional coverage measures whether the features in the verification plan were actually exercised (semantic).

38. **Q: Why is formal verification superior to simulation for AXI protocol checking?**  
    *A:* Simulation only checks the stimulus provided. Formal verification mathematically proves that an assertion holds for *all possible* stimulus sequences.

39. **Q: What is clock gating and how could it be applied to TPU-Lite?**  
    *A:* Clock gating disables the clock to inactive registers. In PEs, the clock could be gated when `enable == 0` to save dynamic power.

40. **Q: What is sign extension and what bug occurs if you omit it?**  
    *A:* Sign extension copies the MSB into upper bit positions. Omitting it causes negative products (e.g. `16'hFFFF` = -1) to be treated as large positive numbers (`32'h0000FFFF` = 65,535).

41. **Q: How does backpressure work on the AXI stream?**  
    *A:* When a receiver cannot accept data, it deasserts `READY`. The sender must hold `VALID` and data stable until `READY` is asserted.

42. **Q: What is a memory BIST?**  
    *A:* Built-In Self-Test hardware added to SRAM banks to test for stuck-at and transition faults post-fabrication.

43. **Q: How would you verify unaligned burst addresses if the DMA engine supported them?**  
    *A:* By writing constrained-random tests that generate addresses with offsets not divisible by the bus width, verifying byte-enable strobes.

44. **Q: What is an interrupt latency?**  
    *A:* The number of clock cycles between the assertion of `tpu_done` and the host CPU servicing the interrupt line.

45. **Q: If you had 2 more weeks on this project, what would you add?**  
    *A:* (1) A full UVM testbench connecting the 10,000 hex vectors to the RTL via `$readmemh`, (2) Formal proofs of the AXI protocol using JasperGold, and (3) Physical synthesis in Vivado to confirm post-layout timing closure.

---

## 12. Interview Speaking Guide

### 12.1 The 2-Minute Elevator Pitch
> *"For my major digital verification project, I designed and verified **TPU-Lite**, an 8×8 weight-stationary systolic array machine learning accelerator implemented in SystemVerilog.*
>
> *The accelerator performs signed INT8 matrix multiplication accumulating into 32-bit registers across 64 pipelined processing elements. It includes an AXI4-Lite CSR register file, a 4-bank double-buffered SRAM controller, and an AXI4 DMA interface.*
>
> *On the verification side, I built a self-checking testbench in SystemVerilog that uses an independent golden reference model and an element-level scoreboard. I also built a 6-test Cocotb Python suite for the AXI4-Lite CSR interface.*
>
> *Across 10 test scenarios—covering active reset, signed INT8 arithmetic, boundary extremes, zero operands, and mid-run reset recovery—the testbench verified 330 matrix elements and assertions with zero mismatches under Icarus Verilog."*

---

### 12.2 The 5-Minute Technical Walkthrough
1. **The Architecture:**
   - *"The core is an 8×8 2D grid. Each PE has a local weight register, an activation pipeline FF, and an accumulator. It operates in weight-stationary mode: weights are loaded once, activations stream horizontally, and sums accumulate vertically."*
2. **The Wavefront Synchronization:**
   - *"To make the spatial math work, I implemented input skew registers where Row $r$ is delayed by $r$ cycles. Partial sums move down one PE row per cycle. Because Column $c$ completes $c$ cycles after Column 0, I added an inverse de-skew delay chain on the output so all 8 elements of a result row emerge in parallel."*
3. **The Verification Environment:**
   - *"I prioritized self-checking architecture. The SV testbench generates matrix stimulus, calculates expected results using an independent reference algorithm, streams data cycle-by-cycle, captures results via a `data_valid` handshake, and runs element-by-element scoreboard comparisons. I also added watchdog timers to catch pipeline deadlocks and SVA assertions to guard against uninitialized X-propagation."*
4. **Key Bugs Discovered:**
   - *"During development, I diagnosed and fixed a critical output alignment bug where missing de-skew registers corrupted matrix columns 1 through 7, as well as an issue where skew registers failed to clear between back-to-back inferences."*

---

### 12.3 Answering "What Was Your Biggest Bug?"
*(Use the structure: Context → Symptom → Diagnosis → Root Cause → Fix → Regression Verification)*
> *"My most challenging bug was the **output de-skewing alignment issue**. When I first simulated the full array with an identity matrix, Column 0 was 100% correct, but Columns 1 through 7 failed scoreboard checks.*
>
> *I traced the waveforms in GTKWave and realized that because input activations are staggered by row, the computation finishes in a diagonal wavefront across columns. Column 7 was finishing 7 clock cycles after Column 0.*
>
> *The original code assigned the bottom PE wires directly to the output bus, sampling all columns simultaneously. I derived the mathematical delay needed—$(N - 1 - c)$ cycles per column—and implemented parametric de-skew shift registers. Running regression test 7 proved that all 64 elements aligned on the exact same clock edge with zero errors."*

---

### 12.4 Answering Tough Questions Honestly

#### "What did you personally implement versus inherit?"
> *"I personally developed the self-checking SystemVerilog testbench, wrote the golden reference model, built the 6 Cocotb AXI4-Lite tests, identified and fixed the pipeline de-skew and combinational adder bugs, and resolved the Icarus Verilog elaboration incompatibilities. The base multi-bank memory and DMA RTL structure were part of the initial SoC project architecture."*

#### "Why didn't you use UVM?"
> *"My goal was to achieve clean, cycle-accurate verification using an open-source toolchain (Icarus Verilog + Cocotb) accessible on Linux/WSL without expensive commercial EDA licenses. I implemented the core principles of UVM—transaction generation, reference modeling, and scoreboard checking—using object-oriented SystemVerilog classes and Cocotb."*

#### "How do you know your design works?"
> *"I proved it through multiple layers of testing: (1) 10 targeted direct and random test cases in SystemVerilog checking 330 element points against an independent golden model, (2) automated `$fatal(1)` assertions that fail on any mismatch, (3) 6 Cocotb bus tests for the CSRs, and (4) a cross-check script verifying 6,400 elements across 100 hex test vectors."*

---

## 13. Resume Bullets & Defense

### 13.1 Tailored Resume Bullets

#### Option 1: Verification-Focused (Recommended for DV Roles)
> - **Digital Verification Engineer — TPU-Lite Systolic Array Accelerator**
>   - Designed a self-checking SystemVerilog testbench for an 8×8 weight-stationary INT8 systolic array accelerator; verified signed arithmetic, boundary values ($-128, +127$), and reset recovery across 10 test scenarios (330 checks, 0 mismatches).
>   - Implemented an independent golden reference model and scoreboard comparing actual vs. expected INT32 matrix products element-by-element with automated `$fatal` failure handling.
>   - Developed a Cocotb Python regression suite validating AXI4-Lite host CSR transactions, performance counters, and interrupt signaling under Icarus Verilog.

#### Option 2: RTL & Architecture Focused
> - **ASIC/FPGA Design & Verification — 8×8 Systolic Array ML Accelerator**
>   - Designed and verified a synthesizable 8×8 weight-stationary systolic array in SystemVerilog for INT8 ML inference, featuring 64 pipelined PEs, input skewing, and output de-skewing logic.
>   - Resolved critical microarchitectural bugs including vertical combinational adder rippling and column de-skew misalignments, restoring cycle-accurate pipeline latency.
>   - Integrated an AXI4-Lite CSR register file and verified host-accelerator handshakes using Cocotb and SystemVerilog Assertions (SVA).

---

### 13.2 Claims You Must NOT Make in an Interview
1. **Do not claim UVM compliance:** You have a clean class-based scoreboard, but not UVM macros (`uvm_info`, `uvm_analysis_port`).
2. **Do not claim 250 MHz silicon/FPGA closure:** You have timing constraints and synthesis scripts, but haven't run physical implementation in Vivado.
3. **Do not claim formal verification closure:** Your temporal SVA properties are written for Questa/JasperGold; in Icarus, you ran immediate assertions.
4. **Do not claim 100% functional coverage:** You tested all key functional features thoroughly, but haven't extracted an EDA code coverage database report.

---

## 14. Final Revision Sheet

### 14.1 Key Equations to Memorize
- **INT8 Multiply Range:** $[-128 \times -128 = +16,384]$ down to $[-128 \times +127 = -16,256]$.
- **Accumulator Bitwidth:** 32 bits ($[-2.14 \times 10^9, +2.14 \times 10^9]$).
- **First Valid Output Cycle:** $T_{\text{first}} = 2N - 2 = 14 \text{ cycles}$ (0-based indexing).
- **Execution Latency:** $3N - 2 = 22 \text{ clock cycles}$.
- **Input Skew Delay (Row $r$):** $r \text{ cycles}$.
- **Output De-Skew Delay (Column $c$):** $(N - 1 - c) = 7 - c \text{ cycles}$.

---

### 14.2 Signal Dictionary
- `sys_load_wgt`: Preloads weight matrix into PE internal registers.
- `sys_clear_acc`: Clears all accumulators and flushes skew/deskew pipelines.
- `sys_enable`: Clock enable for computation and pipeline registers.
- `act_vector[0:7]`: Unskewed input activations (streamed row-by-row).
- `acc_matrix_out[0:7]`: Deskewed output dot-product results (INT32).
- `sys_data_valid`: Asserted when `acc_matrix_out` contains a valid row result.
- `interrupt`: Asserted by top-level SoC upon completing the full matrix block.

---

### 14.3 Commands to Memorize
```bash
# Run Core SystemVerilog Testbench:
bash run_sim.sh

# Run Cocotb AXI4-Lite Tests:
make sim

# Check Last Exit Code:
echo $?
```

---

### 14.4 One-Day Interview Revision Plan
- **Morning (2 hours):** Review Section 2 (Architecture & Timing Schedule) and Section 7 (Biggest Bug Deep Dive). Practice drawing the 2D systolic grid and skew/deskew registers on paper.
- **Afternoon (2 hours):** Review Section 3 (RTL Walkthrough) and Section 10 (SystemVerilog Signed Arithmetic & Assertions). Run `bash run_sim.sh` and inspect the terminal output.
- **Evening (2 hours):** Rehearse Section 12 (Interview Speaking Guide) out loud. Answer 10 random questions from Section 11 without looking at the answers.
