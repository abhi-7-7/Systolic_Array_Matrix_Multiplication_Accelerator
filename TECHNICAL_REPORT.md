# Simulation-Based Technical Report

## Scope

This report documents the RTL architecture, functional verification,
cycle-based comparison, and board-free FPGA tool estimates for the systolic
and sequential matrix multipliers. No physical FPGA board was used; resource
and timing figures are tool estimates, not measurements from hardware.

## Design summary

Both top-level designs compute `C = A x B` for signed integer matrices. This
version interprets the integer representation as fixed point with zero
fractional bits (scale = 1); it does not encode sub-integer fractions.

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
Compute counts are the `busy` interval (`CLEAR` plus computation); end-to-end
counts include loading both matrices, the separate start-acceptance cycle, and
the busy interval, but exclude reading the result matrix.

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

## FPGA synthesis and timing estimates

Both top levels were synthesized and placed/routed for an **iCE40 HX8K-CT256**
using Yosys 0.71, nextpnr-ice40 0.11.1_2, and IceStorm 1.1_1. The target clock
was 100 MHz and the placement seed was fixed at 1. No PCF pin constraints or
external input/output delay constraints were supplied; nextpnr automatically
placed the top-level pins. HX8K has no hard DSP blocks, so multiplier logic is
implemented in LUTs.

| Design | N | LUT4 | Flip-flops | iCE40 logic cells (of 7680) | RAM (of 32) | DSP | I/O pins (of 206) | Estimated Fmax |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Systolic | 3 | 2553 | 428 | 2797 (36.4%) | 0 | 0 | 43 | 65.89 MHz |
| Sequential | 3 | 634 | 352 | 986 (12.8%) | 0 | 0 | 43 | 50.35 MHz |
| Systolic | 4 | 4475 | 776 | 4926 (64.1%) | 0 | 0 | 43 | 63.09 MHz |
| Sequential | 4 | 829 | 604 | 1428 (18.6%) | 0 | 0 | 43 | 50.29 MHz |

The estimated critical clock path runs from the systolic cycle counter `t` to
a PE accumulator (`c_flat`) in the systolic design, and from the sequential
index logic (`row_idx`/`k_idx`) to the C result memory in the baseline. All four
estimates miss the requested 100 MHz target.

The initially considered iCE40 UP5K-SG48 was not suitable for placing the full
top level: it needs 43 I/O pins while SG48 provides 39, and the 3x3 systolic
design maps to 9 DSP cells while UP5K provides 8. The larger HX8K-CT256 target
was used for the estimates above.

Reproduce the estimates (no board required) with:

```bash
brew install yosys nextpnr-ice40
bash scripts/run_ice40_estimates.sh
```

The script writes Yosys logs, nextpnr logs, and JSON reports under
`build/ice40-hx8k/`; build outputs are ignored by Git.

## Interpretation and limitations

The simulation confirms functional behavior and demonstrates fewer compute
cycles for the systolic architecture at both tested sizes. It does not show
that either design meets a particular clock frequency or occupies fewer
resources on an FPGA. The following results remain unavailable:

- Measurements from an actual FPGA board, including power and real clock
  behavior.
- Board-specific pin assignments, external I/O timing constraints, and
  validation that the full design integrates with a particular board.

The 100 MHz simulation assumption must not be used to infer maximum frequency
or measured hardware performance. Operands are signed integer values
(fixed-point with zero fractional bits, scale = 1); sub-integer fractions are
not implemented.

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
