# Systolic-array matrix multiplier: (RTL + testbenches)

N x N output-stationary systolic array computing C = A x B with signed fixed-point operands.
Defaults: N = 3, DATA_W = 8 (signed), ACC_W = 20 (signed accumulator).

## Files

    rtl/mac_unit.v               combinational multiply-accumulate
    rtl/pe.v                     processing element = MAC + accumulator + pass-through registers
    rtl/systolic_array.v         N x N grid of PEs (generate loops)
    rtl/input_buffer.v           small buffer holding one row of A or one column of B
    rtl/matrix_data_interface.v  write port + 2N input buffers + skewed streaming
    rtl/systolic_ctrl.v          Moore FSM IDLE -> CLEAR -> RUN -> DONE + cycle counter
    rtl/systolic_matmul_top.v    top level: load A/B, start, wait for done, read C
    tb/tb_pe.v                   PE testbench (directed + random)
    tb/tb_systolic_matmul.v      whole accelerator vs reference model, latency check, cycle trace
    run.sh                       compile and run both testbenches

## Module hierarchy

    systolic_matmul_top
    |-- systolic_ctrl
    |-- matrix_data_interface
    |   `-- input_buffer   (x 2N)
    `-- systolic_array
        `-- pe             (x N^2)
            `-- mac_unit

## Run (needs Icarus Verilog; GTKWave is optional)

    ./run.sh          # 3x3
    ./run.sh 4        # 4x4
    gtkwave systolic_matmul.vcd      # waveform of the demo test (T1)

## Timing of one multiplication

- RUN phase: 3N - 2 cycles from first input to last MAC (7 for 3x3, 10 for 4x4)
- plus 1 CLEAR cycle, so the accelerator is busy for 3N - 1 cycles

## Accumulator width

Worst case is (-128) * (-128) = 16384 in every term, so the largest sum is N * 16384.
3x3 needs 17 signed bits, 4x4 needs 18. The default ACC_W = 20 leaves headroom.

## To be done 

Sequential baseline, cycle/throughput analysis, synthesis (resources + max frequency),
block diagram, technical report, demo script.
