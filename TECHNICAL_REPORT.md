# Simulation-Based Technical Report

## Scope

This report documents the RTL architecture, functional verification, and
cycle-based comparison of the systolic and sequential matrix multipliers. It
does not claim FPGA implementation, resource utilization, or hardware timing
results. No physical target was selected, and FPGA synthesis/place-and-route
tools are not configured in this environment.

## Design summary

Both top-level designs compute `C = A x B` for signed integer matrices:

- Default configuration: `N = 3`, signed 8-bit inputs, signed 20-bit
  accumulators.
- Additional tested configuration: `N = 4`, with the same widths.
- The systolic design uses an output-stationary `N x N` PE grid. A values
  travel horizontally, B values vertically, and each PE accumulates one C
  element.
- The sequential baseline reuses one signed MAC and stores outputs in
  row-major order.
- Both designs provide the same one-element-per-clock matrix write interface,
  start/busy/done control, and indexed result read.

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the block, dataflow, and controller
diagrams.

## Verification method

The testbenches use Icarus Verilog and compare computed values against integer
reference models. They exercise PE arithmetic and forwarding, directed and
random matrix inputs, signed extremes, reset/restart behavior, writes while
busy, completion latency, and side-by-side results. The sequential test also
checks 200 randomized matrix pairs.

The complete suite was run for both supported configurations:

```bash
./run.sh
./run.sh 4
```

Both runs completed successfully. The simulator used for this run was Icarus
Verilog 13.0 (`iverilog` and `vvp`).

## Cycle-based comparison

The comparison testbench assumes a 100 MHz clock (10 ns per cycle). This is a
simulation assumption, not a clock constraint or measured operating frequency.
Compute counts include the accepted start cycle; end-to-end counts include
loading both matrices and compute, but exclude reading the result matrix.

| Matrix size | Systolic compute | Sequential compute | Compute cycle speedup | Systolic end-to-end | Sequential end-to-end |
|---|---:|---:|---:|---:|---:|
| 3x3 | 8 cycles / 80 ns | 28 cycles / 280 ns | 3.500x | 27 cycles / 270 ns | 47 cycles / 470 ns |
| 4x4 | 11 cycles / 110 ns | 65 cycles / 650 ns | 5.909x | 44 cycles / 440 ns | 98 cycles / 980 ns |

Both designs load one matrix element per clock through the shared write port.
Loading A and B therefore takes 18 cycles for 3x3 and 32 cycles for 4x4.
End-to-end cycles add the start-acceptance cycle and the compute interval.
The speedup is the sequential compute-cycle count divided by the systolic
compute-cycle count.

The systolic controller spends one cycle in `CLEAR`, then streams operands
over `3N - 2` run cycles. The sequential baseline spends one clear cycle and
uses `N^3` MAC cycles. These counts describe the current RTL protocol and
testbench measurements; they do not represent a throughput result under
physical timing constraints.

## Interpretation and limitations

The simulation confirms functional behavior and demonstrates fewer compute
cycles for the systolic architecture at both tested sizes. It does not show
that either design meets a particular clock frequency or occupies fewer
resources on an FPGA. The following hardware-specific results remain
unavailable:

- LUT/logic, flip-flop, DSP, and memory utilization.
- Static timing, maximum frequency, and critical-path reports.
- Place-and-route results for a specific device.

No FPGA target or implementation toolchain was configured, and no FPGA
synthesis tool was available in the checked environment. The 100 MHz
assumption must not be used to infer a maximum frequency or measured hardware
performance. Operands are signed integers; no fractional Q-format is defined.

## Demo procedure

From the repository root, with Icarus Verilog installed:

```bash
./run.sh       # Run the suite with N = 3
./run.sh 4     # Run the suite with N = 4
```

Each run builds and executes the PE, systolic, sequential, and side-by-side
testbenches. The final comparison should report `COMPARISON PASSED` and the
cycle counts shown above. The simulation also writes VCD waveform files. To
inspect a waveform, install GTKWave and run, for example:

```bash
gtkwave systolic_matmul.vcd
```
