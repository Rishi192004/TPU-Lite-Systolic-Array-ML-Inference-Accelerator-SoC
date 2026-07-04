# ============================================================================
# TPU-Lite Accelerator SoC - Master Makefile
# ============================================================================

.PHONY: all clean golden vectors sim synth help

PYTHON ?= python3
VIVADO ?= vivado

all: vectors sim

golden:
	@echo "[*] Running Python Golden Reference Model..."
	$(PYTHON) sim/reference/golden_model.py

vectors:
	@echo "[*] Generating 10,000+ Test Vectors and Validating Golden Model..."
	$(PYTHON) sim/reference/generate_vectors.py

sim:
	@echo "[*] Running SystemVerilog / Cocotb Simulation..."
	cd sim/cocotb && $(MAKE)

synth:
	@echo "[*] Launching Vivado Synthesis @ 250 MHz on Artix-7..."
	cd synth/scripts && $(VIVADO) -mode batch -source synth.tcl

clean:
	rm -rf sim/tb/*.hex synth/synth_build sim/cocotb/sim_build __pycache__
	@echo "[*] Clean complete."

help:
	@echo "TPU-Lite Build System Options:"
	@echo "  make golden   - Run Python cycle-accurate model test"
	@echo "  make vectors  - Generate 10,000+ test vectors"
	@echo "  make sim      - Run Cocotb/SystemVerilog simulation"
	@echo "  make synth    - Run Vivado synthesis targeting 250 MHz Artix-7"
	@echo "  make clean    - Remove build artifacts"
