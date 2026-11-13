#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for tool in yosys nextpnr-ice40; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Required tool not found: %s\n' "$tool" >&2
        exit 1
    fi
done

out_dir="$repo_root/build/ice40-hx8k"
mkdir -p "$out_dir"

for design in systolic sequential; do
    for n in 3 4; do
        top="${design}_matmul_top"
        if [[ "$design" == "systolic" ]]; then
            sources="rtl/mac_unit.v rtl/pe.v rtl/systolic_array.v rtl/input_buffer.v rtl/matrix_data_interface.v rtl/systolic_ctrl.v rtl/systolic_matmul_top.v"
        else
            sources="rtl/sequential_matmul_top.v"
        fi

        prefix="$out_dir/${design}_n${n}"
        yosys -Q -T -p \
            "read_verilog ${sources}; chparam -set N ${n} ${top}; synth_ice40 -top ${top} -device hx -json ${prefix}.json; stat" \
            > "${prefix}_yosys.log" 2>&1

        nextpnr-ice40 --hx8k --package ct256 --freq 100 --seed 1 \
            --timing-allow-fail --json "${prefix}.json" \
            --pcf-allow-unconstrained --report "${prefix}_report.json" \
            > "${prefix}_nextpnr.log" 2>&1
    done
done

printf 'iCE40 HX8K-CT256 estimates written to %s\n' "$out_dir"
