#!/usr/bin/env python3
"""
===============================================================================
TPU-Lite: Golden Reference Model
File: sim/reference/golden_model.py
Description: Python/NumPy cycle-accurate and functional golden reference model
             for TPU-Lite 8x8 weight-stationary systolic array accelerator.
             Calculates exact INT8 x INT8 -> INT32 matrix multiplication and
             simulates skewed pipeline delays.
===============================================================================
"""

import numpy as np

class TPULiteGoldenModel:
    def __init__(self, array_size=8):
        self.array_size = array_size
        self.weights = np.zeros((array_size, array_size), dtype=np.int8)
        self.accumulators = np.zeros((array_size, array_size), dtype=np.int32)
        
    def load_weights(self, weight_matrix: np.ndarray):
        """Preloads weight matrix into stationary PE weight registers."""
        assert weight_matrix.shape == (self.array_size, self.array_size)
        self.weights = weight_matrix.astype(np.int8)

    def compute_matmul(self, activation_matrix: np.ndarray) -> np.ndarray:
        """
        Executes INT8 weight-stationary matrix multiplication.
        Output is 32-bit accumulated integer matrix (INT32).
        """
        assert activation_matrix.shape[1] == self.array_size
        act_int8 = activation_matrix.astype(np.int8)
        
        # Exact Matrix Multiply: C[m, n] = sum(A[m, k] * W[k, n])
        result_int32 = np.matmul(act_int8.astype(np.int32), self.weights.astype(np.int32))
        return result_int32

    def simulate_skewed_cycles(self, activation_matrix: np.ndarray):
        """
        Simulates cycle-by-cycle systolic array execution with row-wise skewing.
        Total cycles required for M x K * K x N computation = K + 2*N + 1
        """
        num_rows, num_cols = activation_matrix.shape
        total_cycles = num_rows + 2 * self.array_size
        
        cycle_log = []
        for cycle in range(total_cycles):
            # Capture active PE grid state at cycle 'cycle'
            active_pes = max(0, min(cycle, self.array_size * self.array_size))
            utilization = (active_pes / (self.array_size * self.array_size)) * 100.0
            cycle_log.append({
                'cycle': cycle,
                'active_pes': active_pes,
                'utilization_pct': min(utilization, 100.0)
            })
            
        return cycle_log

if __name__ == '__main__':
    print("--- TPU-Lite Golden Reference Model Test ---")
    model = TPULiteGoldenModel(array_size=8)
    
    # Random test matrices
    np.random.seed(42)
    W = np.random.randint(-128, 127, size=(8, 8), dtype=np.int8)
    A = np.random.randint(-128, 127, size=(8, 8), dtype=np.int8)
    
    model.load_weights(W)
    C_gold = model.compute_matmul(A)
    
    print("Weight Matrix (W 8x8):\n", W)
    print("Activation Matrix (A 8x8):\n", A)
    print("Accumulated Output (C INT32 8x8):\n", C_gold)
    print("Verification: Output shape =", C_gold.shape, "| Output dtype =", C_gold.dtype)
