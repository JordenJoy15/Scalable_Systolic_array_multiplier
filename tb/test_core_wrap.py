"""
cocotb testbench + NumPy golden model for core_wrap (8x8 output-stationary
systolic matrix-multiply core, int8 operands / int32 accumulators).

Golden model:  C_ref = A @ B   (A: 8xK int8, B: Kx8 int8, C: 8x8 int32)

Driving protocol (derived from the RTL):
  * beat k (k = 0..K-1):  feed_act lane i = A[i][k]   (activation row i)
                          feed_wt  lane j = B[k][j]   (weight column j)
  * then ARRAY_N-1 zero-pad beats so the deepest skew-FIFO lane flushes
  * feed_last is asserted on the FINAL pad beat -> triggers sr_pulse,
    which launches the diagonal accumulator-reset wavefront and the
    8-lane drain sweep.

Drain collection:
  * drn_valid[i] is high for exactly 8 cycles, lane i lagging lane 0 by i
  * while drn_valid[i] is high, drn_data lane i emits C[i][0..7] in order
"""

import random
import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, Timer

WIDTH = 8
ARRAY_N = 8
ACC_W = 4 * WIDTH          # 32-bit accumulators
LANE_MASK = (1 << WIDTH) - 1
ACC_MASK = (1 << ACC_W) - 1


# ----------------------------------------------------------------- helpers --
def to_u8(x: int) -> int:
    """int8 -> two's-complement byte."""
    return x & LANE_MASK


def to_s32(x: int) -> int:
    """32-bit two's-complement -> signed int."""
    return x - (1 << ACC_W) if x & (1 << (ACC_W - 1)) else x


def pack_lanes(vals) -> int:
    """Pack 8 signed bytes into one 64-bit bus value (lane i at bits [8i+7:8i])."""
    word = 0
    for i, v in enumerate(vals):
        word |= to_u8(int(v)) << (WIDTH * i)
    return word


def golden(A: np.ndarray, B: np.ndarray) -> np.ndarray:
    return A.astype(np.int64) @ B.astype(np.int64)


# ------------------------------------------------------------------ driver --
async def reset_dut(dut):
    dut.rst.value = 1
    dut.feed_act.value = 0
    dut.feed_wt.value = 0
    dut.feed_en.value = 0
    dut.feed_last.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def drive_tile(dut, A: np.ndarray, B: np.ndarray):
    """Stream one full tile:
         1 leading zero beat  -- feed_en must precede data by one cycle,
                                 because core_wrap registers the enable
                                 (ena_reg) while skew lane 0 is a
                                 combinational passthrough; without this
                                 pad, beat 0 is dropped by every PE
       + K real beats
       + (ARRAY_N-1) trailing zero pads so the deepest skew lane flushes,
         feed_last on the final pad beat."""
    K = A.shape[1]
    total = 1 + K + (ARRAY_N - 1)
    for beat in range(total):
        if 1 <= beat <= K:
            dut.feed_act.value = pack_lanes(A[:, beat - 1])
            dut.feed_wt.value = pack_lanes(B[beat - 1, :])
        else:
            dut.feed_act.value = 0
            dut.feed_wt.value = 0
        dut.feed_en.value = 1
        dut.feed_last.value = 1 if beat == total - 1 else 0
        await RisingEdge(dut.clk)
    dut.feed_en.value = 0
    dut.feed_last.value = 0
    dut.feed_act.value = 0
    dut.feed_wt.value = 0


# --------------------------------------------------------------- collector --
async def collect_tile(dut, timeout_cycles=200) -> np.ndarray:
    """Watch drn_valid; while lane i is valid, capture 8 beats of drn_data
    lane i as C[i][0..7]. Returns the reassembled 8x8 int32 matrix."""
    rows = [[] for _ in range(ARRAY_N)]
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        await ReadOnly()
        try:
            valid = int(dut.drn_valid.value)
            data = int(dut.drn_data.value)
        except ValueError:      # X/Z before first drain
            continue
        for i in range(ARRAY_N):
            if (valid >> i) & 1 and len(rows[i]) < ARRAY_N:
                lane = (data >> (ACC_W * i)) & ACC_MASK
                rows[i].append(to_s32(lane))
        if all(len(r) == ARRAY_N for r in rows):
            return np.array(rows, dtype=np.int64)
    raise cocotb.result.SimTimeoutError(
        f"drain incomplete: lane fill = {[len(r) for r in rows]}")


async def run_and_check(dut, A, B, tag=""):
    collector = cocotb.start_soon(collect_tile(dut))
    await drive_tile(dut, A, B)
    C_dut = await collector
    C_ref = golden(A, B)
    if not np.array_equal(C_dut, C_ref):
        bad = np.argwhere(C_dut != C_ref)
        msg = [f"{tag}: MISMATCH at {len(bad)} element(s)"]
        for (r, c) in bad[:8]:
            msg.append(f"  C[{r}][{c}]  dut={C_dut[r][c]}  ref={C_ref[r][c]}")
        raise AssertionError("\n".join(msg))
    dut._log.info(f"{tag}: PASS  (K={A.shape[1]}, all 64 outputs match)")


def rand_mat(rows, cols, rng):
    return rng.integers(-128, 128, size=(rows, cols), dtype=np.int64)


# ------------------------------------------------------------------- tests --
async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)


@cocotb.test()
async def test_k8_random(dut):
    """Square case: K = 8, random int8."""
    await setup(dut)
    rng = np.random.default_rng(1)
    await run_and_check(dut, rand_mat(8, 8, rng), rand_mat(8, 8, rng), "K8-random")


@cocotb.test()
async def test_k1_minimum(dut):
    """Degenerate depth: K = 1 (single MAC per PE)."""
    await setup(dut)
    rng = np.random.default_rng(2)
    await run_and_check(dut, rand_mat(8, 1, rng), rand_mat(1, 8, rng), "K1-min")


@cocotb.test()
async def test_k64_deep(dut):
    """Deep accumulation: K = 64 in a single streamed pass."""
    await setup(dut)
    rng = np.random.default_rng(3)
    await run_and_check(dut, rand_mat(8, 64, rng), rand_mat(64, 8, rng), "K64-deep")


@cocotb.test()
async def test_identity(dut):
    """A = I  ->  C must equal B exactly (checks lane ordering / transpose bugs)."""
    await setup(dut)
    rng = np.random.default_rng(4)
    A = np.eye(8, dtype=np.int64)
    B = rand_mat(8, 8, rng)
    await run_and_check(dut, A, B, "identity")


@cocotb.test()
async def test_signed_extremes(dut):
    """All-(-128) x all-(+127) at K = 32: stresses sign extension and
    accumulator growth (each element = -128*127*32 = -520,192)."""
    await setup(dut)
    A = np.full((8, 32), -128, dtype=np.int64)
    B = np.full((32, 8), 127, dtype=np.int64)
    await run_and_check(dut, A, B, "signed-extremes")


@cocotb.test()
async def test_sequential_tiles(dut):
    """Three tiles back-to-back with a short idle gap between them:
    checks that the skew-reset wavefront fully cleans the array state."""
    await setup(dut)
    rng = np.random.default_rng(5)
    for t in range(3):
        K = int(rng.integers(4, 33))
        await run_and_check(dut, rand_mat(8, K, rng), rand_mat(K, 8, rng),
                            f"seq-tile{t}(K={K})")
        for _ in range(12):
            await RisingEdge(dut.clk)


@cocotb.test()
async def test_random_soak(dut):
    """Randomized regression: 10 tiles, K drawn from 1..64, full int8 range."""
    await setup(dut)
    rng = np.random.default_rng(6)
    for t in range(10):
        K = int(rng.integers(1, 65))
        await run_and_check(dut, rand_mat(8, K, rng), rand_mat(K, 8, rng),
                            f"soak{t}(K={K})")
        for _ in range(12):
            await RisingEdge(dut.clk)
