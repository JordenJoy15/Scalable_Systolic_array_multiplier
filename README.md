# Scalable Systolic Array Multiplier

A parameterized, **output-stationary** systolic array for signed integer matrix multiplication, written in Verilog. The default configuration is an **8×8** array of INT8 MAC processing elements with 32-bit accumulators, but the array size, data width, and accumulation depth are all compile-time parameters, so the same RTL scales to larger arrays without changes.

This design targets FPGA acceleration of GEMM workloads (the core operation behind CNN inference). It is built around a fully-pipelined PE grid with a diagonal input-skew network for timing alignment, an FSM-driven compute/drain controller, an addressed output-drain path, and BRAM banking with double-buffer selection.

---

## Architecture

The datapath is a classic 2D output-stationary systolic array:

- **Activations** enter from the **left** (`in_side`) and flow rightward, one column per cycle.
- **Weights / second operand** enter from the **top** (`in_top`) and flow downward, one row per cycle.
- Each **PE** multiplies its two incoming operands and accumulates the product into a local register (`cout += in_side * in_top`). Because the accumulator stays put while operands stream through, the result of each dot product is *stationary* in the PE — hence *output-stationary*.
- After the accumulation window completes, results are **drained** out of the grid through an addressed buffer network and written to BRAM.

Inputs must reach the diagonal of PEs at the right cycle, so a **skew network** (shift registers of increasing depth per lane) staggers the input streams before they enter the array. A matching de-skew/drain sequence reads the accumulated results back out in order.

### Module overview

| Module | File | Role |
|---|---|---|
| `PE` | `PE.v` | Single processing element: signed multiply-accumulate, with data pass-through and enable/skew-reset propagation. |
| `systolic_array` | `systolic_array.v` | Top-level `array_no × array_no` PE grid, wired with generate blocks. Enable and skew-reset ripple diagonally through the array. |
| `shiftr` | `shiftregister.v` | Variable-depth shift register (the delay primitive used for skewing). |
| `fifo` | `fifo.v` | Diagonal skew network — instantiates per-lane shift registers of increasing depth to time-align inputs. |
| `systolic_array_control` | `control.v` | Control FSM (IDLE / COMPUTE). Drives `ena`, generates the `drain` and skew-reset pulses, and counts the accumulation window and drain sequence. |
| `buffer` | `buffer.v` | Per-column output-drain slot: selects a result word, and forward-propagates address / counter / drain signals. |
| `combined_buffer` | `combined_buffer.v` | Assembles `array_no` buffer slots into the full addressed drain path, with an `offset` for buffer placement. |
| `bram` | `single_bram.v` | Single-port synchronous BRAM (inferred block RAM). |
| `bramslot` | `row_bram.v` | A bank of `array_no` BRAMs (one lane per row/column). |
| `2x1_multiplexer` | `multiplexer_bram.v` | Registered 2:1 selector for double-buffered (ping-pong) memory selection. |

---

## Parameters

The design is scaled through parameters rather than edits:

| Parameter | Default | Meaning |
|---|---|---|
| `WIDTH` | `8` | Bit width of each signed operand (INT8 by default). |
| `array_no` | `8` | Array dimension → `array_no × array_no` PEs. |
| `DEPTH` | `1024` | Accumulation depth / BRAM depth (number of MACs per output before drain). |

The PE accumulator is `4*WIDTH` bits wide (32 bits at the default `WIDTH`), sized to hold the running sum without overflow across the accumulation window.

---

## Data flow (one pass)

1. **Load / stream** — operands are read out of the input BRAM banks and pushed through the `fifo` skew network so each lane is delayed by its diagonal offset.
2. **Compute** — the controller asserts `ena`; skewed operands stream into the array and every PE accumulates its dot-product in place for `DEPTH` cycles.
3. **Drain** — when the accumulation window ends, the controller pulses `drain`/`skew_reset`; results are shifted out through `combined_buffer`, each tagged with its write address.
4. **Writeback** — drained results land in the output BRAM bank. The `2x1_multiplexer` selects between buffers so the next tile can load while the current results are read out (ping-pong / double-buffering).

---

## Repository structure

```
.
└── rtl/
    ├── PE.v                 # processing element (signed MAC)
    ├── systolic_array.v     # top-level PE grid
    ├── shiftregister.v      # variable-depth shift register
    ├── fifo.v               # diagonal skew network
    ├── control.v            # compute/drain control FSM
    ├── buffer.v             # single output-drain slot
    ├── combined_buffer.v    # full addressed drain path
    ├── single_bram.v        # single-port BRAM
    ├── row_bram.v           # BRAM bank
    └── multiplexer_bram.v   # 2:1 ping-pong selector
```

---

## Status

**Done**
- Parameterized output-stationary PE and full `array_no × array_no` array
- Diagonal input-skew network
- Compute/drain control FSM
- Addressed output-drain buffer path
- BRAM banking and double-buffer selection mux

**In progress / roadmap**
- Verification: self-checking testbench with a software golden model
- Top-level integration (memory ↔ skew ↔ array ↔ drain) and simulation waveforms
- FPGA bring-up: synthesis, timing closure, and on-board validation
- Host interface (AXI / DMA) for streaming tiles to and from the accelerator

---

## Author

**Jorden Joy** — Electronics & Communication Engineering, BITS Pilani
GitHub: [@JordenJoy15](https://github.com/JordenJoy15)
