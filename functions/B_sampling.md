<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# B_sampling — geometric window, argmax, temperature sample, generation budget

Team B catalog. Source pin: hologram-ai @ `c9609c0`. Alloy: `alloy/B_sampling-generation.als` (scaled `m = 4`) and `alloy/B_window64.als` (real `MIN_WINDOW = 64`). The Alloy logits are exact integers; the Rust path is f32/f64. Float behaviour is listed in `B_f32_inventory.md`, not re-proved here.

---

### SA-01 `geometric_window`
- Source: `crates/hologram-ai/src/engine.rs:37` (`MIN_WINDOW = 64`), `:45–52`
- Signature: `geometric_window : (want : ℕ, max_window : ℕ) → ℕ`
- Definition: `want' = clamp(want, 1, max(max_window, 1))`; `w = 64`; while `w < want'` do `w = w.saturating_mul(2)`; return `min(w, max(max_window, 1))`.
- P1 `window ≤ max_window` — **Implemented**. Alloy `check geoLeMax_m64` expected UNSAT (`B-GEN-1a`).
- P2 `want ≤ max_window ⇒ window ≥ want` — **Implemented** for the real constant 64, inside the bucket list the model covers (`max_window ≤ 256`). Alloy `check geoCoversWant_m64` expected UNSAT (`B-GEN-1b`).
- P3 `want > max_window ⇒ window = max_window`, no error — **Implemented**. Silent cap. Alloy `check geoCapsAtMax_m64` expected UNSAT (`B-GEN-1c`).
- P4 the window is one of `{64, 128, 256}` or exactly `max_window` — **Implemented** under the same bound. Alloy `check geoIsBucketOrCap_m64` expected UNSAT (`B-GEN-1d`).
- P5 monotone in `want` — **Implemented** on the scaled model. Alloy `check geoMonotone_m4` expected UNSAT (`B-GEN-2`).

### SA-02 `GrowableSession::session_for`
- Source: `crates/hologram-ai/src/engine.rs:208`
- Definition: if the current window is already `≥ want`, keep it; else compile `geometric_window(want, max_window)` and load it. No error path when `want > max_window`: the request is clamped by SA-01 P3.
- Contract stated on `SessionProvider` (`engine.rs:114`): the served window is `≥ want`.
- P1 `window ≥ want` for every request — **Absent**. A request past `max_window` is served `max_window`. Alloy `check growableHonoursContract_m4` expected SAT (`B-GEN-3`). The generation loop does not rely on this path for over-long prompts; `generate_stream` rejects those before calling `session_for` (SA-04).

### SA-03 `GrowableStagedSession::session_for`
- Source: `crates/hologram-ai/src/staged.rs:779`
- Definition: if `want > max_window`, `bail!` naming both lengths; else if the current window does not fit, drop it and build `geometric_window(want, max_window)`.
- P1 any returned window is `≥ want` — **Implemented** (the bail is the difference from SA-02). Alloy `check stagedHonoursContract_m4` expected UNSAT (`B-GEN-4`).
- Scenario `staged_window_growth.feature` "a sequence beyond the model's context fails loud" matches this path, not SA-02.

### SA-04 `generate_stream` budget
- Source: `crates/hologram-ai/src/commands/generate.rs:300–340`
- Definition: `eos = cfg.eos.unwrap_or_else(tokenizer.eos_token_id)`; encode the prompt; `bail` if empty or if `|prompt| > max_window`; `remaining = max_window - |prompt|`; `budget = min(max_tokens, remaining)` (`None` means `remaining`); loop `budget` times, each step calling `session_for(cur_len)`.
- P1 for every step `k < budget`, `|prompt| + k ≤ max_window` — **Implemented**. Alloy `check sequenceWithinContext_m4` expected UNSAT (`B-GEN-5`). A prompt that fills the window yields `budget = 0` and the empty completion; the comment calls that not an error.
- P2 the provider's window is `≥ cur_len` — **Asserted-only** as a `debug_assert` (`generate.rs` after the `session_for` call). Release builds do not enforce it. SA-03 does; SA-02 does only when `cur_len ≤ max_window`, which this budget already guarantees.

### SA-05 `argmax`
- Source: `crates/hologram-ai/src/commands/generate.rs:228–238`
- Signature: `argmax : Seq<f32> → u32`
- Definition: scan from index 0; update on strict `>`; seed `best_v = f32::NEG_INFINITY`. Empty row returns 0. Ties keep the first index.
- P1 total function on a non-empty row, first maximal index — **Implemented** for exact comparable values. Alloy `check argmaxFunctional` expected UNSAT (`B-GEN-6`). NaN never wins a strict `>` (IEEE), so a NaN row returns 0. Not modelled in Alloy.
- Test `argmax_picks_highest` (`generate.rs:418`) uses tie-free rows.

### SA-06 `sample`
- Source: `crates/hologram-ai/src/commands/generate.rs:253–288`
- Definition: if `temperature ≤ 0` return `argmax` and ignore `rng`. Else sort indices by descending logit with `sort_unstable_by` and `partial_cmp(...).unwrap_or(Equal)`; keep `top_k.clamp(1, n)` or all; softmax the kept logits in f64 after an f32 max-shift; inverse-CDF with SplitMix64 (`next_unit`, `:241`).
- P1 `temperature ≤ 0` depends only on the logits — **Implemented**. Alloy `check tempZeroDeterministic` expected UNSAT (`B-GEN-7`).
- P2 `top_k = 1` equals `argmax` — **Asserted-only**. The unit test uses tie-free logits. On ties the unstable sort may place any maximal index first. Alloy `check topK1EqualsArgmax` expected SAT (`B-GEN-8`).
- P3 sampling is a pure function of `(logits, temperature, top_k, seed)` — **Asserted-only**. SplitMix64 is deterministic, but the f32 divide, the f64 `exp`, and the unstable sort are not pinned to a rounding spec. Scenario `generation_loop.feature` "greedy decode emits deterministic tokens across runs" is the `temperature ≤ 0` special case, which does not touch those steps.
