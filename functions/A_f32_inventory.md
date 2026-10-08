<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# A_f32_inventory — every f32/f64 use in the slice, with its exact replacement

Team A, steering 2 ("strip out f32 and invert it"). Analyzed source: hologram-ai (MIT OR Apache-2.0), HEAD `c9609c0`, read-only.

**Method.**
- `checks/A_f32_rg.sh` runs `rg -n '\bf32\b|\bf64\b|as f32|from_bits|to_bits|half::'` over the slice source files. The raw output is in `checks/logs/A_f32_rg-20261007T172401.txt`.
- **104 matching lines in 15 files.**
- Six listed paths have **zero** matches:
  - `crates/hologram-ai-onnx/src/dtype_map.rs`
  - `crates/hologram-ai/src/address.rs`
  - `crates/hologram-ai/src/materialize.rs`
  - `crates/hologram-ai/src/staged.rs`
  - `crates/hologram-archivum/src`
  - `crates/hologram-ai-conformance/src/witness.rs`

  The κ, store, materialize and ledger code is therefore float-free already.

Classification of the 104 lines, done by hand from the raw listing:

| kind | lines |
|---|---|
| executable code | 49 |
| doc comments / comments / string literals | 31 |
| unit-test code | 24 |

Each group below names the function, its lines, the exact replacement domain, and the `approx_` entry that holds the error relation. "Exact" means the reference spec is computed in `ℤ`, the dyadic rationals `ℤ[1/2]`, or `ℚ`. No slice function needs the Goldilocks field: nothing in the slice is modular, and every quantity is a signed magnitude or a byte count. Goldilocks would only be the right domain for a field-arithmetic witness, and the slice has none.

Float literal → exact binary value (f32 unless noted). The values were computed by IEEE-754 decomposition in a scratch session that is not part of the deliverable.

| literal (intended) | exact value of the f32 | decimal of the f32 |
|---|---|---|
| 1e-5 (rms_norm_eps, smollm2) | 2748779·2^−38 | 9.99999974737875e−6 |
| 1e-6 (rms_norm_eps, handshake/qwen; encode test slack) | 8796093·2^−43 | 9.99999997475243e−7 |
| 1e-4 (Q4_0 scenario tolerance) | 13743895·2^−37 | 9.99999974737875e−5 |
| 1e-3 (Q8_0 tolerance; rope check) | 8589935·2^−33 | 1.00000004749745e−3 |
| 1e-2 (ORT tolerance, absolute part) | 5368709·2^−29 | 9.99999977648258e−3 |
| 2e-3 (ORT tolerance, relative part) | 8589935·2^−32 | 2.00000009499490e−3 |
| 1e-12 (eps comparison) | 2305843·2^−61 | 9.99999996004197e−13 |
| 0.1 (ORT fixture input step) | 13421773·2^−27 | 0.100000001490116 |
| 0.05, 0.01 (seeded weights) | 13421773·2^−28; 5368709·2^−29 | 0.0500000007450581; 0.00999999977648258 |
| 0.13, 0.7 (encode test fixture) | 1090519·2^−23; 11744051·2^−24 | 0.129999995231628; 0.699999988079071 |
| 0.25, 0.5, −1.25, −1.5, 127, 255, 0.75 | exact: 2^−2, 2^−1, −5·2^−2, −3·2^−1, 127, 255, 3·2^−2 | exact |
| 10000, 100000, 1000000 (rope_theta) | exact: 625·2^4, 3125·2^5, 15625·2^6 | exact |
| fl32(1/127) (encode scale for amax = 1) | 2113665·2^−28 | 0.00787401571869850 |

---

## Grouped by function (executable lines only, then comment and test lines)

### quant crate — `crates/hologram-ai-quant/src` (code 11, doc 6, test 4)

| function | code lines | exact replacement | approx entry |
|---|---|---|---|
| `dequant_q4_0_block` | `q4_0.rs:20,21,26,27` | `f16val` (exact dyadic) times an integer in [−8,7], in `ℤ[1/2]` | A_quant QU-01: error **0** for finite scales |
| `dequant_q4_0` | `q4_0.rs:36` | concatenation | QU-02 |
| `dequant_q8_0_block` / `dequant_q8_0` | `q8_0.rs:20,21,24,33` | `int8 · f16val` in `ℤ[1/2]` | QU-03: error **0** for finite scales |
| `round_f32` | `encode.rs:9` | `rhaz` on `ℚ` | exact on its f32 input |
| `encode_int8_per_channel` | `encode.rs:19` | `s = amax/127 ∈ ℚ`, `Q = rhaz(127·w/amax) ∈ ℤ` | QU-05: `Q` differs by at most 1, and only near ties; round trip `≤ s·(1/2 + 3.03e−5)` |

The `half::` uses are `half::f16::from_bits(...).to_f32()`, which is exact. Replace with `f16val`, which also rejects exponent 31.

### compile-time quantization pass — `crates/hologram-ai-common/src/lower/quantize.rs` (code 2, comment 8, test 9)

| function | code lines | exact replacement | approx entry |
|---|---|---|---|
| `quantize_weights` (decode weights) | `:79,:81` (`f32::from_le_bytes`) | `f32val` as an exact dyadic, then QU-05 exact | QU-07 |

The test weights `0.1 … −0.8` (`:178`, `:286`) are f32 literals and are not exact decimals. The tests check structure only.

### IR parameter access — `crates/hologram-ai-common/src/ir/param.rs` (code 1, doc 2)

| function | code line | exact replacement | note |
|---|---|---|---|
| `AiParam::as_f32_slice` | `:88` | decode LE words to exact dyadics | `bytemuck::try_cast_slice` returns `None` when the `Vec<u8>` buffer is not 4-byte aligned. That depends on the allocator, so callers can see platform-dependent `None`. It also reinterprets in native byte order, which is LE on every target named in the repo. |

### constant dedup log — `crates/hologram-ai-common/src/opt/const_dedup.rs` (code 1)

| function | code line | exact replacement |
|---|---|---|
| `ConstantDeduplication::run` log field `saved_mb` | `:117` | `saved_bytes / 2^20` in `ℚ`. Display only, and exact for `< 2^53` bytes, since division by a power of 2 is exact. |

### ONNX import — `crates/hologram-ai-onnx/src` (code 17, comment 9)

| function | code lines | exact replacement | approx entry / break |
|---|---|---|---|
| `extract_raw_bytes` F16 typed field | `tensor_map.rs:122` | read the uint16 bits from `int32_data` (ONNX spec), with no conversion | A_onnx OX-04. `f16::from_f32` rounds to nearest even, giving a relative error of up to 2^−11, overflow to ±Inf above 65504, and NaN payloads lost. |
| `decode_tensor_proto_f32` | `lib.rs:39,44` | decode per declared dtype into exact values | OX-05: bytes are reinterpreted for non-F32 dtypes |
| `OpCtx::attr_f`, `attr_floats`, `attr_f_or` | `op_map.rs:15,31,47` | keep the attribute as exact f32 bits, i.e. a dyadic | exact, since protobuf float attributes are already f32 |
| Clip default bounds | `op_map.rs:228,229`; `graph_builder.rs:1634,1635` | `Option<ℚ>` bounds, with `None` meaning unbounded | ±Inf stands in for "no bound" |
| ConstantOfShape fill | `op_map.rs:283,292,304` | the single element of `value` in its own dtype (`ℤ` or dyadic) | OX-10: the first 4 bytes are read as f32 regardless of dtype |
| `new_f32_const!` (DQL constants 0.0, 255.0) | `graph_builder.rs:237` | 0 and 255 in `ℤ` | exact |
| `extract_f32_scalar` | `graph_builder.rs:1651,1660,1661` | the exact dyadic of the f32 or f64 | OX-11: `f64 as f32` rounds and can overflow to ±Inf |
| DynamicQuantizeLinear (built from f32 `AiOp`s, not caught by the pattern) | `graph_builder.rs:284–356` | `ℚ` with `rhte` and saturation | OX-07: zero point added unrounded at step 15; NaN when the range is 0 |
| MatMulInteger (f32 MatMul) | `graph_builder.rs:434–496` | `ℤ` sum | OX-08: exact only if `K·max|ab| ≤ 2^24` |

### parametric builder — `crates/hologram-ai-safetensors/src/parametric.rs` (code 7, comment 1, test 8)

| function | code lines | exact replacement | approx entry |
|---|---|---|---|
| `ModelConfig` fields `rms_norm_eps`, `rope_theta` | `:164,:165` | `ℚ`: the decimal written in config.json | ST-06 |
| `require_f64` + `as f32` | `:186,:205,:206` | parse the JSON number text as an exact decimal rational | ST-06: double rounding decimal→f64→f32; relative error `≤ 2^−24 + 2^−53` |
| widen-to-f32 tensor names (`{name}.f32`) | `:460,:496` | not arithmetic. They name the explicit `Cast{F32}` node, which turns F16/BF16 weights into F32 exactly: every f16 and bf16 value is an f32. | exact |

### facade — `crates/hologram-ai/src` (code 8, comment 5, test 3)

| function | code lines | exact replacement | note |
|---|---|---|---|
| `ModelCompiler.patch_budget_ratio: Option<f32>` | `compiler.rs:215` (default `Some(0.75)` at `:231`) | `ℚ ∩ (0,1]`; `0.75 = 3/4` is exact | used by `select_pipeline` |
| `select_pipeline` | `compiler.rs:1032` | same | `unwrap_or(1.0)`, exact |
| `widen_to_f32` (uncompiled file) | `quantized.rs:32,44,57` | `f32val` / `bf16val`, both exact | QU-08: error 0 |
| `format_size` | `download/mod.rs:269,271,273` | `b/2^{10k}` rendered to 1 decimal place | AQ-07: exact for `b < 2^53` |

### model registry — `crates/hologram-ai-model/src/lib.rs` (code 2)

| field | line | exact replacement |
|---|---|---|
| `UseCaseExpects.rope_theta: f64`, `rms_norm_eps: f64` | `:73,:74` | `ℚ`. The TOML decimal text is exact: 1e-5 = 1/100000, 1e-6 = 1/1000000, rope 10000 / 100000 / 1000000. The f64 parse rounds 1e-5 and 1e-6. The steps then compare `e.rms_norm_eps as f32` with the graph value, both rounded from the same f64. |

---

## f32 uses in the slice's step code (outside the rg file list, `crates/hologram-ai-conformance/tests/`)

| site | line | exact replacement | break |
|---|---|---|---|
| `seeded_weights` | `bdd.rs:513–534` | `unit = ⌊x/2^11⌋/2^53 ∈ ℚ` | `unit_f32 = 1.0` reachable (A_compilation CP-09) |
| eps comparison `< 1e-12` | `bdd.rs:1339` | equality of exact rationals | both sides are the same rounding, so this is equality in practice |
| rope comparison `< 1e-3` | `bdd.rs:1373` | equality in `ℚ` | the tolerance hides nothing for exact thetas |
| quant tolerance | `bdd.rs:1719` | exact equality (QU-01/03 show error 0) | the tolerance is unnecessary |
| ORT parity tolerance `1e-2 + 2e-3·|r|` | `bdd.rs:1928` | **no exact replacement**: the authority (ORT) is itself f32 | f32 sums are non-associative, so the two engines can differ by reduction order |
| ORT fixture input `((7i mod 13) − 6)·0.1` | `bdd.rs:4812–4814` | `(…)·(1/10)` in `ℚ` | the f32 step is `13421773·2^−27`, not 1/10 |

## Assertions whose truth depends on exactness

These are the Alloy models (integer-only) whose UNSAT results would not carry over to the f32 code without the error relations above:
- `A_quant.als` `encodeWithinRange` and `encodeHalfStepBound` are stated over integers and rationals scaled to integers. In f32, `Q` can move by 1 near ties (QU-05 (c)).
- `A_onnx.als` `matmulIntegerExactUnderBound` is the integer statement of the 2^24 condition. It is about exactness itself.
- `A_quant.als` `q4LayoutsDifferUnlessSymmetric` is a pure index permutation and is independent of exactness.
- All κ-based checks depend on the injectivity assumption (`fact kappaInjective`), not on floats.
