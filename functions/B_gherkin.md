<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# B_gherkin — s3 and s4 scenarios, traced only where the function catalog already reached

Team B catalog. Source pin: hologram-ai @ `c9609c0`, `features/suites/s3_execution/` and `features/suites/s4_application/`. Scenario titles were read from the feature files. A verdict here is the verdict of the function the scenario claims to check, not a fresh reading of every Then step. Rows marked **not traced** were not opened past the title in this pass.

---

## s3 execution

| Feature | Scenario | Verdict | Where |
|---|---|---|---|
| `stage_residency_cache` | within the budget, each stage materializes once per window | Asserted-only | EL-01 P4; probe can evict |
| `stage_residency_cache` | a zero budget is exactly the strict one-stage window | Implemented | EL-01 P3 |
| `stage_residency_cache` | the resident set never exceeds the budget | Implemented | EL-01 P1 |
| `stage_residency_cache` | cached and strict execution produce the same completion | not traced | step body not read |
| `stage_residency_cache` | the resident set survives across chat turns | not traced | |
| `stage_residency_cache` | admission asks the environment with the model's own transient margin | Implemented | EL-01 probe |
| `staged_execution` | the stage κ-maps partition the monolithic κ-map exactly | Asserted-only | EX-02 P1 holds for declared names, P2 does not |
| `staged_execution` | staged execution reproduces the monolithic logits exactly | not traced | |
| `staged_execution` | peak weight residency is bounded by the window, never the model | Asserted-only | EL-01 P2: recorded peak under-counts a streaming stage |
| `staged_execution` | generation over the staged runner equals the monolithic completion | not traced | |
| `staged_window_growth` | a short prompt executes in a sequence-sized window | Absent | SA-01 starts at 64, not at `|prompt|` |
| `staged_window_growth` | the window regrows geometrically as the sequence crosses a bucket | Implemented | SA-01, SA-03 |
| `staged_window_growth` | growable staged generation equals the fixed-window completion | not traced | |
| `staged_window_growth` | a sequence beyond the model's context fails loud | Implemented | SA-03, not SA-02 |
| `session_verified_kappa` | rematerialization within a session is read-only resolution | Implemented | EL-02; this is the gap, stated as a feature |
| `session_verified_kappa` | a fresh session verifies at first touch and fails loud | Implemented | EL-02 P1 |
| `derived_artifact_kappa` | a warm session resolves the derivation instead of re-deriving | Asserted-only | EL-03 P1: a consistent rewrite also "resolves" |
| `derived_artifact_kappa` | a corrupted derived entry evaporates and derivation recovers | Implemented | EL-03 P2, collision-freedom assumed |
| `tokenizer_parity` | encode matches the reference; decode round-trips | Asserted-only | TK-02; fallback eos not in the claim |
| `bounded_embedding` | a large-vocabulary embedding never materializes a whole-vocab F32 table | not traced | |
| `bounded_embedding` | a fused Phi3-family model runs monolithic and staged to identical logits | not traced | |
| `chunked_head` | four scenarios (chunk granularity, logit agreement, generation agreement, κ rematerialize) | not traced | |
| `execution_parity` | prefill logits match ONNX Runtime within tolerance | not traced | tolerance is an f32 claim; see B_f32 |
| `execution_parity` | greedy continuation matches ONNX Runtime token-for-token | not traced | |
| `idle_derivation` | pre-derivation moves no weights; later crossing resolves | not traced | |
| `kappa_materialization` | materialized equals inline; missing κ aborts; corrupt fails | not traced | overlaps A AD-08 |
| `kappa_provenance_resolution` | empty cache handshake; corrupted cache recovers | not traced | |
| `quantized_transit` | deterministic derivation; staged agrees; wide form never moves | not traced | team A owns quant layout |
| `saturation_residency` | cache corruption recovers; recovered content reproduces its label | not traced | |
| `single_position_head` | the pipeline emits one logit row for the consumed position | not traced | |
| `structural_{ce,cf,im,lw,za,zm}` | the witness is green in an isolated process | Asserted-only | CF-01: a green witness is a process exit, not an independent authority |
| `total_algebraic_path` | the float-dispatch fraction of the compiled plan is measured | Marketing | measurement, not a bound |

## s4 application

| Feature | Scenario | Verdict | Where |
|---|---|---|---|
| `app_domain_events` | the same event stream reduces to the same view | Implemented | SE-01 P1 |
| `app_domain_events` | independent events commute | not traced | |
| `app_domain_events` | order decides the terminal state of a request | Asserted-only | SE-01 P2 |
| `app_domain_events` | a registered model manifest preserves its κ | not traced | |
| `session_window` | a transcript outgrowing the context trims oldest-first and continues | Asserted-only | SE-03 P3 |
| `generation_loop` | greedy decode emits deterministic tokens across runs | Implemented | SA-06 P1, temperature ≤ 0 |
| `decode_elision` | consecutive decode steps skip the unchanged prefix cone | Asserted-only | EL-04: true for per-position inputs, false for a single `input_ids` tensor |
| `browser_journey` | fixture reaches runnable; forward pass; windowed execution reproduces the reference | not traced | `@target` rows may be report-only (CF-02 P2) |
| `chat_handshake` | three turns complete deterministically | not traced | |
| `deployment_gate` | the deploy workflow gates publishing on the journey | not traced | distinct from CN-01, which does not deploy |
| `live_model_journey` | SmolLM2-135M-Instruct completes the journey | not traced | opt-in live lane |
| `performance_contract` | decode throughput, compile time, and reuse are measured | Marketing | measurement |
| `warm_turn` | the second turn reuses the warm session | not traced | |
