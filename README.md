# Systolic-array matrix multiplier: (RTL + testbenches)

N x N output-stationary systolic array computing C = A x B with signed fixed-point operands.
Defaults: N = 3, DATA_W = 8 (signed), ACC_W = 20 (signed accumulator).

## Architecture diagrams

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the shared host protocol,
systolic PE dataflow, controller states, and sequential baseline diagrams.

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
    gtkwave systolic_matmul.vcd      # waveform of the demo test (T1)

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
- The comparison includes one start-acceptance cycle in compute latency and
  reports end-to-end cycles as loading + start acceptance + compute

The comparison testbench measures these cycle counts for both designs using
the same input matrices. At its assumed 100 MHz clock (10 ns period), its
reported results are:

| N | Design | Compute cycles | Compute latency | Compute rate | End-to-end cycles | End-to-end latency |
|---|---|---:|---:|---:|---:|---:|
| 3 | Systolic | 8 | 80 ns | 12.500 M matrix multiplies/s | 27 | 270 ns |
| 3 | Sequential | 28 | 280 ns | 3.571 M matrix multiplies/s | 47 | 470 ns |
| 4 | Systolic | 11 | 110 ns | 9.091 M matrix multiplies/s | 44 | 440 ns |
| 4 | Sequential | 65 | 650 ns | 1.538 M matrix multiplies/s | 98 | 980 ns |

Compute speedup, calculated as sequential compute cycles divided by systolic
compute cycles, is 3.500x for 3x3 and 5.909x for 4x4. End-to-end counts include
the common `2N^2` load cycles and one start-acceptance cycle. Rates are derived
from simulated cycles and the assumed clock; they are not FPGA timing or
hardware measurements.

## Accumulator width

Worst case is (-128) * (-128) = 16384 in every term, so the largest sum is N * 16384.
3x3 needs 17 signed bits, 4x4 needs 18. The default ACC_W = 20 leaves headroom.

## Still to do

FPGA synthesis and timing (resources + maximum frequency), technical report,
demo procedure.
