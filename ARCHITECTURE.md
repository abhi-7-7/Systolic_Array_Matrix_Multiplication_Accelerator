# Architecture

This project provides two implementations of `C = A x B` with the same
element-write, start/status, and indexed-result-read interface:

- The systolic implementation computes all outputs in parallel with an
  output-stationary `N x N` processing-element (PE) array.
- The sequential baseline reuses one multiply-accumulate (MAC) datapath for
  every output element.

The default configuration is `N = 3`, signed 8-bit operands, and signed 20-bit
accumulators. The diagrams show the parameterized structure; the PE grid is
drawn as 3x3 for readability.

## Shared host protocol

```mermaid
flowchart LR
    HOST["Host / testbench"]
    SYS["Systolic top"]
    SEQ["Sequential top"]

    HOST -->|"wr_en, wr_sel, address, data"| SYS
    HOST -->|"wr_en, wr_sel, address, data"| SEQ
    HOST -->|"rst, start"| SYS
    HOST -->|"rst, start"| SEQ
    SYS -->|"busy, done"| HOST
    SEQ -->|"busy, done"| HOST
    HOST -->|"rd_row, rd_col"| SYS
    HOST -->|"rd_row, rd_col"| SEQ
    SYS -->|"rd_data"| HOST
    SEQ -->|"rd_data"| HOST
```

Write A with `wr_sel = 0` and B with `wr_sel = 1`, one element per clock.
Writes are ignored while `busy` is high. Pulse `start` for one clock in `IDLE`
or `DONE`, wait for `done`, then read each result by its row and column.
`done` stays high until another accepted start. `rst` is synchronous and
returns the controller to `IDLE`; matrix storage is not cleared by reset.

## Systolic implementation

```mermaid
flowchart LR
    HOST["Host write port"]
    CTRL["systolic_ctrl<br/>IDLE / CLEAR / RUN / DONE<br/>cycle counter t"]
    subgraph MDI["matrix_data_interface"]
        ASTORE["N row buffers<br/>A[i][0..N-1]"]
        BSTORE["N column buffers<br/>B[0..N-1][j]"]
        SKEW["Skewed stream generation<br/>lane i starts at t = i<br/>zero outside its N-cycle window"]
        ASTORE --> SKEW
        BSTORE --> SKEW
    end
    subgraph ARRAY["systolic_array: output-stationary PE grid"]
        direction TB
        R0["PE(0,0) → PE(0,1) → PE(0,2)"]
        R1["PE(1,0) → PE(1,1) → PE(1,2)"]
        R2["PE(2,0) → PE(2,1) → PE(2,2)"]
        R0 -->|"B moves down"| R1
        R1 -->|"B moves down"| R2
    end
    RESULT["C accumulators<br/>one per PE"]
    MUX["Indexed result mux<br/>rd_row, rd_col"]
    HOSTREAD["Host rd_data"]

    HOST -->|"wr_en, wr_sel, address, data"| MDI
    CTRL -->|"run, t"| MDI
    SKEW -->|"A lanes enter from left"| ARRAY
    SKEW -->|"B lanes enter from top"| ARRAY
    CTRL -->|"clr"| ARRAY
    ARRAY --> RESULT
    RESULT --> MUX
    MUX --> HOSTREAD
```

Each PE forwards A one column to the right and B one row downward while
accumulating `A[i][k] * B[k][j]` locally into `C[i][j]`. The input interface
delays lane `i` by `i` clocks so each PE receives matching operands at
`t = i + j + k`. The controller asserts `clr` in `CLEAR`, then streams inputs
in `RUN`; for an `N x N` array, `RUN` lasts `3N - 2` clocks.

### PE dataflow

```mermaid
flowchart LR
    AIN["a_in"] --> MAC["Signed multiply<br/>and accumulate"]
    BIN["b_in"] --> MAC
    ACC["accumulator<br/>C[i][j]"] --> MAC
    MAC --> ACC
    AIN -->|"registered forward"| AOUT["a_out → next PE"]
    BIN -->|"registered forward"| BOUT["b_out ↓ next PE"]
    CLR["clr"] -.->|"synchronous clear"| ACC
    CLR -.->|"synchronous clear"| AOUT
    CLR -.->|"synchronous clear"| BOUT
```

## Sequential baseline

```mermaid
flowchart LR
    HOST["Host write port"]
    subgraph SEQ["sequential_matmul_top"]
        AMEM["A matrix memory"]
        BMEM["B matrix memory"]
        CTRL["Controller<br/>IDLE / CLEAR / RUN / DONE<br/>row_idx, col_idx, k_idx"]
        MAC["Single signed MAC<br/>A[row,k] × B[k,col] + accumulator"]
        ACC["Working accumulator"]
        CMEM["C matrix memory"]
        AMEM --> MAC
        BMEM --> MAC
        CTRL -->|"select row, col, k"| MAC
        ACC --> MAC
        MAC --> ACC
        MAC -->|"after final k for output"| CMEM
        CTRL -->|"advance row-major output"| CTRL
    end
    READ["Indexed result mux<br/>rd_row, rd_col"]
    HOSTREAD["Host rd_data"]

    HOST -->|"wr_en, wr_sel, address, data"| AMEM
    HOST -->|"wr_en, wr_sel, address, data"| BMEM
    HOST -->|"rst, start"| CTRL
    CTRL -->|"busy, done"| HOST
    CMEM --> READ
    READ --> HOSTREAD
```

In `RUN`, the controller iterates `k` for each output coordinate, then stores
the completed sum in C and advances through outputs in row-major order. The
same single MAC is reused for every output; computation takes `N^3` MAC clocks,
plus the one-clock `CLEAR` phase. Both implementations expose the same host
write and indexed-read behavior, but use separate top-level modules.

## Controller state transitions

```mermaid
stateDiagram-v2
    [*] --> IDLE: rst
    IDLE --> CLEAR: start
    CLEAR --> RUN: next clock
    RUN --> RUN: more compute cycles
    RUN --> DONE: final output / final systolic cycle
    DONE --> DONE: hold result
    DONE --> CLEAR: start
```

`rst` synchronously returns either controller to `IDLE`. In the systolic
implementation, `CLEAR` clears every PE accumulator and forwarding register.
In the sequential baseline, `CLEAR` initializes its working accumulator and
iteration indices. In both, `busy` is high in `CLEAR` and `RUN`; `done` is high
in `DONE`.
