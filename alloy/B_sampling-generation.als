-- SPDX-License-Identifier: AGPL-3.0-only
-- Team B model: generation loop, sampling, window policy.
-- Analyzed source: hologram-ai @ c9609c0 (MIT OR Apache-2.0)
--   crates/hologram-ai/src/engine.rs:37 (MIN_WINDOW = 64), :45-52 (geometric_window)
--   crates/hologram-ai/src/engine.rs:207-233 (GrowableSession::session_for)
--   crates/hologram-ai/src/staged.rs:778-800 (GrowableStagedSession::session_for, bails if want > max)
--   crates/hologram-ai/src/commands/generate.rs:228-238 (argmax), :253-288 (sample), :300-411 (generate_stream)
-- Integer-only. Logits are exact integers (no NaN, no -0.0, no rounding); B_f32_inventory.md
-- lists the float behaviour this abstracts away. Alloy checks this model, not the Rust.
--
-- Window arithmetic is parameterised by the minimum bucket m. The real constant m = 64 is
-- checked in B_window64.als at 10-bit Int (too slow to share a file with the seq sigs here).
-- Commands *_m4 use a scaled instance m = 4 at 7-bit Int (buckets 4, 8, 16); they are
-- evidence about the doubling-and-cap scheme, not about the value 64.
module B_sampling_generation

fun clampWant[want, mx: Int]: Int { (want < 1) => 1 else ((want > mx) => mx else want) }
-- smallest of m, 2m, 4m that is >= c  (the while-doubling loop, valid while c <= 4m)
fun bucketAtLeast[c, m: Int]: Int {
  (c =< m) => m else ((c =< plus[m, m]) => plus[m, m] else plus[plus[m, m], plus[m, m]])
}
fun geo[want, mx, m: Int]: Int {
  let b = bucketAtLeast[clampWant[want, mx], m] | (b < mx) => b else mx
}

one sig P { want, want2, mx, cur: Int }
pred inRange[m, wantTop: Int] {
  P.mx >= 1 and P.mx =< plus[plus[m, m], plus[m, m]]
  and P.want >= 1 and P.want =< wantTop and P.want2 >= 1 and P.want2 =< wantTop
  and P.cur >= 0 and P.cur =< P.mx
}


-- B-GEN-2: monotone in the request (scaled).
assert geoMonotone_m4 { (inRange[4, 20] and P.want =< P.want2) implies geo[P.want, P.mx, 4] =< geo[P.want2, P.mx, 4] }
check geoMonotone_m4 for 1 but 7 int expect 0

-- B-GEN-3: LmSession/SessionProvider contract "window >= want" for GrowableSession.
-- session_for keeps the current window if cur >= want, else builds geo(want, max). No error
-- path when want > max_window. Refuted.
fun growableWindow[cur, want, mx, m: Int]: Int { (cur >= want) => cur else geo[want, mx, m] }
assert growableHonoursContract_m4 { inRange[4, 20] implies growableWindow[P.cur, P.want, P.mx, 4] >= P.want }
check growableHonoursContract_m4 for 1 but 7 int expect 1

-- B-GEN-4: GrowableStagedSession bails when want > max_window, so any returned window is >= want.
assert stagedHonoursContract_m4 {
  (inRange[4, 20] and P.want =< P.mx) implies growableWindow[P.cur, P.want, P.mx, 4] >= P.want
}
check stagedHonoursContract_m4 for 1 but 7 int expect 0

-- generate_stream budget: remaining = max_window - |prompt|; budget = min(max_tokens, remaining).
abstract sig Bit {}
one sig On, Off extends Bit {}
one sig G { prompt, maxTok, k: Int, hasMax: one Bit }
fun budget: Int {
  let remaining = minus[P.mx, G.prompt] |
    (G.hasMax = On and G.maxTok < remaining) => G.maxTok else remaining
}
-- B-GEN-5: for every step k < budget, the running length prompt + k <= max_window.
assert sequenceWithinContext_m4 {
  (inRange[4, 20] and G.prompt >= 1 and G.prompt =< P.mx and G.maxTok >= 0 and G.maxTok =< 20
   and G.k >= 0 and G.k < budget) implies plus[G.prompt, G.k] =< P.mx
}
check sequenceWithinContext_m4 for 1 but 7 int expect 0

-- ---------- argmax / sampling over exact integer logits ----------
sig Rng {}
one sig L { v: seq Int, rngA, rngB: one Rng, temp: Int, keep0: Int }

-- argmax (generate.rs:228-238): strict '>' scan from index 0 => first maximal index.
pred isArgmax[i: Int] {
  i in L.v.inds
  and (all j: L.v.inds | L.v[j] =< L.v[i])
  and (all j: L.v.inds | j < i implies L.v[j] < L.v[i])
}
-- B-GEN-6: argmax is a total function on non-empty rows.
assert argmaxFunctional { (not L.v.isEmpty) implies (one i: L.v.inds | isArgmax[i]) }
check argmaxFunctional for 3 but 5 int, 5 seq expect 0

-- sample(temp <= 0, rng) = argmax(logits), rng unused (generate.rs:254-256).
fun sampleIdx[temp: Int, rng: Rng]: set Int { (temp =< 0) => { i: L.v.inds | isArgmax[i] } else L.v.inds }
-- B-GEN-7: temperature 0 => choice depends on the logits only.
assert tempZeroDeterministic {
  (L.temp =< 0 and not L.v.isEmpty) implies sampleIdx[L.temp, L.rngA] = sampleIdx[L.temp, L.rngB]
}
check tempZeroDeterministic for 3 but 5 int, 5 seq expect 0

-- top_k = 1, temp > 0: keep[0] after sort_unstable_by(descending) (generate.rs:258-265).
-- The unstable sort places SOME maximal index first on ties; the model allows any of them.
pred keep0Legal { L.keep0 in L.v.inds and (all j: L.v.inds | L.v[j] =< L.v[L.keep0]) }
-- B-GEN-8: "top_k = 1 equals argmax" (unit test top_k_one_is_argmax uses tie-free logits).
-- Refuted on ties in this model; whether the Rust std unstable sort actually reorders a given
-- tie is implementation-defined and not derived here.
assert topK1EqualsArgmax { (keep0Legal and not L.v.isEmpty) implies isArgmax[L.keep0] }
check topK1EqualsArgmax for 3 but 5 int, 5 seq expect 1

pred nonVacuousRow { #L.v = 4 and L.temp = 0 and L.rngA != L.rngB }
run nonVacuousRow for 3 but 5 int, 5 seq expect 1
pred nonVacuousWindow { inRange[4, 20] and P.want > P.cur and P.want =< P.mx }
run nonVacuousWindow for 1 but 7 int expect 1
