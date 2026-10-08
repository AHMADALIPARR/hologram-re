<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# A_quant — block dequantization, int8 encoding, compile-time quantization

Team A catalog. Analyzed source: hologram-ai (MIT OR Apache-2.0), HEAD `c9609c0`, read-only. Verdict vocabulary as in `A_addressing.md`.

Reference arithmetic (steering 2, "strip out f32 and invert it"): each function is first defined exactly, then each f32 code path is listed as `approx_<name>`.
- Dequant functions: exact domain is the dyadic rationals `ℤ[1/2]`.
- Encoding: exact domain is `ℚ`, because of the division by 127.
- No function in this file needs the Goldilocks field. All values are signed magnitudes, and none of the arithmetic is modular.

Exact helpers:
- `f16val : u16 → ℤ[1/2] ∪ {⊥}`. Let `s = bit15`, `e = bits14..10`, `m = bits9..0`.
  - `e = 0` → `(−1)^s · m · 2^−24`.
  - `1 ≤ e ≤ 30` → `(−1)^s · (1024 + m) · 2^(e−25)`.
  - `e = 31` (Inf/NaN) → `⊥`, meaning the exact spec is undefined and must reject.
- `bf16val : u16 → ℤ[1/2] ∪ {⊥}` uses the same scheme with 8 exponent bits and 7 mantissa bits. It equals `f32val(bits << 16)`.
- `rhaz : ℚ → ℤ`, round half away from zero: `rhaz(x) = sign(x) · ⌊|x| + 1/2⌋`.

Worked constants, decoded from the repo goldens by `checks/A_quant_layout.sh`:
- scale bits 15360 = 1
- 14336 = 1/2
- 46080 = −1/4
- 31743 = 65504
- 16384 = 2
- 0 = 0

---

### QU-01 `dequant_q4_0_block`
- Source: `crates/hologram-ai-quant/src/q4_0.rs:20`. Block layout: `#[repr(C, packed)]`, `{scale: u16 (f16 bits, LE), qs: [u8; 16]}`, `Q4_0_BLOCK_SIZE = 18` (`q4_0.rs:15`).
- Exact signature: `dq4 : B^18 → (ℤ[1/2])^32 ∪ {⊥}`.
- Exact definition, as implemented (interleaved):
  - `d = f16val(b0 + 256·b1)`. If `d = ⊥`, the result is `⊥`.
  - For `i ∈ 0..15`: `lo_i = (qs_i mod 16) − 8` and `hi_i = ⌊qs_i / 16⌋ − 8`.
  - Then `out[2i] = lo_i · d` and `out[2i+1] = hi_i · d`.
- GGML reference definition (`ggml-quants.c:459`, fetched 2026-10-07): `y[i] = lo_i·d` and `y[i+16] = hi_i·d`, i.e. split halves.
- Relation: `out = y ∘ π`, where `π(2i) = i` and `π(2i+1) = i+16`. `π` is a non-identity permutation of 0..31, so the two agree only when the block's values are invariant under it. For example, they agree when all nibbles are equal or `d = 0`.
- `approx_dequant_q4_0_block`:
  - (a) Source: `q4_0.rs:20–31`.
  - (b) Rounding steps: `half::f16::to_f32` is exact, since every f16 is representable in f32. Then one f32 multiply `lo as f32 * scale`.
  - (c) Error: `|approx − exact| = 0` for every finite scale. Reason: `|lo| ≤ 8` (4 bits) times an 11-bit significand needs ≤ 15 significant bits, which is below 24. The magnitude range is `[2^−24, 65504·8]`, inside f32's normal range. Derivation: this file; checked on the 5 goldens by `A_quant_layout.sh` (exact jq products equal the repo's expected values).
  - (d) Breaks:
    - `e = 31` scale bits give ±Inf/NaN outputs, and `0·Inf = NaN`, where the exact spec gives `⊥`.
    - `lo = 0` with a negative scale gives `−0.0`, which is rational 0 but a different bit pattern. That matters only if f32 bytes are later hashed or κ-addressed.
- Properties:
  - P1 "GGML-conformant" (`docs/architecture/ARCHITECTURE.md:78`) — **Absent**. The code uses the interleaved layout. Against GGML's split layout the repo goldens mismatch 27, 16, 28, 4 and 0 of 32 elements (`checks/logs/A_quant_layout-*.txt`).
  - P2 bit-exact against the repo goldens ("bit-exactly", dictionary row `quant-dequant`) — **Implemented** for the 5 goldens (0 mismatches). The scenario itself uses tolerance `0.0001` / `0.001`, not bit equality.
  - P3 the goldens come from GGML (`model/oracles.toml` quant-goldens, `source = "ggml"`) — **Marketing**:
    - `pin = ""`
    - there is no generator in the repo
    - the goldens encode the non-GGML layout
  - P4 "dequant used by the pipeline" (implicit in ADR-0004) — **Absent**. `dequant_q4_0` and `dequant_q8_0` are called only from `crates/hologram-ai-conformance/tests/bdd.rs:1708–1709`.

### QU-02 `dequant_q4_0`
- Source: `q4_0.rs:36`.
- Signature: `B* → (ℤ[1/2])*`. The exact version is partial: `⊥` unless `|data| ≡ 0 (mod 18)`.
- Definition: concatenate QU-01 over the `|data|/18` blocks.
- Error: `assert_eq!` panics (process abort in a test) when `|data| mod 18 ≠ 0`. It does not return an error value.
- `approx_dequant_q4_0`: the per-block result as in QU-01. No cross-element arithmetic, so it is deterministic and exact.
- P1 rejects misaligned input — **Implemented** as a panic (test `q4_0.rs:110`).

### QU-03 `dequant_q8_0_block` / QU-04 `dequant_q8_0`
- Source: `q8_0.rs:20`, `q8_0.rs:33`. `Q8_0_BLOCK_SIZE = 34` (`q8_0.rs:15`), laid out as `{scale u16, qs [i8;32]}`.
- Exact definition: `out[i] = int8(qs_i) · f16val(scale)`, where `int8(x) = x if x < 128 else x − 256`.
- Same layout as GGML `dequantize_row_q8_0` (`ggml-quants.c:553`).
- `approx_dequant_q8_0_block`:
  - (a) Source: `q8_0.rs:20–28`.
  - (b) Rounding steps: exact f16→f32, then one multiply.
  - (c) `|approx − exact| = 0` for finite scales: `|q| ≤ 128` (8 bits) plus an 11-bit significand is 19 bits, at most 24. Max magnitude `65504·128 = 8384512`.
  - (d) Breaks: Inf/NaN scale; `−0.0` for `q = 0` with a negative scale.
- P1 matches GGML Q8_0 — **Implemented** (4 goldens, 0 mismatches against the GGML formula). The authority, GGML, is still named rather than consulted by any repo code; team A consulted it.
- P2 misaligned input — panics (`q8_0.rs:96`). **Implemented** as a panic.

### QU-05 `encode_int8_per_channel`
- Source: `crates/hologram-ai-quant/src/encode.rs:19`, using `round_f32 = libm::roundf` (`encode.rs:9`).
- Exact signature: `enc : (W ∈ ℚ^{k×n}) → (Q ∈ [−127,127]^{k×n} ⊂ ℤ, s ∈ ℚ_{>0}^n)`. The input `W` is the exact values of finite f32s, row-major.
- Exact definition:
  - `amax_j = max_i |W_ij|`.
  - `s_j = amax_j / 127` if `amax_j > 0`, else `1`.
  - `Q_ij = rhaz(W_ij / s_j) = rhaz(127·W_ij / amax_j)`.
  - The code's clamp to ±127 is never active in exact arithmetic, since `|W_ij| ≤ amax_j`.
- Pre: `|w| = k·n`. The code checks this with `assert_eq!` and panics otherwise; `k·n` is an unchecked `usize` product.
- Exact post: `|Q_ij·s_j − W_ij| ≤ s_j/2`. If `amax_j = 0`, the column is all zeros with `s_j = 1`. If `W_ij = amax_j`, then `Q_ij = 127`.
- `approx_encode_int8_per_channel`:
  - (a) Source: `encode.rs:19–44`.
  - (b) Rounding steps:
    - `amax` by `>` comparison, which is exact
    - `fl(amax / 127.0)`, one rounding
    - `fl(w / scale)`, one rounding
    - `roundf`, exact on its f32 input
    - `clamp(−127, 127)`
    - `as i8`, a saturating cast in which NaN becomes 0
  - (c) Error relation. Let `u = 2^−24` and `t = 127·W/amax`, and assume `fl(amax/127)` is a normal f32 (`amax ≥ 127·2^−126`).
    - Then `|fl(w/fl(s)) − t| ≤ 127·2u/(1−u) ≈ 1.514e−5`.
    - So `Q_approx − Q_exact ∈ {−1, 0, 1}`, and it is nonzero only when `t` lies within `1.514e−5` of a half-integer.
    - Round trip in f32: `|fl(Q·fl(s)) − W| ≤ s·(1/2 + 1.514e−5 + 127·(2u+u²)) ≈ s·(1/2 + 3.03e−5)`.
    - Below the normal range, the relative error of `fl(amax/127)` is unbounded.
    - If `fl(amax/127) = 0` (`amax ≤ 127·2^−150`), then `w/0 = ±Inf` and the clamp gives `Q = ±127`, while `0/0 = NaN` gives 0. The stored scale is 0, so the dequantized column is all 0.
  - (d) Breaks:
    - NaN inputs are skipped by `amax`, since `NaN > x` is false, and become `Q = 0`.
    - Any ±Inf in column `j` makes `scale_j = +Inf`; every element in that column becomes `Q = 0` (finite/Inf = 0, Inf/Inf = NaN → 0), and dequant gives `0·Inf = NaN`.
    - `−0.0` input gives `Q = 0`.
    - There are no sums, so the result is deterministic under IEEE round-to-nearest.
- Properties:
  - P1 `|deq − w| ≤ scale/2 + 1e−6` (test `encode.rs:50`; `1e-6` is an f32 literal with exact value `8796093·2^−43`; fixture `w_i = fl(fl(i·0.13) − 0.7)`, `i ∈ 0..14`, with `0.13 = 1090519·2^−23` and `0.7 = 11744051·2^−24` in f32) — **Asserted-only** as a general property. The derived f32 bound is `s·(1/2 + 3.03e−5)`. That is inside `s/2 + 1e−6` only when `3.03e−5·s ≤ 1e−6`, i.e. `s ≤ 0.033`. The fixture has `s ≈ 1.12/127 ≈ 0.0088`, so it passes for a derivable reason. Larger scales are not covered. In exact arithmetic the bound `s/2` is **Implemented** by construction.
  - P2 zero column gives scale 1 and exact zeros — **Implemented** (`encode.rs:69`).
  - P3 the max-magnitude element maps to ±127 — **Implemented** (`encode.rs:81`).

### QU-06 `QuantDescriptor::{none,q4_0,q8_0,q6_k}` and `QuantScheme`
- Source: `crates/hologram-ai-quant/src/scheme.rs:32,41,50,59`.
- Definition (constant table, integers):
  - none = (block 1, scale F32)
  - Q4_0 = (32, F16)
  - Q8_0 = (32, F16)
  - Q6K = (256, F16)
- `QuantScheme` has 9 variants: None, Q4_0, Q4_1, Q5_0, Q8_0, Q2K, Q4K, Q6K, IQ4Xs.
- P1 "QuantDescriptor carries scale, zero-point, block size, scheme" (ADR-0004 Decision) — **Absent**. The struct has `scheme`, `block_size` and `scale_dtype` only.
- P2 "dequant implemented for every scheme" (ADR-0004 Consequences) — **Absent**. 2 of 8 non-None schemes (Q4_0 and Q8_0) have dequant functions.

### QU-07 `quantize_weights`
- Source: `crates/hologram-ai-common/src/lower/quantize.rs:31`, helper `concrete_2d` at `:13`.
- Signature: `(AiGraph, QuantStrategy) → Result<AiGraph>`. `QuantStrategy` has 7 variants (`lower/builder.rs:46`): None, Auto, Q4_0, Q8_0, Q2_0, Int8, Int4.
- Definition:
  - `Int4` returns `Err("int4 quantization is not yet implemented")`.
  - Every strategy other than `Int8` returns `Ok` with the graph unchanged.
  - `Int8`: for each `MatMul` node whose input 1 is `AiParam::Inline` with logical dtype F32, a concrete rank-2 shape `[k,n]`, and `|data| = 4kn`:
    - `(Q,s) = encode_int8_per_channel`
    - add an INT8 constant `[k,n]`, an F32 constant `[n]`, and `Dequantize{axis:1}`
    - rewire the MatMul to read the dequantized tensor
    - delete the original param
  - If no MatMul matched, it emits a `tracing::warn!` and still returns `Ok`.
- Edges:
  - The original f32 param is removed even if another, non-MatMul node reads it, which leaves a dangling input (from reading).
  - A param shared by two MatMuls is encoded twice.
- P1 "When set to `Q4_0`, f32 MatMul weights are quantized at compile time to 4-bit centroid indices, enabling the LUT-GEMM execution path" (`crates/hologram-ai/src/compiler.rs:195–197`) — **Absent**. Q4_0 is a silent no-op without even the Int8 warning.
- P2 Int8 rewrite preserves the matmul up to the QU-05 error — **Implemented** (test `quantize.rs:216`, structural).

### QU-08 `widen_to_f32` (source present, not compiled)
- Source: `crates/hologram-ai/src/quantized.rs:32`.
- Exact definition, for an input of `elems` values:
  - F32 requires `|b| = 4·elems`, giving `f32val` of each LE word.
  - BF16 requires `|b| = 2·elems`, giving `bf16val`.
  - Any other dtype → `Err`.
- `approx`: BF16 → f32 is `(bits as u32) << 16`, which is exact, with error 0.
- Compiled? **No.** `crates/hologram-ai/src/lib.rs:9–20` declares no `mod quantized`, and `quantized.rs:29` re-exports `hologram_ai_common::lower::QuantMap`, which does not exist anywhere in the tree (`rg QuantMap`). The file is dead source.

### QU-09 `derive_quantized_artifact` (not compiled)
- Source: `quantized.rs:68`.
- Exact definition, for a wide weight `[out, in]`:
  - transpose it to `[in, out]`
  - compute `(Q, s) = enc(Wᵀ)` with `k = in`, `n = out`, i.e. one scale per output feature
  - artifact = `Q` as i8 bytes, row-major `[in,out]`, followed by `s_j` as f32 LE
  - length `= in·out + 4·out`
- The exact spec keeps `s ∈ ℚ^out`. The approx stores `fl32(s_j)` (`A_f32_inventory.md`).
- P1 deterministic — **Implemented** in source (test `quantized.rs:117`), but the code is not compiled, so the overall verdict is **Absent**.

### QU-10 `crystallize_quantized` (not compiled)
- Source: `quantized.rs:97`.
- Definition: `wide = store.resolve(k)`, with **no** κ re-check (AD-05); derive QU-09; insert into the store; return the new κ.
- P1 "fail-closed at every step" (doc comment) — **Absent**. A corrupt wide entry would yield a well-addressed wrong artifact. It is also not compiled.
- P2 "the quantized tier" (dictionary row `quantized-rest`, `features/s1_acquisition/quantized_rest.feature`) — **Absent** in the product:
  - no caller in Rust, TS or wasm (`rg crystallize_quantized|derive_quantized_artifact`)
  - three of its Gherkin steps have no binding in `apps/web/bdd/steps.mjs` (see `A_gherkin.md`)
