# Systolic-array matrix multiplier: (RTL + testbenches)

N x N output-stationary systolic array computing C = A x B. Defaults: N = 3,
signed 8-bit operands, signed 20-bit accumulators. The current arithmetic uses
signed integer values (fixed point with zero fractional bits; scale = 1).

## Architecture diagrams

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the shared host protocol,
systolic PE dataflow, controller states, and sequential baseline diagrams.

## Simulation report and demo

See [TECHNICAL_REPORT.md](./TECHNICAL_REPORT.md) for verification details,
cycle-based results, iCE40 tool estimates, limitations, and the demo procedure.

## Files

    rtl/mac_unit.v               combinational multiply-accumulate
    rtl/pe.v                     processing element = MAC + accumulator + pass-through registers
    rtl/systolic_array.v         N x N grid of PEs (generate loops)
    rtl/input_buffer.v           small buffer holding one row of A or one column of B
    rtl/matrix_data_interface.v  write port + 2N input buffers + skewed streaming
    rtl/systolic_ctrl.v          Moore FSM IDLE -> CLEAR -> RUN -> DONE + cycle counter
    rtl/systolic_matmul_top.v    top level: load A/B, start, wait for done, read C
    rtl/sequential_matmul_top.v  one-MAC sequential baseline with matching host interface
    tb/tb_pe.v                   PE testbench (directed + random)
    tb/tb_systolic_matmul.v      whole accelerator vs reference model, latency check, cycle trace
    tb/tb_sequential_matmul.v    sequential baseline vs reference model and latency checks
    tb/tb_matmul_comparison.v    side-by-side latency and throughput comparison
    run.sh                       compile and run all four testbenches
    systolic_matmul.gtkw         GTKWave view: control signals, input streams, PE accumulators
    scripts/run_ice40_estimates.sh  Yosys/nextpnr estimates for iCE40 HX8K

## Module hierarchy

    systolic_matmul_top
    |-- systolic_ctrl
    |-- matrix_data_interface
    |   `-- input_buffer   (x 2N)
    `-- systolic_array
        `-- pe             (x N^2)
            `-- mac_unit

The sequential baseline is a separate top level with the same write, start,
status, and indexed result-read interface. It stores A and B, then uses one
signed multiplier-accumulator to compute each output in row-major order.

## Run (needs Icarus Verilog; GTKWave is optional)

    ./run.sh          # 3x3
    ./run.sh 4        # 4x4
    gtkwave systolic_matmul.vcd systolic_matmul.gtkw   # waveform of the demo test (T1)

The saved view shows `clk`, `start`, `busy`, `done`, the controller state and
cycle counter, the skewed A/B input streams, and a few PE accumulators. It
targets the default 3x3 build; for `./run.sh 4` the bus widths differ.

The final test run compares both designs side by side using the same random
matrices and 100 MHz simulation clock assumption. It checks both results against
the same reference and reports compute-only and load-inclusive cycle rates.
These are cycle-based simulation results, not measured FPGA maximum-frequency
or hardware-throughput results.

## Timing of one multiplication

- RUN phase: 3N - 2 cycles from first input to last MAC (7 for 3x3, 10 for 4x4)
- plus 1 CLEAR cycle, so the accelerator is busy for 3N - 1 cycles
- Sequential baseline: N^3 MAC cycles plus 1 CLEAR cycle, so it is busy for
  N^3 + 1 cycles (28 for 3x3, 65 for 4x4), excluding matrix loading
- Both designs use the same one-element-per-clock matrix write interface;
  loading both matrices takes 2N^2 cycles when included
- Compute counts are the `busy` interval (`CLEAR` plus computation); the
  separate start-acceptance cycle is included in end-to-end counts

The comparison testbench measures these cycle counts for both designs using
the same input matrices. At its assumed 100 MHz clock (10 ns period), its
reported results are:

| N | Design | Compute cycles | Compute latency | Compute rate | End-to-end cycles | End-to-end latency |
|---|---|---:|---:|---:|---:|---:|
| 3 | Systolic | 8 | 80 ns | 12.500 M matrix multiplies/s | 27 | 270 ns |
| 3 | Sequential | 28 | 280 ns | 3.571 M matrix multiplies/s | 47 | 470 ns |
| 4 | Systolic | 11 | 110 ns | 9.091 M matrix multiplies/s | 44 | 440 ns |
| 4 | Sequential | 65 | 650 ns | 1.538 M matrix multiplies/s | 98 | 980 ns |

Compute cycle speedup, calculated as sequential compute cycles divided by
systolic compute cycles, is 3.500x for 3x3 and 5.909x for 4x4. At each
design's estimated iCE40 Fmax, the wall-clock speedup is 4.58x and 7.41x; see
[TECHNICAL_REPORT.md](./TECHNICAL_REPORT.md). End-to-end counts include
the common `2N^2` load cycles and one start-acceptance cycle. Rates are derived
from simulated cycles and the assumed clock; they are not FPGA timing or
hardware measurements.

## Accumulator width

Worst case is (-128) * (-128) = 16384 in every term, so the largest sum is N * 16384.
3x3 needs 17 signed bits, 4x4 needs 18. The default ACC_W = 20 leaves headroom.

## FPGA tool estimate (no board required)

Install Yosys and nextpnr-ice40, then run:

    brew install yosys nextpnr-ice40
    bash scripts/run_ice40_estimates.sh

This performs target-specific estimates for iCE40 HX8K-CT256. See
[TECHNICAL_REPORT.md](./TECHNICAL_REPORT.md) for the results and limitations.
Physical board programming/testing remains optional and has not been performed.
