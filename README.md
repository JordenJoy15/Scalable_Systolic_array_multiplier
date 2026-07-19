# Scalable Systolic Array Multiplier

A parameterized, **output-stationary** systolic array for signed integer matrix
multiplication, written in Verilog. The default configuration is an **8×8**
array of INT8 MAC processing elements with 32-bit accumulators, but the array
size, data width, and accumulation depth are all compile-time parameters, so
the same RTL scales to larger arrays without changes.

**Functionally verified:** the core passes a full cocotb regression against a
NumPy golden model — element-exact `C = A @ B` across a randomized K-sweep,
signed extremes, and multi-tile runs. **7 / 7 tests passing.** See
[Verification](#verification).

This design targets FPGA acceleration of GEMM workloads (the core operation
behind CNN inference). It is built around a fully-pipelined PE grid with a
diagonal input-skew network for timing alignment, an FSM-driven compute/drain
controller, an addressed output-drain path, and BRAM banking with
double-buffer selection.

---

## Architecture

The datapath is a classic 2D output-stationary systolic array:

- **Activations** enter from the **left** (`in_side`) and flow rightward, one
  column per cycle.
- **Weights / second operand** enter from the **top** (`in_top`) and flow
  downward, one row per cycle.
- Each **PE** multiplies its two incoming operands and accumulates the product
  into a local register (`cout += in_side * in_top`). Because the accumulator
  stays put while operands stream through, the result of each dot product is
  *stationary* in the PE — hence *output-stationary*.
- After the accumulation window completes, results are **drained** out of the
  grid through an addressed buffer network and written to BRAM.

Inputs must reach the diagonal of PEs at the right cycle, so a **skew
network** (shift registers of increasing depth per lane) staggers the input
streams before they enter the array. At end-of-tile, two diagonal wavefronts
chase each other through the grid: an 8-lane **drain sweep** that serializes
all 64 accumulators (8 beats per lane, lane *i* lagging lane 0 by *i*
cycles), followed one cycle behind by the **accumulator-reset wavefront**
that clears the array for the next tile. Sampling is race-free by
construction — each accumulator is read on the cycle before the reset zeroes
it.

### Module overview

| Module | File | Role |
| --- | --- | --- |
| `PE` | `rtl/PE.v` | Single processing element: signed multiply-accumulate, with data pass-through and enable/skew-reset propagation. |
| `systolic_array` | `rtl/systolic_array.v` | Top-level `array_no × array_no` PE grid, wired with generate blocks. Enable and skew-reset ripple diagonally through the array. |
| `shiftr` | `rtl/shiftregister.v` | Variable-depth shift register (the delay primitive used for skewing). |
| `fifo` | `rtl/fifo.v` | Diagonal skew network — instantiates per-lane shift registers of increasing depth to time-align inputs. |
| `core_wrap` | `rtl/core_wrap.v` | **Verified integration wrapper**: skew FIFOs + PE array + end-of-tile pulse generation + the 8-lane drain sweep sequencer. This is the DUT of the cocotb testbench. |
| `systolic_array_control` | `rtl/control.v` | Control FSM (IDLE / COMPUTE). Drives `ena`, generates the `drain` and skew-reset pulses, and counts the accumulation window and drain sequence. |
| `buffer` | `rtl/buffer.v` | Per-column output-drain slot: selects a result word, and forward-propagates address / counter / drain signals. |
| `combined_buffer` | `rtl/combined_buffer.v` | Assembles `array_no` buffer slots into the full addressed drain path, with an `offset` for buffer placement. |
| `bram` | `rtl/single_bram.v` | Single-port synchronous BRAM (inferred block RAM). |
| `bramslot` | `rtl/row_bram.v` | A bank of `array_no` BRAMs (one lane per row/column). |
| `2x1_multiplexer` | `rtl/multiplexer_bram.v` | Registered 2:1 selector for double-buffered (ping-pong) memory selection. |

---

## Parameters

| Parameter | Default | Meaning |
| --- | --- | --- |
| `WIDTH` | `8` | Bit width of each signed operand (INT8 by default). |
| `array_no` | `8` | Array dimension → `array_no × array_no` PEs. |
| `DEPTH` | `1024` | Accumulation depth / BRAM depth (number of MACs per output before drain). |

The PE accumulator is `4*WIDTH` bits wide (32 bits at the default `WIDTH`) —
with INT8 operands there is no overflow until K > 2¹⁷ accumulations.

---

## Verification

The core (`core_wrap`) is verified with **cocotb** (Icarus Verilog) against a
**NumPy golden model**: `C_ref = A.astype(int64) @ B.astype(int64)`. A driver
streams `A` (8×K, lane *i* = row *i*) and `B` (K×8, lane *j* = column *j*)
through the real feed protocol; a monitor reassembles the 8 drain lanes into
the 8×8 result; a scoreboard compares element-exact.

```
TEST                                  STATUS
test_k8_random        K=8 random      PASS
test_k1_minimum       K=1 degenerate  PASS
test_k64_deep         K=64 deep       PASS
test_identity         A=I → C=B       PASS
test_signed_extremes  ±extremes K=32  PASS
test_sequential_tiles 3 tiles         PASS
test_random_soak      10×, K∈[1,64]   PASS
```

### Feed protocol (required by the stream interface)

Two non-obvious rules — both cause silent wrong answers if violated:

1. **One leading zero beat.** `feed_en` must rise one cycle before the first
   data beat: the enable is registered (`ena_reg`) while skew lane 0 is a
   combinational passthrough, so starting data with `feed_en` drops beat 0 in
   every PE.
2. **`array_no−1` trailing zero pads, `feed_last` on the final pad.** The
   skew FIFOs are inside `core_wrap`, so the deepest lane lags by 7 cycles;
   firing `feed_last` on the last real beat launches the reset wavefront
   before those lanes flush. One K-deep tile therefore costs `1 + K + 7`
   feed cycles.

### Running the tests

```bash
sudo apt install iverilog
pip install cocotb numpy
cd tb
make        # runs all 7 tests
```

---

## Data flow (one pass)

1. **Load / stream** — operands are read out of the input BRAM banks and
   pushed through the `fifo` skew network so each lane is delayed by its
   diagonal offset.
2. **Compute** — the controller asserts `ena`; skewed operands stream into
   the array and every PE accumulates its dot-product in place for the
   reduction depth.
3. **Drain** — at end-of-tile the drain sweep serializes results out through
   `combined_buffer`, each tagged with its write address, while the reset
   wavefront cleans the array one cycle behind.
4. **Writeback** — drained results land in the output BRAM bank. The
   `2x1_multiplexer` selects between buffers so the next tile can load while
   the current results are read out (ping-pong / double-buffering).

---

## Repository structure

```
.
├── rtl/
│   ├── PE.v                 # processing element (signed MAC)
│   ├── systolic_array.v     # top-level PE grid
│   ├── shiftregister.v      # variable-depth shift register
│   ├── fifo.v               # diagonal skew network
│   ├── core_wrap.v          # verified integration wrapper (cocotb DUT)
│   ├── control.v            # compute/drain control FSM
│   ├── buffer.v             # single output-drain slot
│   ├── combined_buffer.v    # full addressed drain path
│   ├── single_bram.v        # single-port BRAM
│   ├── row_bram.v           # BRAM bank
│   └── multiplexer_bram.v   # 2:1 ping-pong selector
└── tb/
    ├── test_core_wrap.py    # cocotb tests + NumPy golden model
    └── Makefile             # cocotb / Icarus flow
```

---

## Status

**Done**

- Parameterized output-stationary PE and full `array_no × array_no` array
- Diagonal input-skew network
- Compute/drain control FSM
- Addressed output-drain buffer path
- BRAM banking and double-buffer selection mux
- **Functional verification: cocotb testbench vs. NumPy golden model —
  randomized K-sweep, signed extremes, multi-tile regression, 7/7 passing**

**In progress / roadmap**

- FPGA bring-up: synthesis, timing closure, and on-board validation on Zynq
  (PYNQ-Z2)
- Host interface (AXI / DMA) for streaming tiles to and from the accelerator
- Tiling controller for matrices larger than the array — the foundation for
  mapping convolutional layers onto the core

---

## Author

**Jorden Joy** — Electronics & Communication Engineering, BITS Pilani
GitHub: [@JordenJoy15](https://github.com/JordenJoy15)
