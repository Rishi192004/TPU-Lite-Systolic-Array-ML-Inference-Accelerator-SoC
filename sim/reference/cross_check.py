#!/usr/bin/env python3
"""
===============================================================================
TPU-Lite: RTL vs Golden-Model Cross-Check
File: sim/reference/cross_check.py

Reads test_vectors.hex (produced by generate_vectors.py) and independently
re-computes every expected matrix using NumPy INT32 arithmetic, then compares
byte-for-byte against the hex file's stored expected values.

This is separate from generate_vectors.py — it uses the STORED hex output as
the "DUT reference" and re-derives answers from scratch to catch bugs in the
generator itself.
===============================================================================
"""

import sys
import os
import numpy as np

HEX_FILE = os.path.join(os.path.dirname(__file__), "..", "tb", "test_vectors.hex")

def read_int8_row(hex_str):
    """Parse a 64-byte (128 hex char) weight/activation row into int8 array."""
    assert len(hex_str) == 128, f"Expected 128 hex chars, got {len(hex_str)}"
    vals = []
    for i in range(0, 128, 2):
        byte = int(hex_str[i:i+2], 16)
        # sign-extend
        if byte >= 128:
            byte -= 256
        vals.append(byte)
    return np.array(vals, dtype=np.int8).reshape(8, 8)

def read_int32_row(hex_str):
    """Parse a 256-byte (512 hex char) result row into int32 array."""
    assert len(hex_str) == 512, f"Expected 512 hex chars, got {len(hex_str)}"
    vals = []
    for i in range(0, 512, 8):
        word = int(hex_str[i:i+8], 16)
        # sign-extend 32-bit
        if word >= 0x80000000:
            word -= 0x100000000
        vals.append(word)
    return np.array(vals, dtype=np.int32).reshape(8, 8)

def main():
    if not os.path.exists(HEX_FILE):
        print(f"[ERROR] test_vectors.hex not found at: {HEX_FILE}")
        print("        Run generate_vectors.py first.")
        sys.exit(1)

    print(f"[*] Cross-checking test vectors from: {HEX_FILE}")

    total = 0
    errors = 0
    vec_idx = -1

    W = A = C_stored = None

    with open(HEX_FILE) as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("//"):
                # New vector header
                if line.startswith("// Vector #"):
                    vec_idx = int(line.split("#")[1])
                    W = A = C_stored = None
                continue

            if W is None:
                W = read_int8_row(line)
            elif A is None:
                A = read_int8_row(line)
            elif C_stored is None:
                C_stored = read_int32_row(line)

                # We have a full vector — cross-check now
                C_golden = np.matmul(A.astype(np.int32), W.astype(np.int32))
                total += 1

                if not np.array_equal(C_golden, C_stored):
                    print(f"[FAIL] Vector #{vec_idx}: golden != stored")
                    print(f"  Golden:\n{C_golden}")
                    print(f"  Stored:\n{C_stored}")
                    errors += 1
                else:
                    if total <= 5 or vec_idx < 5:
                        print(f"  [OK] Vector #{vec_idx}: 64 elements match")

    print()
    print("=" * 56)
    print("         CROSS-CHECK SUMMARY")
    print("=" * 56)
    print(f"  Vectors checked : {total}")
    print(f"  Mismatches      : {errors}")
    if errors == 0:
        print("  VERDICT         : PASSED — all stored vectors match golden")
    else:
        print(f"  VERDICT         : FAILED — {errors} mismatches detected")
    print("=" * 56)

    sys.exit(0 if errors == 0 else 1)

if __name__ == "__main__":
    main()
