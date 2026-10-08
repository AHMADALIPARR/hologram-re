<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# A_safetensors — header parsing, family registry, config, parametric graph

Team A catalog. Analyzed source: hologram-ai (MIT OR Apache-2.0), HEAD `c9609c0`, read-only. Verdicts follow `A_addressing.md`.

Exact domains used here:
- Header and config functions use bytes, ℕ, and JSON values.
- Config float keys use `ℚ`, specifically the decimal rational written in `config.json`.
- Graph structure uses ℕ.

The external authority is `safetensors-ref` 0.4, the reference `safetensors` crate (`model/oracles.toml`).

---

### ST-01 `split_safetensors`
- Source: `crates/hologram-ai-conformance/src/witness.rs:90` (conformance crate; used by tests and `fetch_helper`, not by the product).
- Signature: `split : B* → Result<(B*, B*)>`.
- Definition:
  - `n = le_u64(b[0..8])`. If `|b| < 8`, return `Err`.
  - `header = b[8 .. 8+n]`. If `8 + n > |b|`, return `Err`.
  - `data = b[8+n ..]`.
- Edges:
  - `n as usize` truncates on 32-bit targets.
  - `8 + n` can overflow `usize` before `get` is called. The result is a panic in debug builds and wrap in release builds; then `get` fails, so the release behavior is still an `Err`.
- P1 matches the safetensors container format — **Implemented** (step `crates/hologram-ai-conformance/tests/bdd.rs:1178`).

### ST-02 `parse_streamed_header`
- Source: `witness.rs:45`.
- Signature: `B* → Result<[ (name, DType, [u64], (u64,u64)) ]>`.
- Definition:
  - Parse JSON. It must be an object; skip `__metadata__`.
  - Each entry must be an object.
  - dtype comes from ST-03, applied to `meta.dtype`, or `"F32"` if absent.
  - shape is `[d.as_u64() or 1]`, or `[]` if absent.
  - `data_offsets` must be a two-element array of u64 values, otherwise `Err`.
  - Output order is serde_json `Map` iteration order. That is sorted by key unless serde_json's `preserve_order` feature is on; this was not checked for this build.
- Not checked:
  - `begin ≤ end`
  - `end − begin = Π shape · size(dtype)`
  - non-overlap
  - contiguity
  - `end ≤ |data|`
- P1 "header parsed per the safetensors spec" (dictionary row `safetensors-header-streaming`, verified) — **Asserted-only**. The step at `bdd.rs:1208/1214` compares against `safetensors::SafeTensors::deserialize` on a well-formed fixture, so the parse agrees with the reference on valid input. On invalid input the reference rejects and this parser accepts. Alloy: `A_safetensors.als` `run gap_lenientHeaderAccepted`.

### ST-03 `safetensors_dtype`
- Source: `witness.rs:27`.
- Definition: a table F32, F16, BF16, I64, I32, I8, U8, BOOL. **Any other string (F64, I16, U16, F8_E4M3, …) maps to F32.**
- P1 "never silent" (`docs/conceptual-model/03-status-discipline.md` forbids silent divergence) — **Absent** for unknown dtypes.

### ST-04 `map_dtype` (product path)
- Source: `crates/hologram-ai-safetensors/src/parametric.rs:22`.
- Definition: F32, F16, BF16, I64, I32 map to their equivalents. Anything else is `Err("Unsupported safetensors dtype: …")`.
- P1 fails loud on unsupported dtypes — **Implemented**. Note the inconsistency with ST-03, which accepts I8/U8/BOOL and maps unknowns to F32.

### ST-05 `select_family` / `selected_family` / `supported_families`
- Source: `parametric.rs:125`, `:121`, `:113`; table `SUPPORTED_FAMILIES` at `:68–108`.
- Definition:
  - `name = config.architectures[0]` (must be a string).
  - If the key is missing, return `Err("…missing required key `architectures`…")`.
  - If `name ∉ {LlamaForCausalLM, Qwen2ForCausalLM, MistralForCausalLM, Phi3ForCausalLM}`, return `Err("unsupported architecture family `name` — supported families: …")`.
- Table (integers and booleans):

  | family | qkv_bias | fused_qkv | fused_gate_up | sliding_window_clamp | unsupported_knobs |
  |---|---|---|---|---|---|
  | Llama | false | false | false | false | — |
  | Qwen2 | true | false | false | false | — |
  | Mistral | false | false | false | true | — |
  | Phi3 | false | true | true | true | `partial_rotary_factor`, `rope_scaling` |

- P1 unsupported families fail with a message naming the family — **Implemented** (`family_registry_support.feature`; steps `bdd.rs:1285,1306,1439` and streamed `bdd.rs:1581–1614`; browser preflight `apps/web/bdd/steps.mjs:306`).

### ST-06 `ModelConfig::from_json`
- Source: `parametric.rs:199`; helpers `require_u64` at `:180` and `require_f64` at `:186`.
- Exact signature: `JSON → Result<Cfg>`. `Cfg` has fields in ℕ, plus `rms_norm_eps, rope_theta ∈ ℚ` in the exact spec.
- Definition:
  - Required u64 keys: hidden, layers, heads, vocab, intermediate, max_pos.
  - Required numeric keys: `rms_norm_eps` and `rope_theta`.
  - Constraints: `heads > 0`; `kv = num_key_value_heads` or `heads`; `kv > 0 ∧ heads mod kv = 0`.
  - `head_dim` is the config value, or `hidden/heads` (requiring `hidden mod heads = 0`).
  - `sliding_window`: `null` or absent → None; otherwise it must be a u64.
  - Flags `tie_word_embeddings`, `attention_bias`, `mlp_bias` default to false.
- Accepted but not rejected:
  - zero values for `hidden_size`, `vocab_size`, `intermediate_size`, `max_position_embeddings`, `head_dim`, `num_hidden_layers`, despite the message text "positive integer"
  - negative or zero `rms_norm_eps` and `rope_theta`
- `approx_from_json` for the two float keys:
  - (a) `parametric.rs:205–206`.
  - (b) Rounding steps: decimal text → f64 (serde_json, round-to-nearest) → `as f32`, a second rounding. Double rounding can differ from a direct decimal→f32 rounding in rare tie cases.
  - (c) Error relation: `|approx − x| ≤ 2^−24·|x| + 2^−53·|x|` for normal-range values. Concretely, from the usecases:
    - `1e-5` becomes `2748779·2^−38` (≈ 9.99999974737875e−6; |err| ≈ 2.53e−13)
    - `1e-6` becomes `8796093·2^−43` (≈ 9.99999997475243e−7; |err| ≈ 2.52e−15)
    - `rope_theta` values 10000, 100000 and 1000000 are exact in f32 (`625·2^4`, `3125·2^5`, `15625·2^6`)
  - (d) Breaks: values above f32 max become +Inf, values under 2^−149 become 0, and a negative zero is kept.
- P1 config keys extracted without architecture constants (`docs/conceptual-model/00-source.md`: "No architecture constant … hard-coded") — **Implemented** for the keys listed.
- P2 rejects semantic knobs it does not implement ("refuses to silently ignore a semantic config key", `:273–286`) — **Asserted-only**. Only Phi3 lists any knobs. Llama, Qwen2 and Mistral configs that carry `rope_scaling` are accepted silently, and the RoPE built ignores the scaling. Example: Llama-3.x configs carry `rope_scaling: {rope_type: "llama3"}` (upstream Transformers convention, not verified against a specific checkpoint here). Tests only cover Phi3 (`parametric.rs:2416`, `:2437`).

### ST-07 `reject_unsupported_knobs`
- Source: `parametric.rs:275`.
- Definition: for each `knob ∈ family.unsupported_knobs`, fail if `config[knob]` exists and is not null.
- P1 — **Implemented** for the table as written (see the ST-06 P2 gap).

### ST-08 `TensorManifest::new` / `dtype_of`
- Source: `parametric.rs:294`, `:317`.
- `new` requires `|keys| = |dtypes|`.
- `dtype_of(name)` returns the dtype if present, else F32. A missing tensor reads as F32 instead of failing; the graph builder separately checks `contains`.

### ST-09 `validate_layer_count`
- Source: `parametric.rs:693`.
- Definition: `L_manifest = 1 + max{ idx | key = "model.layers.idx.…" }`. If there are no such keys, return `Err`. Require `L_manifest = cfg.num_hidden_layers`.
- Edge: gaps are not detected. Layers {0, 29} alone satisfy `L = 30`; missing per-layer tensors fail later, when the builder looks them up.

### ST-10 `effective_context_ceiling` / `resolve_context_length`
- Source: `parametric.rs:721`, `:732`.
- Definitions (ℕ):
  - `ceiling = min(max_pos, sw)` if `family.sliding_window_clamp ∧ sw = Some`, else `max_pos`.
  - `resolve(None) = ceiling`.
  - `resolve(Some n) = n` if `1 ≤ n ≤ ceiling`, else `Err`.
- P1 the sliding-window clamp — **Implemented** (parametric graph scenarios; unit tests in `parametric.rs`).

### ST-11 `f32_head_floor_error` / `guard_f32_head_materialization`
- Source: `parametric.rs:522`, `:548`; ceiling `f32_materialization_ceiling` at `:510` is `2^31` when `usize::BITS ≤ 32`, else `u64::MAX`.
- Definition:
  - `bytes = 2·sat(rows·cols·4) + 3·rows·cols·elem_bytes`.
  - If `bytes > ceiling`, return `Err(message naming the tensor)`.
- Edge: `rows·cols` and `3·elems·elem_bytes` are unchecked multiplications, while `f32_weight_bytes` saturates. Overflow wraps in release and could pass the guard. This needs `rows·cols > 2^64/12`, which is unrealistic for real heads.

### ST-12 `build_parametric_graph_from_manifest` / `build_parametric_stage_graphs`
- Source: `parametric.rs:1577`, `:1643`.
- Structural spec (ℕ), checked by the steps:
  - output tensor `logits`
  - `2L + 1` RmsNorm nodes, each with `eps` equal to `approx_from_json(rms_norm_eps)` (step `bdd.rs:1323`, tolerance `1e-12` between two f32 roundings of the same f64, i.e. equality in practice)
  - GQA ratio `heads/kv`
  - RoPE `theta` within `1e-3` of the config value (step `bdd.rs:1345`, compare at `:1373`)
  - a tied head reuses the embedding weight
- Stage graphs: `stage_count = ⌈L/block⌉ + 1 + ⌈vocab/chunk_rows⌉` (`:1656–1660`).
- P1 "every dimension is a function of config.json" — **Implemented** for the structure checked. The rest of the graph body (about 1000 lines) was read only at the level of these counts and is not formalized further.
- P2 deterministic in the inputs — **Implemented** (no clock, RNG or hash-map iteration in the emitted order was seen at the entry points). Alloy: `A_compilation.als` `check compileFunctional`.
