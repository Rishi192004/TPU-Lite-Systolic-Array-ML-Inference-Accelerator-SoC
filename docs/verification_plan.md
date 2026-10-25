# TPU-Lite Verification Plan & Strategy

## 1. Overview
The verification strategy for **TPU-Lite** targets both the computational core (8×8 INT8 systolic array) and the host interface layer (AXI4-Lite CSR register file). It uses:
- A standalone, self-checking SystemVerilog testbench (`sim/tb/tb_systolic_self_check.sv`) with an element-by-element scoreboard and hard failure detection (`$fatal`).
- A Python/NumPy golden reference model (`sim/reference/golden_model.py`) for independent matrix math verification.
- A Cocotb Python testbench (`sim/cocotb/test_systolic.py`) testing AXI4-Lite CSR read/write access, reset status, and interrupt behavior.
- SystemVerilog Assertions (`rtl/assertions/`) validating AXI handshakes, FSM states, and SRAM memory address bounds.

---

## 2. Verification Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 Test Generation & Reference                 │
│  - Python NumPy Golden Model (Matrix Multiplication)        │
│  - 10,000 Constrained-Random Vector Generator               │
│  - Hex Vector Cross-Check Validator                         │
└──────────────────────────────┬──────────────────────────────┘
                               │
            ┌──────────────────┴──────────────────┐
            ▼                                     ▼
┌──────────────────────────────┐    ┌─────────────────────────┐
│ SystemVerilog Direct TB      │    │ Cocotb Python TB        │
│ (`tb_systolic_self_check.sv`)│    │ (`test_systolic.py`)    │
│  - Single PE MAC operations  │    │  - AXI4-Lite CSR Read/  │
│  - 8x8 Systolic Array checks │    │    Write verification   │
│  - Self-checking scoreboard  │    │  - Performance counter  │
│  - Immediate SVA assertions  │    │  - Reset and idle status│
└──────────────────────────────┘    └─────────────────────────┘
```

---

## 3. Test Matrix & Coverage Targets

### A. Core Arithmetic & Pipeline (`tb_systolic_self_check.sv`)
- **Reset Behavior**: Verifies all PE accumulators, activation pipeline registers, and `data_valid` deassert during active reset.
- **Single-PE Signed MAC**: Tests normal signed MAC (`10 + 4*6 = 34`), activation passthrough, negative operands (`-20 + -3*6 = -38`), zero activation (`0*5 + 99 = 99`), and boundary cases (`127*127 = 16129`, `-128*127 = -16256`).
- **Array Zero Inputs**: Matrix multiply with all-zero weights and activations ($C = 0$).
- **Array Identity Matrix**: Verifies matrix multiplication against identity matrix ($C = A \times I = A$).
- **Array Boundary Extremes**: Maximum magnitude signed INT8 inputs ($A=+127, W=-128$).
- **Array Pseudo-Random Multiply**: Arbitrary signed matrices with dynamic golden model calculation.
- **Mid-Run Reset & Recovery**: Triggers reset mid-computation, verifies `data_valid` immediate deassertion, followed by successful re-run.

### B. Host Interface & CSRs (`sim/cocotb/test_systolic.py`)
- **Reset State**: Verifies ready/valid lines and interrupt default to zero.
- **Dimension Registers**: Read/write of M, K, and N dimensions.
- **Base Addresses**: Configuration and readback of activation, weight, and output buffer base addresses.
- **Status Register**: Verifies `busy=0` and `done=0` when idle.
- **Performance Counters**: Checks clock cycle counter increments while running.
- **Interrupt Idle**: Asserts interrupt line remains inactive when no compute task is triggered.

---

## 4. SystemVerilog Assertions (SVA) Checkers

1. **`sva_axi4_checker`**:
   - `AWVALID` stability until `AWREADY` handshake.
   - `WVALID` and `WDATA` stability until `WREADY` handshake.
   - `ARVALID` stability until `ARREADY` handshake.
   - *Note*: Temporal concurrent assertions require Questa/JasperGold (`+define+FORMAL_SVA`); immediate equivalents run in Icarus Verilog.

2. **`sva_fsm_checker`**:
   - FSM state encoding validity (verifies no invalid states occur).
   - Reset-to-IDLE transition and liveness checks (formal temporal properties).

3. **`sva_fifo_checker`**:
   - SRAM buffer bounds checking (`sram_addr < DEPTH`).
   - Simultaneous read/write warning detection.

---

## 5. Verification Results Summary

- **SystemVerilog Testbench**: 10 of 10 tests passed (330 scoreboard elements and assertion points checked, 0 mismatches).
- **Cocotb Test Suite**: 6 of 6 tests passed (0 failures).
- **Golden Model Cross-Check**: 100 stored hex vectors re-derived and verified byte-for-byte against NumPy INT32 golden output (0 mismatches).
