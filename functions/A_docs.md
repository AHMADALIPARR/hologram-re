<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# A_docs — slice-relevant documentation and model claims as predicates

Team A catalog. Analyzed source: hologram-ai (MIT OR Apache-2.0), HEAD `c9609c0`, read-only.

Scope: claims about addressing, acquisition, safetensors, ONNX, quantization, compilation and archivum, drawn from:
- `README.md`
- `docs/conceptual-model/00–04`
- `docs/architecture/ARCHITECTURE.md`
- `docs/adrs/{0003,0004,0018,ADR-001,ADR-002}`
- `model/{dictionary,status,usecases,oracles}.toml`

Verdicts follow `A_addressing.md`. Each claim is written as a predicate over the code. "Evidence" points to the catalog entry that holds the full definition.

---

## README.md

| id | claim (path:line) | predicate | verdict | evidence |
|---|---|---|---|---|
| D-01 | "formally verified" (`README.md:3`) | some slice component has a machine-checked proof against a formal spec | **Marketing** | 0 `.lean` files and no proof tooling in the slice. Tests and BDD exist, but those are not formal verification. |
| D-02 | "every feature begins as a Gherkin definition" (`README.md:7`) | `∀` slice behavior `b`. `∃` row ∧ feature for `b` | **Asserted-only** | Holds for dictionary rows (honesty gate). These have no row: native downloader, archivum, ONNX DQL and MatMulInteger, `quantize_weights` (A_gherkin coverage section). |
| D-03 | "every claim is validated against an authority this repository did not author" (`README.md:7`) | `∀` scenario. its Then is checked against external data or an external engine | **Asserted-only** | 14 of 40 scenario instances consult an external authority at test time (A_gherkin). |
| D-04 | "Every inference event hashes into an immutable JSONL ledger providing absolute legal provenance" (`README.md:31`) | append-only ∧ tamper-evident ∧ complete | **Marketing** | A_archivum AR-02 P2–P5 |
| D-05 | archivum "cryptographic provenance (via `UnifiedWitness` SHA-256)" (`README.md:19`) | each record carries SHA-256 of its event | **Implemented** (per record only) | AR-02 P1. No chain. |
| D-06 | "External authorities: ONNX Runtime, BLAKE3 test vectors, HuggingFace Hub, and the pinned hologram/holospaces substrate witnesses" (`README.md:54`) | each is consulted by some gating step | **Implemented** for BLAKE3, Hub and ORT (G-01, G-09, G-33). The substrate witnesses are same-ecosystem dependencies. | A_gherkin |

## docs/conceptual-model/00-source.md

| id | claim | predicate | verdict | evidence |
|---|---|---|---|---|
| D-07 | "No architecture constant, no model identity, and no capacity limit is hard-coded" (`:21–22`) | the graph is a function of `(config, manifest)` only | **Implemented** for the parametric builder. Exception: the 32-bit head ceiling `2^31` (`parametric.rs:510`) is a hard-coded capacity limit, stated openly in code. | ST-06, ST-11, ST-12 |
| D-08 | "Identical tensors — across shards, revisions, or models — deduplicate structurally" (`:42`) | `bytes_a = bytes_b ⇒ one blob` | **Implemented** for the browser κ-store (G-12) | AD-04, AQ-11 |
| D-09 | "The compiled archive is a pure k-form … never weight bytes" (`:44–48`) | External params give 0-byte constants plus a κ-map | **Implemented** | CP-02, CP-03 |
| D-10 | "every resolved buffer is re-hashed and must reproduce its κ" (`:50–51`) | `∀` resolve on the materialize path. `kappa_of(b) = κ` | **Implemented** for the first touch per session. A second read of a verified κ is trusted. `DirKappaStore::resolve` alone does not re-hash. | AD-05, AD-08 |
| D-11 | "GGML/ONNX quantization references — committed golden vectors for Q4_0/Q8_0" (`:91`) | the goldens equal GGML output | **Absent** for Q4_0 (27/16/28/4/0 mismatches); **Implemented** for Q8_0 | QU-01, QU-03 |

## docs/conceptual-model/01-k-representation.md

| id | claim | predicate | verdict | evidence |
|---|---|---|---|---|
| D-12 | "equality of κ is equality of content" (`:20`) | `κ(a) = κ(b) ⇔ a = b` | **Asserted-only**. The ⇐ direction is Implemented. The ⇒ direction is the BLAKE3 collision assumption, encoded in Alloy as a `fact`. | AD-01 P3 |
| D-13 | "transfer is bounded by nothing but the wire. Unbounded model size." (`:37`, `:48`) | no size bound in acquisition or compile | **Marketing**. Bounds that exist in code: <br>• JS safe-integer offsets, `≤ 2^53−1` (`download.worker.ts:124`) <br>• each tensor must fit in one `Uint8Array` buffer (`:394`) <br>• the 32-bit head guard (ST-11) | AQ-09, AQ-10 |
| D-14 | "a κ absent from the local store re-resolves from its source and must re-hash to its κ" (`:39–41`) | the remote path verifies like the local path | **Implemented** in `patch_constants`, the same check for any store. The browser resolver is team B's (HANDOFF). | AD-08 |

## docs/conceptual-model/02-user-journey.md

| id | claim | predicate | verdict | evidence |
|---|---|---|---|---|
| D-15 | "Resolve the repo's file manifest via the Hub API, with retry" (`:21`) | the manifest fetch retries | **Implemented** in the browser (`apps/web/src/ipc.ts:260–270`, 3 attempts). **Absent** natively: `model_info` makes one attempt (AQ-05). | |
| D-16 | companions = config, tokenizer, tokenizer_config, generation_config, "matched by its exact basename, never by suffix" (`:23–25`) | the companion set equals that list, compared with `=` | **Implemented** in the browser (`ipc.ts:287`, plus `special_tokens_map.json`). Natively, **Absent** for generation_config (AQ-03 P2). In the test stand-in it is a different list again (AQ-12). | |
| D-17 | "the journey validates the model before any shard byte moves" (`:26`) | `t(validate) < t(first shard byte)` | **Asserted-only**. The config is validated before any byte. Manifest validation needs the shard **header** bytes, which are fetched first. The steps do not check ordering (G-18…20). | |
| D-18 | "Peak transient memory is bounded by one tensor, never a shard or the model" (`:44`) | `peak ≤ max_t size(t) + chunk` | **Implemented** for the stream buffer. No step asserts it. | AQ-10 P2 |
| D-19 | "No stage publishes partial state" | each output appears atomically | **Absent** for the native downloader (in-place writes). Not checked for the browser. | AQ-06 P2 |

## docs/conceptual-model/03-status-discipline.md and model/status.toml

| id | claim | predicate | verdict | evidence |
|---|---|---|---|---|
| D-20 | levels: verified = green-gating, build = invariants-only, open = measurement-only with `gating = false` (`status.toml:10–26`) | the runner gates on verified and build rows and not on open rows | **Implemented** (`bdd.rs:5030–5040` uses Tier Suite vs Target) | |
| D-21 | the gate fails CI if "a gating suite contains a skipped, pending, or undefined step" (`03-status-discipline.md:26–30`) | `∀` gating feature. every step is bound | **Asserted-only**. Static `honesty.rs` does not resolve step bindings. Rust runs use `fail_on_skipped`; browser runs rely on cucumber-js `strict`. `quantized_rest` (build, gating) has 3 unbound steps (G-23, G-24), so a run would fail; none was observed. | |
| D-22 | forbidden: "a build row's scenarios cite an external authority as their basis" (`:36–37`) | `∀` row with status build. its oracles contain no live or external authority | **Absent** as enforcement. Build rows `streamed-weightless-compile`, `supported-search`, `model-preflight` and `network-skip` list `hf-hub` in `dictionary.toml`. | |

## docs/conceptual-model/04-resource-model.md

| id | claim | predicate | verdict | evidence |
|---|---|---|---|---|
| D-23 | Transit = set-difference(remote, known), known = provenance-recorded κ (`:14`) | skip exactly the tensors whose range key is in the prior under the same ETag | **Implemented** | AQ-11 P1, G-21 |
| D-24 | failed verification evaporates the entry (`KappaStore::invalidate`) and re-resolves (`:149–152`) | as stated | **Implemented**, with the unvalidated-path caveat | AD-06, AD-08 |

## docs/architecture/ARCHITECTURE.md

| id | claim | predicate | verdict | evidence |
|---|---|---|---|---|
| D-25 | `hologram-ai-quant`: "Q4_0/Q8_0 dequantization (GGML-conformant)" (`:78`) | `dq4 = ggml_q4_0 ∧ dq8 = ggml_q8_0` | **Absent** for Q4_0; **Implemented** for Q8_0 | QU-01 |
| D-26 | §4.1 companions (`config.json`, `tokenizer.json`, `generation_config.json`) are persisted per model (`:97–98`) | as stated | **Implemented** in the browser, **Absent** natively | D-16 |
| D-27 | §4.1 "κ-equality is content-equality" (`:99`) | as D-12 | **Asserted-only** | D-12 |
| D-28 | §4.3 step 3: verify each buffer re-hashes to its κ "and matches the constant's declared dtype × shape byte length" (`:118–119`) | `kappa_of(b) = κ ∧ |b| = size(dtype)·Π shape` | **Implemented** for the re-hash. The byte-length check is **Absent** in `materialize.rs` (no dtype or shape reference in the file). The downstream hologram loader may check it; that is team B's area and was not verified. | AD-08 |
| D-29 | cross-references "architecture §8", "§7", "§5.1", "§5.3" in code comments (e.g. `crates/hologram-ai-common/src/lower/mod.rs:12`) | the cited sections exist | **Absent**. ARCHITECTURE.md has sections 1–6, and §5 has no subsections. | `rg '^#' docs/architecture/ARCHITECTURE.md` |

## ADRs

| id | claim | predicate | verdict | evidence |
|---|---|---|---|---|
| D-30 | ADR-0004: `TensorInfo.quant: QuantDescriptor` carries "scale, zero-point, block size, scheme" | the struct has those fields | **Absent**. It has scheme, block_size and scale_dtype. | QU-06 P1 |
| D-31 | ADR-0004: optimization pass `QuantMatMulFusion` fuses Dequantize→MatMul; `LoweringOptions::quant_strategy = EagerDequant` exists | the pass and the enum variant exist | **Absent**. `rg QuantMatMulFusion\|EagerDequant` finds nothing. `QuantizedMatMul` lowers to a plain MatMul (`lower/dispatch.rs:252`). | |
| D-32 | ADR-0004: "No silent upcasting occurs anywhere in the pipeline" | no implicit dtype widening | **Asserted-only**. ONNX UINT16→INT32 and similar are declared but not converted (OX-01). The parametric builder adds explicit `Cast` to F32 (`parametric.rs:496`), which is explicit, not silent. | |
| D-33 | ADR-0004: "70B Q4 model loads as Q4 throughout" | a Q4 path exists end to end | **Absent**. There is no GGUF importer (address-only), no Q4_0 compile-time quantization (QU-07), and Q4_0 dequant is unused by the pipeline. | |
| D-34 | ADR-0018 (Accepted): "ONNX bytes are ingested via `uor_addr::onnx::canonicalize`"; "There are no architecture-specific passes"; "Every rule is verified against an external authoritative source" | ingestion calls uor-addr canonicalize; no architecture-specific passes | **Absent**. `hologram-ai-onnx` has no uor-addr dependency and decodes with prost (`lib.rs:100`). `uor_addr::onnx` is used only for addressing (`address.rs:63`, `:103`). `inject_lm_head_if_needed` (`hologram-ai-onnx/src/lib.rs:187`) is architecture-specific. The ONNX DQL decomposition is not verified against the spec (OX-07). | |
| D-35 | ADR-0003: format readers stay behind the import boundary and travel metadata as `AiGraph::metadata` | importers output `AiGraph` with metadata | **Implemented** (structural, read only) | ST-12, CP-02 |
| D-36 | ADR-001 `:22–24`, `:40`: "perfect internal κ-provenance", "immutable JSONL", "cryptographic chain of custody … enforced inherently" | as D-04 | **Marketing / Absent** | AR-02, AR-03 |
| D-37 | ADR-001 `:64`: "The analytic contradiction for RH is successfully closed … `FinalContradiction.lean` … `CriticalHeight.lean` … Real constant extraction (`extracted.json`) has been generated to validate the gap formula deterministically" | the Lean files exist and some code reads `extracted.json` | **Absent**. 0 `.lean` files in the repo. `extracted.json` (root; keys `eta_min 0.001, C_bound 1.5, tau_star -0.85, K0 2.1, A_param 100.0, T0 1.0, N 10.0`) is referenced only in this ADR sentence. No Rust, TS, shell, TOML or feature file reads it. `rg "extracted\.json"` over the whole tree, hidden files included, matches only ADR-001:64; the other `extracted` hits are unrelated English in comments. It does nothing in this repository. | |
| D-38 | ADR-002 `:7`: hologram-api has "built-in formal verification (`hologram-cnl`) and ledger logging (`hologram-archivum`)" | the archivum part as D-04; the CNL part is team B's | **Marketing** for the archivum part | AR-02 |

## model/dictionary.toml rows in the slice (statements as predicates)

| id | row (status) | statement as predicate | verdict |
|---|---|---|---|
| D-39 | kappa-addressing (verified) | `κ(b) = "blake3:" ++ hex(BLAKE3(b))` and it agrees with KATs and `holospaces::address` | **Implemented** (G-01) |
| D-40 | chunked-kappa-persisting (verified) | `∀` chunking. incremental = one-shot | **Implemented** for the blake3 crate (G-02…05) |
| D-41 | content-verified-resolution (build) | "Resolving κ → bytes re-hashes the bytes" | **Implemented** on the materialize path. The resolve primitive does not re-hash (AD-05). |
| D-42 | hf-model-resolution (verified) | "Any HuggingFace repo id resolves to its file manifest … classified" | **Asserted-only**. The test stand-in is exercised, not the product (G-09, G-10). |
| D-43 | safetensors-header-streaming (verified) | reference-crate files stream-parse identically | **Asserted-only**. The conformance-crate parser is exercised, not the product JS (G-11). |
| D-44 | streamed-download (build) | per-tensor streaming into OPFS, peak = one tensor | **Implemented**, but no step checks peak memory (G-12) |
| D-45 | supported-search, model-preflight, memory-guard, network-skip, companion-assets (build) | see G-25, G-18…20, G-15…17, G-21…22, G-14 | per scenario, see A_gherkin |
| D-46 | quantized-rest (build) | "A consumed wide blob never holds the quota against its own artifact" | **Absent**. No product code (QU-10) and the steps are unbound (G-23, G-24). The statement also does not match the feature, which is about a forced quantized tier and narration. |
| D-47 | parametric-graph (build) | graph = f(config, manifest) | **Implemented** (G-34…36) |
| D-48 | streamed-weightless-compile (build) | κ-map binds every weight constant to its κ | **Asserted-only** (G-40, stand-in κs) |
| D-49 | onnx-compile-parity (verified) | outputs within tolerance of ORT "on the committed fixtures and the official node corpus" | **Implemented** for the `mlp` fixture (G-33). There is no node-corpus scenario in s2. |
| D-50 | quant-dequant (verified) | "reproduces the GGML reference golden vectors bit-exactly" | **Absent** for Q4_0: the goldens are not GGML, and the step uses a tolerance. **Implemented** for Q8_0 against the goldens. |
| D-51 | family-registry-support (verified) | each family compiles from its pinned model; "κ-map covering every tensor exactly once" | **Asserted-only** (G-29…32, stand-in κs) |
| D-52 | deterministic-compile (build) | byte-identical archives for identical inputs | **Implemented** for one fixture in one process (G-27, G-28) |
| D-53 | parametricity (build) | an arbitrary use-case runs end to end | **Implemented** for handshake-tiny (G-37) |
| D-54 | arbitrary-architecture-coverage (open) | measured, never asserted | **Implemented**, as a count over a fixed list of 10 names (G-26) |

## model/oracles.toml and model/usecases.toml

| id | claim | verdict | evidence |
|---|---|---|---|
| D-55 | `blake3-kats` pin `master:test_vectors/test_vectors.json`, sha256 `dcb91ea8…f624` | **Implemented**. The upstream copy fetched on 2026-10-07 is byte-identical. | `checks/logs/A_external_authorities-*.txt` |
| D-56 | `quant-goldens`: "Block-dequant vectors matching the GGML reference layout", source ggml, `pin = ""` | **Absent** for Q4_0. There is no pin and no generator. | `checks/logs/A_quant_layout-*.txt` |
| D-57 | `onnx-fixtures`: "correctness is asserted by diffing against ORT, never against ourselves"; source `crates/hologram-ai-conformance/fixtures/generate.py` | **Implemented** for the `mlp` fixture used in G-33 | |
| D-58 | `journey-reference`: "Committed deterministic references … generated through the real k-form pipeline" | self-authored by definition. Listing it as an oracle does not make it an independent authority. | A_gherkin coverage |
| D-59 | all `sha256` pins of the oracle artifacts match the files on disk (12 artifacts) | **Implemented** | `checks/logs/A_external_authorities-*.txt` section 4 |
| D-60 | `xtask oracle-verify` / `pin-check` verify the oracles | **Asserted-only**. oracle-verify compares sha256 only. pin-check covers substrate-witness and HF/GitHub live-authority pins, and skips `blake3-kats`, `quant-goldens` and the reference implementations (read from `xtask`). | |
| D-61 | `usecases.toml` constants used by the scenarios: <br>• smollm2-135m: hidden 576, L 30, heads 9, kv 3, vocab 49152, rope 100000.0, eps 1e-5 <br>• handshake-tiny: 64/2/4/2/512, rope 10000.0, eps 1e-6 <br>• qwen2_5-0_5b: 896/24/14/2/151936, rope 1e6, eps 1e-6 | **Implemented** as data. The exact f32 images of the float fields are in `A_f32_inventory.md`. | `crates/hologram-ai-model/src/lib.rs:73–74` (f64 fields) |
