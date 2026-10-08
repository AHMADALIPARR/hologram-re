<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# A_compilation — weightless compile, κ-map emission, staging, determinism

Team A catalog. Analyzed source: hologram-ai (MIT OR Apache-2.0), HEAD `c9609c0`, read-only. Verdicts follow `A_addressing.md`.

Exact domains: graphs as finite maps over ℕ ids, byte strings, and ℕ. Two f32 values are configuration only: `patch_budget_ratio = Some(0.75)`, which is exact in binary (`3·2^−2`), and the quantization encoder from A_quant.

---

### CP-01 `ModelCompiler` defaults
- Source: `crates/hologram-ai/src/compiler.rs:224`
- Default values: `mmap = true`, `quant_strategy = Auto` (a no-op, see A_quant QU-07), `patch_budget_ratio = Some(0.75)`, `address_model = false`.

### CP-02 `ModelCompiler::compile` / `prepare` / `import` (SafetensorsStreamed arm)
- Source: `compile` at `compiler.rs:256`, `prepare` at `:284`, streamed import at `:345–395`.
- Signature: `(config_json, keys : [String], kappas : [Label], shapes : [[u64]], dtypes : [DType]) → Result<AiGraph>`
- Definition:
  1. `G = build_parametric_graph_from_manifest(config, keys, dtypes, None)` (A_safetensors ST-12).
  2. For each `i < |keys|`:
     - `id = G.name→id(keys[i])`, or a fresh id `max(tensor_names)+1, …` if the name is absent from the graph.
     - Set `tensor_info[id] = (dtypes[i], shapes[i])` and `params[id] = External{kappa: kappas[i], range: None}`.
- Edges:
  - There is no check that `|kappas| = |shapes| = |dtypes| = |keys|`. A shorter slice panics on index. `compile_stages` (CP-05) does check this.
  - Keys the graph does not use are still added as params. They become constants and κ-map lines (CP-03), so the monolithic archive names tensors no node reads.
  - CP-05 rejects the same situation for staged builds ("consumed by no stage graph").
- `PreparedModel::context_length` falls back to `2048` when the graph metadata lacks the key (`compiler.rs:423`).
- P1 "weightless compile": no weight bytes are needed — **Implemented**. External params lower to 0-byte constants (`crates/hologram-ai-common/src/lower/builder.rs:2256–2260`).

### CP-03 `emit_params` (κ-map producer)
- Source: `crates/hologram-ai-common/src/lower/builder.rs:220–258`
- Definition:
  - Iterate params in ascending `TensorId` order (`sort_unstable` on distinct u32 keys, so the order is total).
  - Each param becomes a constant `cid`, numbered in insertion order.
  - Each External param appends `format!("{cid:?}:{κ}\n")`, or `"{cid:?}:{κ}@{off}+{len}\n"` for ranged bindings.
  - If any lines were emitted, add extension `holospaces.kappa_map`.
- Post: κ-map lines correspond one-to-one with External params, ordered by TensorId.
- P1 deterministic κ-map for a given graph — **Implemented** (sorted ids).
- P2 κ syntax validated — **Absent** (A_addressing AD-09 P2).

### CP-04 `compile_at_inner` pipeline
- Source: `compiler.rs:464`
- Definition: `concretize_all_dims(seq) → post_concretization_repair → quantize_weights(strategy) → extract_metadata → lower → hologram_compiler::compile`. A tokenizer section is added only when `bake_tokenizer` is set.
- `canonicalize_archive` is **not** called here. Its only callers are `crates/hologram-ai-wasm/src/lib.rs:280` and `:324`.

### CP-05 `compile_stages`
- Source: `crates/hologram-ai/src/staged.rs:48`
- Definition:
  - Require all four slices to have the same length (`:57`).
  - Build the stage graphs (A_safetensors ST-12).
  - For each stage and each key the stage graph names: bind `External{κ, range}`, where `range` is parsed from metadata `kappa_range:<key>` = `"off+len"`. Then compile the stage with `ModelCompiler::default()`.
  - After all stages, fail if any key was bound by no stage (`:127`).
- Post: every manifest key is bound in at least one stage. A key can be bound in several stages (e.g. a tied embedding).
- P1 "the staged partition must cover the model's tensors exactly" (error text) — **Implemented** as "at least once". "Exactly once" is not checked, and is not true for tied weights.

### CP-06 `canonicalize_archive` / `sort_weights_section`
- Source: `crates/hologram-ai/src/materialize.rs:443`, `:457`
- Definition:
  - A Weights section is laid out as `[u32 count] (fp[32] · len[u64] · bytes[len])*`.
  - The function re-emits the entries sorted by `fp` (bytewise, unstable sort), then reassembles the archive with a new BLAKE3 footer (A_addressing AD-10).
- P1 idempotent: `canon(canon(a)) = canon(a)` — **Implemented** (a sort is idempotent; test `materialize.rs:510`). Alloy: `check canonIdempotent`.
- P2 content-preserving permutation — **Implemented**, assuming `fp` determines `bytes`. Equal fps with unequal bytes would make the unstable order input-dependent.

### CP-07 deterministic compile (scenario `deterministic_compile.feature`)
- Steps: `crates/hologram-ai-conformance/tests/bdd.rs:1488` (Given), `:1502` and `:1521` (When), `:1548` and `:1562` (Then). `DET_COMPILE_RUNS = 8` (`:1460`).
- Formal claim: `∀ inputs x. compile(x)` is a function, i.e. `compile(x) = compile(x)` byte for byte. Equivalently, `κ(compile(x))` is a single value.
- What is tested: 8 compiles in **one process**, one fixture (handshake-tiny), F32 dtypes, κs = `kappa_of(name)` (`bind_external_kappas`, `:1465`).
  - Each new `HashMap` gets a fresh `RandomState`, so hash-order dependence within one process would probably show up.
  - Determinism across processes, machines or compiler versions is not tested.
- P1 — **Implemented** for the tested fixture (the step code does real byte comparison). As a universal claim it is **Asserted-only**: one fixture, one process. Alloy: `check compileFunctional` holds by construction, since the model defines compile as a function. The model cannot catch hidden nondeterminism. That limitation is stated in the .als file.

### CP-08 κ-map completeness (scenario `streamed_weightless_compile.feature`)
- Steps: `bdd.rs:1581` (Given, live Hub), `:1644` (When, `compile_at(Some(64))`), `:1663`, `:1670` (Then).
- Formal claim: `multiset{κ ∈ kappa_map} = set{κ_i | i < |keys|}`, with no duplicates.
- With content κs, `∃ i≠j. bytes_i = bytes_j ⇒ κ_i = κ_j`, so the multiset has a duplicate and the step's `dupes.is_empty()` fails. The scenario passes only because `fetch_helper.rs:133` sets `κ_i = "blake3:" ++ name_i`, and names are unique.
- P1 "κ-map names every manifest weight tensor exactly once" — **Asserted-only** (the stand-in κs make the property vacuous for content addressing). Alloy: `A_compilation.als` `run gap_dupContentBreaksExactlyOnce` (SAT) and `check exactlyOnceUnderNameKappas` (UNSAT).

### CP-09 `seeded_weights` (test fixture generator)
- Source: `bdd.rs:513`
- Exact definition (ℤ/2^64 and ℚ):
  - `state₀ = le_u64(BLAKE3(name)[0..8]) | 1`.
  - Step: `x ^= x<<13; x ^= x>>7; x ^= x<<17` (mod 2^64). This is plain xorshift64 with triple (13,7,17). The code has no multiply, so it is not xorshift64* as a nearby comment states.
  - `unit = ⌊x / 2^11⌋ / 2^53 ∈ [0, 1)` in ℚ, and `c = 2·unit − 1`.
  - Weight = `1 + c/100` for norm-like names, else `c/20`.
- `approx_seeded_weights`:
  - (a) `bdd.rs:526–531`.
  - (b) Rounding: `(x>>11) as f32` rounds a 53-bit integer to 24 bits. `(1u64<<53) as f32` is exact. The division by `2^53` is exact. `·2 − 1`, `·0.01` and `·0.05` each round. The literal `0.01` is `5368709·2^−29` and `0.05` is `13421773·2^−28`.
  - (c) `|unit_f32 − unit| ≤ 2^−25`.
  - (d) **`unit_f32 = 1.0` is reachable**: any `x>>11 ≥ 2^53 − 2^28` rounds up to `2^53`. So the comment's `[0, 1)` is false in f32. Deterministic otherwise; there are no sums.
