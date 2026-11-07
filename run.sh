#!/usr/bin/env bash
# Compile and run both testbenches with Icarus Verilog.
#   ./run.sh        -> 3x3 array (default)
#   ./run.sh 4      -> 4x4 array
set -e
cd "$(dirname "$0")"
N=${1:-3}

RTL="rtl/mac_unit.v rtl/pe.v rtl/systolic_array.v rtl/input_buffer.v \
     rtl/matrix_data_interface.v rtl/systolic_ctrl.v rtl/systolic_matmul_top.v"

iverilog -g2005 -o sim_pe.vvp rtl/mac_unit.v rtl/pe.v tb/tb_pe.v
vvp sim_pe.vvp

iverilog -g2005 -P tb_systolic_matmul.N="$N" -o sim_matmul.vvp $RTL tb/tb_systolic_matmul.v
vvp sim_matmul.vvp

echo "Waveforms:  gtkwave tb_pe.vcd    gtkwave systolic_matmul.vcd"
