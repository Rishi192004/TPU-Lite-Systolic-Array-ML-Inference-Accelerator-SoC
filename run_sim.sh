#!/usr/bin/env bash
# ============================================================================
# TPU-Lite: WSL Simulation Runner
# Usage: wsl bash run_sim.sh   (from TpuLite directory)
# ============================================================================

set -e
PROJ_ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "[1/3] Compiling RTL (Icarus Verilog iverilog -g2012)..."
iverilog -g2012 -Wall \
    -o /tmp/tb_systolic.vvp \
    "$PROJ_ROOT/rtl/pe/pe_mac_csa.sv" \
    "$PROJ_ROOT/rtl/pe/processing_element.sv" \
    "$PROJ_ROOT/rtl/systolic/systolic_array_8x8.sv" \
    "$PROJ_ROOT/sim/tb/tb_systolic_self_check.sv"

echo "[2/3] Running simulation (vvp)..."
vvp /tmp/tb_systolic.vvp

echo "[3/3] Simulation complete."
