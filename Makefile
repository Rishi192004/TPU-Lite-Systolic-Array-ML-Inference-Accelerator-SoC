# ============================================================================
# TPU-Lite Accelerator SoC - Master Makefile
# ============================================================================

.PHONY: all clean golden vectors cross-check sim sim-sv synth help

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
	@echo "[*] Running Cocotb AXI4-Lite Simulation..."
	cd sim/cocotb && $(MAKE) SIM=icarus

sim-sv:
	@echo "[*] Running SystemVerilog Self-Checking Testbench..."
	bash run_sim.sh

cross-check:
	@echo "[*] Cross-checking generated hex test vectors..."
	$(PYTHON) sim/reference/cross_check.py

synth:
	@echo "[*] Launching Vivado Synthesis @ 250 MHz on Artix-7..."
	cd synth/scripts && $(VIVADO) -mode batch -source synth.tcl

clean:
	rm -rf sim/tb/*.hex synth/synth_build sim/cocotb/sim_build __pycache__
	@echo "[*] Clean complete."

help:
	@echo "TPU-Lite Build System Options:"
	@echo "  make golden      - Run Python cycle-accurate model test"
	@echo "  make vectors     - Generate 10,000+ test vectors"
	@echo "  make cross-check - Validate stored hex vectors against NumPy reference"
	@echo "  make sim-sv      - Run SystemVerilog 8x8 array testbench (iverilog)"
	@echo "  make sim         - Run Cocotb AXI4-Lite test suite"
	@echo "  make synth       - Run Vivado synthesis targeting Artix-7 (if Vivado installed)"
	@echo "  make clean       - Remove build artifacts"
