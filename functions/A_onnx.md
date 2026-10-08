<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# A_onnx — ONNX import: dtypes, tensor bytes, quantization decompositions

Team A catalog. Analyzed source: hologram-ai (MIT OR Apache-2.0), HEAD `c9609c0`, read-only. Verdicts as in `A_addressing.md`. The external authority for every claim here is the ONNX operator and protobuf specification (oracle ids `onnx-node-corpus` v1.17.0 and `onnx-runtime` v1.18.1 in `model/oracles.toml`).

Exact domains used:
- dtype and byte functions: integers and bytes
- DynamicQuantizeLinear: `ℚ`, with saturation to `ℤ ∩ [0,255]`
- MatMulInteger: `ℤ`, because the spec output is int32 and the exact accumulation lives in `ℤ`

No Goldilocks arithmetic is needed. int32 overflow semantics are noted where relevant.

---

### OX-01 `onnx_dtype`
- Source: `crates/hologram-ai-onnx/src/dtype_map.rs:15`
- Signature: `onnx_dtype : i32 → Option<DType>` (a finite table).
- Definition, taken from the code:

  | ONNX code | DType |
  |---|---|
  | 1 | F32 |
  | 2 | U8 |
  | 3 | INT8 |
  | 4 (UINT16) | INT32 |
  | 5 | INT16 |
  | 6 | INT32 |
  | 7 | INT64 |
  | 9 | BOOL |
  | 10 | F16 |
  | 11 | F64 |
  | 12 (UINT32) | INT64 |
  | 13 (UINT64) | INT64 |
  | 16 | BF16 |
  | 21 (UINT4), 22 (INT4) | INT4 |
  | anything else | None |
- P1 "Widening casts for types without native representation" — **Absent**. No code widens the bytes. `is_widened_dtype` (`:39`) is `#[allow(dead_code)]` and has no callers. `raw_data` for UINT16 has 2 bytes per element, but the declared INT32 implies 4, so `|bytes| ≠ elems · size(dtype)`. UINT64 values ≥ 2^63 become negative INT64. UINT4 nibbles 8..15 are reinterpreted as INT4 −8..−1.

### OX-02 `tensor_to_param`
- Source: `crates/hologram-ai-onnx/src/tensor_map.rs:15`
- Definition:
  - `dtype = onnx_dtype(t.data_type)`, or `Err("unsupported ONNX data_type …")`.
  - `shape = [d as u64 | d ∈ t.dims]`. A negative `d` becomes `2^64 + d`, with no error.
  - The data location chooses between OX-03 (external buffer), mmap (`:153`), and OX-04 (inline).
- P1 shape is faithful to the spec — **Implemented** for valid dims (`dims ≥ 0`). A negative dim is accepted silently.

### OX-03 `extract_raw_bytes_external`
- Source: `tensor_map.rs:56`
- Definition:
  - `offset` and `length` are parsed from the `external_data` key/value entries, with defaults `offset = 0` and `length = |buf| − offset` (saturating).
  - If `offset + len > |buf|`, it returns `Err`; otherwise it returns `buf[offset .. offset+len)`.
- Edge: `offset + len` is an unchecked `u64` add. With a crafted `length` near 2^64 the sum wraps in release builds and passes the check. The following `start + len as usize` then overflows or panics at the slice. The result is a panic rather than an `Err`. Found by reading.
- P1 bounds-checked — **Implemented** except for the wrap edge.

### OX-04 `extract_raw_bytes` (typed fields)
- Source: `tensor_map.rs:98`
- Definition: if `raw_data ≠ ε`, return it unchanged, with no length check against `dims × size(dtype)`. Otherwise, per dtype:

  | dtype | source field | conversion |
  |---|---|---|
  | F32 | `float_data` | LE |
  | F16 | `float_data` | `f16::from_f32` (`:122`), then LE |
  | INT8 | `int32_data` | `i as i8` |
  | U8 / BOOL | `int32_data` | `i as u8` |
  | INT32 | `int32_data` | LE |
  | INT64 | `int64_data` | LE |
  | anything else (BF16, F64, INT16, INT4) | — | `Err` |
- P1 matches the ONNX protobuf field semantics — **Absent** for F16. The ONNX spec stores float16 typed values as their uint16 bit patterns in `int32_data`, not in `float_data`. A spec-conformant F16 tensor in typed form therefore yields 0 bytes. A non-conformant producer that puts full floats in `float_data` gets a lossy `from_f32` rounding (`approx`, see `A_f32_inventory.md`). For UINT32 and UINT64 (mapped to INT64) the spec field is `uint64_data`, which is never read, so the result is 0 bytes.

### OX-05 `decode_tensor_proto_bytes` / `decode_tensor_proto_f32`
- Source: `crates/hologram-ai-onnx/src/lib.rs:27`, `:39`
- `decode_tensor_proto_bytes(b) = (raw_data, dims, data_type)` after a protobuf decode, or `Err`.
- `_f32` returns `float_data` if it is non-empty. Otherwise it reinterprets `raw_data` as f32 LE (4-byte chunks, extra bytes dropped), whatever the dtype.
- P1 dtype-correct — **Absent** for non-F32 tensors: the bytes are reinterpreted, not converted.

### OX-06 `import_onnx_inner` opset gate
- Source: `lib.rs:94`
- Definition:
  - `opset = version of the opset_import with empty domain`, else 0.
  - If `max_opset > 0 ∧ opset > max_opset`, it returns `Err`.
  - A model with no default-domain opset gets `opset = 0` and passes any gate.
- P1 opset enforcement — **Implemented** as stated, including the 0 edge.

### OX-07 DynamicQuantizeLinear decomposition
- Source: `crates/hologram-ai-onnx/src/graph_builder.rs:181` (match), steps at `:284–356`. The comment block at `:160–180` cites https://onnx.ai/onnx/operators/onnx__DynamicQuantizeLinear.html.
- Exact spec (ONNX), for `x ∈ ℚ^N`:
  - `M = max(0, max x)` and `m = min(0, min x)`
  - `s = (M − m)/255`
  - `zp = sat₀²⁵⁵(rhte(−m/s))`
  - `y_i = sat₀²⁵⁵(rhte(x_i/s) + zp)`
  - `rhte` is round-half-to-even, as ONNX specifies for this op, and `sat₀²⁵⁵` clamps to `[0,255]`.
  - The spec leaves `M = m = 0` (all-zero input) without a finite scale.
- Code (as built), in f32:
  - `s = fl((M − m)/255)`
  - `zp_f32 = fl(−m/s)`
  - `zp = Cast_U8(clip(Round(zp_f32)))`, which is correct in form
  - **but** `y_i = Cast_U8(clip(Round(fl(x_i/s)) + zp_f32))` (step 15, `:344–346`) adds the **unrounded** `zp_f32`
- Deviation: the spec adds the integer `zp`, but the code adds `zp_f32`, which differs from `zp` by a fraction in `(−1/2, 1/2]`. The final `y` then depends on how `Cast{U8}` maps a non-integer. That lowering is team B's (HANDOFF). Worked case in exact arithmetic:
  - Input `x = [−1, 3]`, so `s = 4/255` and `−m/s = 255/4 = 63.75`.
  - That gives `zp = 64` and `zp_f32 = 63.75`.
  - For `x = 3`: `x/s = 191.25`, which rounds to 191.
  - The spec gives `y = 191 + 64 = 255`. The code gives `191 + 63.75 = 254.75` before the Cast, i.e. 254 under truncation or 255 under rounding.
  - The two formulas differ whenever `zp_f32 ∉ ℤ`.
- `approx_dynamic_quantize_linear`:
  - (a) `graph_builder.rs:284–356`
  - (b) rounding steps: 4 f32 divisions/subtractions plus `Round` and `Cast`
  - (c) error relative to the spec: up to 1 unit in `y` from step 15 alone, plus near-tie flips from `fl(x/s)`. Bound: `|y_code − y_spec| ≤ 1` cannot be shown without the B-side Cast semantics, so it is "not derived".
  - (d) breaks: when `M = m = 0`, `s = 0` and `0/0 = NaN` propagates to `zp` and `y`. The Cast of NaN is B-side.
- P1 implements the ONNX operator — **Absent**: the formula differs at step 15.
- P2 tested against the spec — **Absent**. No ONNX node-corpus case for DQL is wired. Only `crates/hologram-ai/tests/diag_qwen25_int8.rs`, a diagnostic, exercises it.

### OX-08 MatMulInteger decomposition
- Source: `graph_builder.rs:381` (match), with the comment at `:362–380`.
- Exact spec: `Y[i,j] = Σ_{t<K} (A[i,t] − a_zp)·(B[t,j] − b_zp)`, computed in ℤ and returned as int32. (ONNX accumulates in int32; for u8/i8 the sum fits when `K·65025 < 2^31`, i.e. `K ≤ 33025`.)
- Code: cast to INT32, subtract the zero points, cast to F32, do an f32 `MatMul`, cast back to INT32.
- `approx_matmul_integer`:
  - (a) `graph_builder.rs:434–496` (cast/sub/MatMul/cast chain; f32 `MatMul` at `:491`)
  - (b) rounding steps: every product `|a·b| ≤ 65025` is exact in f32. Each partial sum is rounded to 24 significant bits.
  - (c) error: exact if every partial sum stays within `[−2^24, 2^24]`. A sufficient condition is `K·max|a·b| ≤ 2^24`:
    - u8 with zero points: `max|a·b| = 255² = 65025`, so `K ≤ 258` (`258·65025 = 16776450 ≤ 16777216`)
    - i8 without zero points: `128² = 16384`, so `K ≤ 1024`
    - Above that, worst case: `|Y_code − Y| ≤ Σ_t ulp(partial_t)/2`, a value that depends on the summation order and was not derived further.
  - (d) breaks: f32 summation is non-associative, so the result depends on the backend's reduction order (B-side). The final Cast of a value > 2^31 is B-side.
- P1 the comment "for K ≤ ~2^24 with u8/i8 inputs the int32 accumulator value is exact (Qwen2.5-0.5B hidden_size=896, well under 2^24)" — **Absent** (the claim is false). The worst-case-exact bound is K ≤ 258 (u8 with zero point) or 1024 (i8). Qwen's 896 exceeds the u8 bound. Exactness depends on exact integer arithmetic; `A_onnx.als` encodes the sufficient condition over small integers.

### OX-09 QuantizeLinear / DequantizeLinear mapping
- Source: `crates/hologram-ai-onnx/src/op_map.rs:436`, `:439`
- QuantizeLinear maps to `AiOp::Quantize{scheme: Q8_0}`. The ONNX op is affine per-tensor/per-axis u8/i8 with a zero point, which is not a GGML Q8_0 32-element block scheme.
- DequantizeLinear maps to `Dequantize{axis: attr or 1}`. ONNX's default axis is also 1.
- P1 QuantizeLinear semantics preserved — **Absent** at the mapping level: the scale/zero-point operands are kept as node inputs, but the op is labeled Q8_0. Lowering is B-side.

### OX-10 ConstantOfShape fill value
- Source: `op_map.rs:282–305`
- Exact spec: the fill is the single element of the `value` tensor, in that tensor's dtype. The default is float32 0.
- Code: `float_data[0]` if present; else the first 4 bytes of `raw_data` as f32 LE; else `0.0`. The result is stored as `f32::to_bits`.
- Edges:
  - For an INT64 `value = 1` in `raw_data`, the bits are `0x00000001`. As an f32 that is `2^−149`; as an integer it is 1. Which one is used depends on B-side lowering.
  - An INT64 value in `int64_data` is ignored, giving 0.
- P1 dtype-correct — **Absent** in the import; it is correct only by accident of bit reinterpretation, if at all.

### OX-11 `extract_f32_scalar`
- Source: `graph_builder.rs:1647`
- Definition: F32 scalars use the 4 LE bytes. F64 scalars are converted with `f64 as f32`, which rounds to nearest even and can overflow to ±Inf. Anything else gives None.
- Exact replacement: return the scalar as an exact dyadic rational, without narrowing.
