-- SPDX-License-Identifier: AGPL-3.0-only
-- Team A model: Q4_0 / Q8_0 integer structure, Q4_0 layout vs GGML,
-- int8 per-channel encoding in scaled integers, compile-time quant strategy.
-- Analyzed source: hologram-ai @ c9609c0 (MIT OR Apache-2.0).
-- Catalog: functions/A_quant.md (QU-01, QU-03, QU-05, QU-07).
-- Alloy checks THIS MODEL, not the Rust. Integer-only. The encode checks
-- state the EXACT spec (rationals scaled to integers); the f32 code can move
-- Q by one step near ties (A_quant QU-05 (c)), so those UNSAT results do not
-- transfer to f32 without that error relation.
module A_quant

fun abs[x: Int]: Int { x < 0 implies minus[0, x] else x }

-------------------------------------------------- QU-01 nibble decode
-- byte b in [0,255]; lo = b mod 16, hi = b div 16; value = nibble - 8
pred isByte[b: Int] { b >= 0 and b <= 255 }
fun lo4[b: Int]: Int { minus[rem[b, 16], 8] }
fun hi4[b: Int]: Int { minus[div[b, 16], 8] }

assert nibbleRange {
  all b: Int | isByte[b] implies
    (lo4[b] >= -8 and lo4[b] <= 7 and hi4[b] >= -8 and hi4[b] <= 7)
}
check nibbleRange for 10 Int

-------------------------------------------------- QU-03 int8 decode
fun int8[b: Int]: Int { b < 128 implies b else minus[b, 256] }
assert int8Range { all b: Int | isByte[b] implies (int8[b] >= -128 and int8[b] <= 127) }
check int8Range for 10 Int

-------------------------------------------------- QU-01 layout
-- Output position p in [0,31] reads source (half, idx): half 0 = low nibble,
-- 1 = high nibble of qs[idx].
--   interleaved (q4_0.rs:20): p -> (p mod 2, p div 2)
--   GGML split  (ggml-quants.c:459): p -> (p div 16, p mod 16)
pred isPos[p: Int] { p >= 0 and p <= 31 }
fun iHalf[p: Int]: Int { rem[p, 2] }
fun iIdx[p: Int]: Int { div[p, 2] }
fun gHalf[p: Int]: Int { div[p, 16] }
fun gIdx[p: Int]: Int { rem[p, 16] }
pred sameSource[p: Int] { iHalf[p] = gHalf[p] and iIdx[p] = gIdx[p] }

-- The interleaved map is a bijection onto the 32 sources.
assert interleavedIsBijection {
  all p, q: Int | (isPos[p] and isPos[q] and iHalf[p] = iHalf[q] and iIdx[p] = iIdx[q]) implies p = q
}
check interleavedIsBijection for 7 Int
-- The two layouts read the same source only at positions 0 and 31, so the
-- outputs agree elementwise only where the block's nibble values happen to
-- coincide (the goldens differ on 27/16/28/4/0 of 32: checks/A_quant_layout.sh).
assert q4LayoutsDifferUnlessSymmetric {
  all p: Int | (isPos[p] and sameSource[p]) iff (p = 0 or p = 31)
}
check q4LayoutsDifferUnlessSymmetric for 7 Int

-------------------------------------------------- QU-05 encode (exact spec)
-- Scaled integers: w and amax are integers with 0 < amax and |w| <= amax.
-- Q = rhaz(127*w/amax) = sign(w) * floor((254*|w| + amax) / (2*amax)).
-- Exact claim |Q*s - w| <= s/2 with s = amax/127  <=>  |254*w - 2*Q*amax| <= amax.
pred encIn[w, amax: Int] { amax > 0 and amax <= 7 and abs[w] <= amax }
fun encQ[w, amax: Int]: Int {
  w < 0 implies minus[0, div[plus[mul[254, abs[w]], amax], mul[2, amax]]]
        else div[plus[mul[254, w], amax], mul[2, amax]]
}
assert encodeWithinRange {
  all w, amax: Int | encIn[w, amax] implies (encQ[w, amax] >= -127 and encQ[w, amax] <= 127)
}
check encodeWithinRange for 12 Int
assert encodeHalfStepBound {
  all w, amax: Int | encIn[w, amax] implies
    abs[minus[mul[254, w], mul[mul[2, encQ[w, amax]], amax]]] <= amax
}
check encodeHalfStepBound for 12 Int
assert encodeMaxIs127 {
  all w, amax: Int | (encIn[w, amax] and abs[w] = amax) implies abs[encQ[w, amax]] = 127
}
check encodeMaxIs127 for 12 Int

-------------------------------------------------- QU-07 quantize_weights
abstract sig Strategy {}
one sig SNone, SAuto, SQ4_0, SQ8_0, SQ2_0, SInt8, SInt4 extends Strategy {}
sig Graph { f32MatMulWeights: Int }          -- count of eligible inline f32 MatMul weights
sig Pass { strat: one Strategy, gIn, gOut: one Graph, err: lone ErrInt4 }
one sig ErrInt4 {}
-- reading of quantize.rs:31-35 and the Int8 loop
fact passSemantics {
  all p: Pass {
    p.strat = SInt4 implies some p.err
    p.strat != SInt4 implies no p.err
    p.strat = SInt8 implies p.gOut.f32MatMulWeights = 0
    p.strat not in SInt8 + SInt4 implies p.gOut = p.gIn
  }
  all g: Graph | g.f32MatMulWeights >= 0
}
assert nonInt8IsIdentity { all p: Pass | p.strat not in SInt8 + SInt4 implies p.gOut = p.gIn }
check nonInt8IsIdentity for 4 but 4 Int

run someInt8Rewrite { some p: Pass | p.strat = SInt8 and p.gIn.f32MatMulWeights > 0 } for 4 but 4 Int
-- GAP QU-07 P1: compiler.rs:195-197 documents Q4_0 compile-time quantization;
-- the pass leaves the graph unchanged.
run gap_q4_0DocumentedButNoop {
  some p: Pass | p.strat = SQ4_0 and p.gIn.f32MatMulWeights > 0 and p.gOut = p.gIn
} for 4 but 4 Int
-- non-vacuity for the layout facts: a position where the layouts read different sources
run gap_layoutMismatchPosition { some p: Int | isPos[p] and not sameSource[p] } for 7 Int
-- non-vacuity for encode: an input strictly inside the range
run encodeInstance { some w, amax: Int | encIn[w, amax] and w < 0 and abs[w] < amax } for 12 Int
