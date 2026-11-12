#!/usr/bin/env bash
# Compile and run all testbenches with Icarus Verilog.
#   ./run.sh        -> 3x3 designs (default)
#   ./run.sh 4      -> 4x4 designs
set -e
cd "$(dirname "$0")"
N=${1:-3}

SYSTOLIC_RTL="rtl/mac_unit.v rtl/pe.v rtl/systolic_array.v rtl/input_buffer.v \
              rtl/matrix_data_interface.v rtl/systolic_ctrl.v rtl/systolic_matmul_top.v"

iverilog -g2005 -o sim_pe.vvp rtl/mac_unit.v rtl/pe.v tb/tb_pe.v
vvp sim_pe.vvp

iverilog -g2005 -P tb_systolic_matmul.N="$N" -o sim_matmul.vvp $SYSTOLIC_RTL tb/tb_systolic_matmul.v
vvp sim_matmul.vvp

iverilog -g2005 -P tb_sequential_matmul.N="$N" -o sim_sequential.vvp \
    rtl/sequential_matmul_top.v tb/tb_sequential_matmul.v
vvp sim_sequential.vvp

iverilog -g2005 -P tb_matmul_comparison.N="$N" -o sim_comparison.vvp \
    $SYSTOLIC_RTL rtl/sequential_matmul_top.v tb/tb_matmul_comparison.v
vvp sim_comparison.vvp

echo "Waveforms:  gtkwave tb_pe.vcd    gtkwave systolic_matmul.vcd    gtkwave sequential_matmul.vcd"
