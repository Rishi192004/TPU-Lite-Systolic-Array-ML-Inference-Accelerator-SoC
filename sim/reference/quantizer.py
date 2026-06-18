#!/usr/bin/env python3
"""
===============================================================================
TPU-Lite: Matrix Quantization Engine
File: sim/reference/quantizer.py
Description: Quantizes floating-point PyTorch/NumPy tensor matrices into INT8
             signed integer format for hardware inference on TPU-Lite.
===============================================================================
"""

import numpy as np

class INT8Quantizer:
    @staticmethod
    def quantize_symmetric(matrix_fp32: np.ndarray):
        """
        Symmetric INT8 Quantization:
        scale = max(abs(matrix)) / 127
        int8_val = clamp(round(fp32_val / scale), -128, 127)
        """
        max_val = np.max(np.abs(matrix_fp32))
        if max_val == 0:
            scale = 1.0
        else:
            scale = max_val / 127.0
            
        quantized = np.clip(np.round(matrix_fp32 / scale), -128, 127).astype(np.int8)
        return quantized, scale

    @staticmethod
    def dequantize(matrix_int32: np.ndarray, scale_a: float, scale_w: float) -> np.ndarray:
        """Dequantizes INT32 accumulated output back to FP32 float tensor."""
        scale_out = scale_a * scale_w
        return matrix_int32.astype(np.float32) * scale_out

if __name__ == '__main__':
    print("--- TPU-Lite Quantization Engine Demo ---")
    fp32_weights = np.random.randn(8, 8).astype(np.float32) * 2.5
    int8_w, s_w = INT8Quantizer.quantize_symmetric(fp32_weights)
    print("FP32 Matrix Range:", np.min(fp32_weights), "to", np.max(fp32_weights))
    print("INT8 Quantized Matrix:\n", int8_w)
    print("Scale factor:", s_w)
