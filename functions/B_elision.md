<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# B_elision — stage residency, session verified-κ, derived store, content-addressed skip

Team B catalog. Source pin: hologram-ai @ `c9609c0`. Alloy: `alloy/B_elision-cache.als`. Labels are abstract atoms; collision-freedom is an assumption, stated where an assertion needs it. This file is the HANDOFF the A catalog points at for the session verified-set (`functions/A_addressing.md` AD-08).

---

### EL-01 `StagedRunner::execute_window` residency
- Source: `crates/hologram-ai/src/staged.rs:437`, admission and peak at `:480–502`
- Definition per stage, after `take()` of itself from the resident map: `bytes = stage_weight_bytes[stage]`; admissible iff `bytes > 0 ∧ resident_bytes + bytes ≤ budget ∧ probe(margin)` (probe defaults to admit). On admit, store the runner and add `bytes`. Peak update: `peak = max(peak, max(resident_bytes, bytes))`.
- P1 resident bytes never exceed the budget — **Implemented**. Alloy `check residentWithinBudget` expected UNSAT (`B-EC-1`). Scenario `stage_residency_cache.feature` "the resident set never exceeds the budget".
- P2 recorded peak ≥ true live weight (other residents + this stage) — **Absent**. A non-admitted stage that still runs is counted as `max(resident, bytes)`, not `resident + bytes`. Alloy `check recordedPeakCoversLive` expected SAT (`B-EC-2`). The bound that does hold is `live ≤ budget + bytes` (`B-EC-3`, expected UNSAT).
- P3 zero budget streams every stage every pass — **Implemented** (nothing is ever admitted). Alloy `check zeroBudgetStreams` expected UNSAT (`B-EC-4`). Matches "a zero budget is exactly the strict one-stage window".
- P4 a budget that already holds every stage keeps them resident — **Asserted-only**. True only if the admission probe also admits. A failing probe evicts. Alloy `check fullBudgetStaysResident` expected UNSAT with the probe assumed; `check fullBudgetStaysResidentNoProbe` expected SAT (`B-EC-5`, `B-EC-6`). Scenario "admission asks the environment with the model's own transient margin" is this probe.

### EL-02 session verified-κ set
- Source: `crates/hologram-ai/src/materialize.rs:229–371` (`materialize_archive_with` / `patch_constants`); session set shared from `staged.rs` (`share_verified_set`). First-touch rule is the one written out as AD-08 in `functions/A_addressing.md`.
- Definition across two passes: a κ already in the session set is resolved and executed without re-hashing; a κ not in the set is hashed, and on mismatch invalidated and re-resolved once. κ that executed in pass 1 enter the set for pass 2.
- P1 first touch never executes content whose hash differs from its κ — **Implemented**. Alloy `check firstTouchVerified` expected UNSAT (`B-EC-7`). Scenario `session_verified_kappa.feature` "a fresh session verifies at first touch and fails loud".
- P2 every executed blob in a session hashes to its κ — **Absent**. Content swapped in the store between passes is executed on the second pass without re-hashing. The scenario "rematerialization within a session is read-only resolution" asserts the no-re-hash half of this as a feature. Alloy `check alwaysVerified` expected SAT (`B-EC-8`).
- Time-of-check/time-of-use inside a single pass is the A finding (AD-08): a second requirement of the same κ in one `patch_constants` call is also trusted.

### EL-03 `stages_for_window` derived store
- Source: `crates/hologram-ai/src/staged.rs:942–980`
- Definition: load `(stages, kappas)` for the derivation key; intact iff lengths match, non-empty, and `kappa_of(stage_i) = kappas_i` for every i. Intact ⇒ return the stored bytes. Else evaporate and `compile_stages`, then store the new bytes with freshly computed κ.
- P1 served stages equal the derivation — **Absent**. The κ list is written beside the blobs, so a consistent rewrite of both passes the check. Alloy `check servedIsDerivation` expected SAT (`B-EC-9`).
- P2 a damaged blob whose recorded κ is still the derivation's κ is never served, assuming collision-freedom — **Implemented**. Alloy `check blobDamageDetected` expected UNSAT (`B-EC-10`). Scenario `derived_artifact_kappa.feature` "a corrupted derived entry evaporates and derivation recovers" is this case, not a same-directory rewrite of both files.

### EL-04 content-addressed elision (cache-free decode)
- Source: upstream reuse rule cited by the model header, `hologram-exec` session bind (substrate pin `18f553d8`, `crates/hologram-exec/src/session.rs` around the resident-label skip). Product scenario: `features/suites/s4_application/decode_elision.feature` "consecutive decode steps skip the unchanged prefix cone".
- Model: a node is reused on step 2 iff it is not a graph output and its derived label already occurred on step 1. Slices (`Kind::View`) are counted as skipped whether or not they were resident. Labels are hash-consed (no BLAKE3 collision assumed).
- P1 a node that depends on the changed input is never reused — **Implemented** in the model. Alloy `check noReuseDownstreamOfChange` expected UNSAT (`B-EC-11`). For a decoder whose tokens arrive as one `input_ids` tensor, every token-dependent node recomputes on every step: elision does not stand in for a KV cache. The dispatch comment at `dispatch.rs:584` says the same thing by mapping `KvSlotRead`/`KvSlotWrite` to Identity.
- P2 `last_skipped > 0` means some kernel output was reused — **Absent**. Slices count. Alloy `check skippedMeansComputeReuse` expected SAT (`B-EC-12`).
- The tiny-LM BDD shape (one input per position) does yield compute reuse of the untouched prefix. That is a non-vacuity run (`perPositionReuse`), not the product decoder shape.
