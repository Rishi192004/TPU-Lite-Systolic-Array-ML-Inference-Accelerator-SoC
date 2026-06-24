@echo off
REM TPU-Lite Vivado Batch Synthesis Command Script
echo Running Vivado Synthesis for TPU-Lite (Artix-7 @ 250 MHz)...
vivado -mode batch -source synth.tcl
pause
