-- SPDX-License-Identifier: AGPL-3.0-only
-- Team B model: content-addressed elision, stage residency, session verified-κ set,
-- derived-stage store.
-- Analyzed source: hologram-ai @ c9609c0 (MIT OR Apache-2.0)
--   crates/hologram-ai/src/staged.rs:437-508 (StagedRunner::execute_window)
--   crates/hologram-ai/src/staged.rs:942-980 (stages_for_window), :861-898 (DirDerivedStore)
--   crates/hologram-ai/src/materialize.rs:229-371 (materialize_archive_with / patch_constants)
--   upstream hologram-exec @ 18f553d8 crates/hologram-exec/src/session.rs ~730-790 (reuse rule)
-- Integer-only (byte counts are small integers). Labels/κ are abstract atoms; the hash is
-- modelled as a function, collision-freedom is stated where an assertion needs it.
-- Alloy checks this model, not the Rust.
module B_elision_cache

open util/ordering[Stage] as SO   -- note: makes the Stage scope exact (4 stages)

------------------------------------------------------------------------
-- Part 1: one execute_window pass over ordered stages with a residency budget
------------------------------------------------------------------------
sig Stage {
  bytes: Int,                 -- stage_weight_bytes[stage] (counted on materialization)
  resBefore: set Stage,          -- resident set when this stage starts, after take() of itself
  admitted: lone Stage,       -- = this stage iff admissible
  probeOk: lone Stage,        -- admission_probe(margin) result for this stage (free)
  peakAfter: Int              -- peak_resident_weight_bytes after this stage
}
one sig Budget { b: Int, start: set Stage, peak0: Int }

fun rsum[X: set Stage]: Int { sum s: X | s.bytes }
fun resAfter[s: Stage]: set Stage { s.resBefore + s.admitted }
fun imax[a, c: Int]: Int { (a >= c) => a else c }

fact passSemantics {
  all s: Stage | s.bytes >= 0 and s.bytes =< 7
  Budget.b >= 0 and Budget.b =< 15 and Budget.peak0 >= 0 and Budget.peak0 =< 15
  rsum[Budget.start] =< Budget.b               -- invariant carried from earlier passes
  all s: Budget.start | s.bytes > 0            -- only admitted (bytes > 0) stages are resident
  -- first stage: resident = start minus itself (take())
  SO/first.resBefore = Budget.start - SO/first
  all s: Stage - SO/last | SO/next[s].resBefore = resAfter[s] - SO/next[s]
  -- admissible = bytes > 0 && resident + bytes <= budget && probe(margin)
  all s: Stage | (s.admitted = s) iff
      (s.bytes > 0 and plus[rsum[s.resBefore], s.bytes] =< Budget.b and s.probeOk = s)
  all s: Stage | s.admitted in s and s.probeOk in s
  -- peak = max(peak, max(resident_bytes, bytes))  (staged.rs:500-502)
  SO/first.peakAfter = imax[Budget.peak0, imax[rsum[resAfter[SO/first]], SO/first.bytes]]
  all s: Stage - SO/last | let n = SO/next[s] |
      n.peakAfter = imax[s.peakAfter, imax[rsum[resAfter[n]], n.bytes]]
}
-- weight bytes alive while stage s executes: the other resident stages plus s itself
fun live[s: Stage]: Int { plus[rsum[s.resBefore], s.bytes] }
-- s was materialized this pass iff it was not resident at the start
pred materialized[s: Stage] { s not in Budget.start }

-- B-EC-1: resident bytes never exceed the budget.
assert residentWithinBudget { all s: Stage | rsum[resAfter[s]] =< Budget.b }
check residentWithinBudget for 4 but 6 int expect 0

-- B-EC-2: recorded peak >= true live weight bytes. Refuted: a non-admitted stage that runs
-- while other stages are resident is counted as max(resident, bytes), not resident + bytes.
assert recordedPeakCoversLive { all s: Stage | SO/last.peakAfter >= live[s] }
check recordedPeakCoversLive for 4 but 6 int expect 1

-- B-EC-3: true live bytes <= budget + this stage's bytes (the bound that does hold).
assert liveBounded { all s: Stage | live[s] =< plus[Budget.b, s.bytes] }
check liveBounded for 4 but 6 int expect 0

-- B-EC-4 (stage_residency_cache.feature, zero budget): nothing is ever resident, so every
-- stage is materialized on every pass.
assert zeroBudgetStreams { Budget.b = 0 implies (all s: Stage | no resAfter[s] and materialized[s]) }
check zeroBudgetStreams for 4 but 6 int expect 0

-- B-EC-5 (budget holds the model): if all stages start resident, none is materialized and
-- all stay resident -- provided the probe admits them.
assert fullBudgetStaysResident {
  (Budget.start = Stage and (all s: Stage | s.bytes > 0 and s.probeOk = s))
    implies (all s: Stage | not materialized[s] and s in resAfter[s])
}
check fullBudgetStaysResident for 4 but 6 int expect 0

-- B-EC-6: same, without assuming the probe: a failing probe evicts a resident stage
-- (the probe reads current memory, which the budget does not bound). Refuted.
assert fullBudgetStaysResidentNoProbe {
  (Budget.start = Stage and (all s: Stage | s.bytes > 0)) implies (all s: Stage | s in resAfter[s])
}
check fullBudgetStaysResidentNoProbe for 4 but 6 int expect 1

pred passNonVacuous { some s: Stage | s.admitted = s and some t: Stage | no t.admitted }
run passNonVacuous for 4 but 6 int expect 1

------------------------------------------------------------------------
-- Part 2: session verified-κ set across two passes (materialize_archive_with)
------------------------------------------------------------------------
sig Kappa {}
sig Content { h: one Kappa }                 -- kappa_of(content)
abstract sig Pass {}
one sig P1, P2 extends Pass {}
one sig Store { at: Pass -> Kappa -> lone Content, retry: Pass -> Kappa -> lone Content }
one sig Session { need: set Kappa, verified: Pass -> set Kappa, executed: Pass -> Kappa -> lone Content }

fact verifiedSemantics {
  no Session.verified[P1]                     -- fresh session
  -- per pass, per required κ: verified κ is used without hashing; otherwise resolve,
  -- check kappa_of == κ, on mismatch invalidate + re-resolve once and check again.
  all p: Pass, k: Session.need |
    let c = Store.at[p][k], r = Store.retry[p][k] |
      (k in Session.verified[p]) =>
        Session.executed[p][k] = c
      else (some c and c.h = k) =>
        Session.executed[p][k] = c
      else (some r and r.h = k) =>
        Session.executed[p][k] = r
      else no Session.executed[p][k]
  all p: Pass | Session.executed[p].Content in Session.need
  -- κ that executed in P1 enter the session set for P2
  Session.verified[P2] = Session.executed[P1].Content
}

-- B-EC-7: first touch in a session never executes content whose hash differs from its κ.
assert firstTouchVerified { all k: Kappa, c: Session.executed[P1][k] | c.h = k }
check firstTouchVerified for 4 but 6 int expect 0

-- B-EC-8: "every executed weight blob hashes to its κ" across a session. Refuted: content
-- swapped in the store between passes is executed on P2 without re-hashing
-- (session_verified_kappa.feature asserts the no-re-hash half of this as a feature).
assert alwaysVerified { all p: Pass, k: Kappa, c: Session.executed[p][k] | c.h = k }
check alwaysVerified for 4 but 6 int expect 1

pred verifiedNonVacuous { some Session.verified[P2] and some k: Kappa | some Session.executed[P2][k] }
run verifiedNonVacuous for 4 but 6 int expect 1

------------------------------------------------------------------------
-- Part 3: derived-stage store integrity (stages_for_window)
------------------------------------------------------------------------
sig Key { derive: one Blob, storedBlob: lone Blob, storedK: lone Kappa2 }
sig Blob { h2: one Kappa2 }
sig Kappa2 {}
-- served = stored blob iff present and kappa_of(stored) = recorded κ; else recompile (= derive)
fun served[k: Key]: one Blob {
  (some k.storedBlob and some k.storedK and k.storedBlob.h2 = k.storedK) => k.storedBlob else k.derive
}
-- B-EC-9: served stages equal the derivation. Refuted: the κ list is written to the same
-- directory, so a consistent (blob, κ) rewrite passes the check.
assert servedIsDerivation { all k: Key | served[k] = k.derive }
check servedIsDerivation for 3 but 6 int expect 1

-- B-EC-10: if the recorded κ is the derivation's κ (only the blob was damaged) and the
-- hash is collision-free, a damaged blob is never served.
assert blobDamageDetected {
  (all disj x, y: Blob | x.h2 != y.h2) implies
    (all k: Key | k.storedK = k.derive.h2 implies served[k] = k.derive)
}
check blobDamageDetected for 3 but 6 int expect 0

------------------------------------------------------------------------
-- Part 4: content-addressed elision (upstream reuse rule) over two decode steps
------------------------------------------------------------------------
abstract sig Step {}
one sig S1, S2 extends Step {}
sig Op {}
abstract sig Label {}
sig Fresh extends Label {}
sig Derived extends Label { op: one Op, args: set Label }
fact labelsCanonical {                      -- hash-consing: no BLAKE3 collision assumed
  all disj a, c: Derived | not (a.op = c.op and a.args = c.args)
  no l: Derived | l in l.^args
}
abstract sig Kind {}
one sig Compute, View extends Kind {}
abstract sig Tensor { lab: Step -> one Label }
sig Input extends Tensor {}
sig Node extends Tensor { nop: one Op, ins: some Tensor, kind: one Kind }
sig Out in Node {}                          -- graph outputs always re-fire
one sig X in Input {}                       -- the input whose bytes change between steps
fact elisionSemantics {
  all i: Input, s: Step | i.lab[s] in Fresh
  -- derive_label(op, in_labels); inputs as a set (commutative sort); a set model makes
  -- MORE labels coincide than the ordered rule, so "no reuse" results carry over.
  all n: Node, s: Step | n.lab[s] in Derived and n.lab[s].op = n.nop and n.lab[s].args = n.ins.lab[s]
  no n: Node | n in n.^ins
  X.lab[S2] not in Tensor.lab[S1]           -- new input bytes, new label
  all i: Input - X | i.lab[S2] = i.lab[S1]  -- weights / unchanged inputs
}
-- interior node with a label resident from the previous step => skipped (bind_resident)
pred reused[n: Node] { n not in Out and n.lab[S2] in Tensor.lab[S1] }
-- last_skipped also counts every interior Slice (bind_view), resident or not
pred counted[n: Node] { n not in Out and (reused[n] or n.kind = View) }

-- B-EC-11: a node that depends on the changed input is never reused. For a real decoder
-- whose tokens arrive as ONE input_ids tensor, every token-dependent node recomputes on
-- every step: elision does not stand in for a KV cache.
assert noReuseDownstreamOfChange { all n: Node | X in n.^ins implies not reused[n] }
check noReuseDownstreamOfChange for 5 but 6 int expect 0

-- B-EC-12: "last_skipped > 0 means some kernel output was reused". Refuted: slices count.
assert skippedMeansComputeReuse {
  (some n: Node | counted[n]) implies (some n: Node | reused[n] and n.kind = Compute)
}
check skippedMeansComputeReuse for 5 but 6 int expect 1

-- Non-vacuity: per-position inputs (the shape of the BDD tiny_lm) do yield reuse.
pred perPositionReuse { some n: Node | reused[n] and n.kind = Compute and X not in n.^ins }
run perPositionReuse for 5 but 6 int expect 1
