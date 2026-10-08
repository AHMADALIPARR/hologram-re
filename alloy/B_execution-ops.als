-- SPDX-License-Identifier: AGPL-3.0-only
-- Team B model: AiGraph validation / topological order, staged partition cover,
-- op dispatch collapse.
-- Analyzed source: hologram-ai @ c9609c0 (MIT OR Apache-2.0)
--   crates/hologram-ai-common/src/ir/graph.rs:200-279 (validate), :284-300 (topo_order cache),
--     :325-380 (compute_topo_order, producer map), has_cycle
--   crates/hologram-ai/src/staged.rs:48-133 (compile_stages)
--   crates/hologram-ai-common/src/lower/dispatch.rs (dispatch: Gelu/GeluApprox, Trilu, Opaque, Softmax axis)
-- Integer-only (no tensor values are modelled). util/ordering fixes the N scope exactly.
-- Alloy checks this model, not the Rust.
module B_execution_ops

open util/ordering[N] as NO

------------------------------------------------------------------------
-- Part 1: graph validation
------------------------------------------------------------------------
sig T {}
sig N { ins: set T, outs: set T }               -- nodes, in `nodes`-vector order
one sig G { gin: set T, params: set T, reg: set T, cacheFull: one Flag }
abstract sig Flag {}
one sig Yes, No extends Flag {}

-- producer map: later positions overwrite earlier ones (HashMap::insert in vector order)
fun producer[t: T]: lone N { { n: N | t in n.outs and no m: NO/nexts[n] | t in m.outs } }
fun dep: N -> N { { c, p: N | some t: c.ins | p = producer[t] } }
pred acyclic { no n: N | n in n.^dep }
pred registered { G.gin + G.params + N.ins + N.outs in G.reg }
-- validate() returns no errors (empty-param and subgraph checks abstracted away);
-- has_cycle() compares the (possibly cached) order length with nodes.len().
-- cacheFull = Yes models a cached order of full length left over from before a mutation.
pred validates { registered and (G.cacheFull = Yes or acyclic) }
pred validatesFresh { registered and acyclic }

-- (No assertion for "Kahn covers all nodes iff acyclic": in this model that is the definition
-- of has_cycle, so a check would be a tautology.)
-- B-EX-2: validate => every tensor has at most one producer (SSA). Refuted: no such check;
-- the last producer silently wins.
assert validateSingleProducer { validatesFresh implies (all t: T | lone outs.t) }
check validateSingleProducer for 4 expect 1
-- B-EX-3: validate => every consumed tensor is produced, a graph input, or a param. Refuted:
-- registration in tensor_info is the only requirement.
assert validateInputsBound { validatesFresh implies (all t: N.ins | t in N.outs + G.gin + G.params) }
check validateInputsBound for 4 expect 1
-- B-EX-4: with a stale full-length topo cache, validate => acyclic. Refuted (documented
-- precondition: callers must invalidate_topo_cache after mutation; nothing enforces it).
assert validateAcyclicEvenIfCached { validates implies acyclic }
check validateAcyclicEvenIfCached for 4 expect 1
pred graphNonVacuous { validatesFresh and some dep and some n: N | some n.outs }
run graphNonVacuous for 4 expect 1

------------------------------------------------------------------------
-- Part 2: compile_stages partition
------------------------------------------------------------------------
sig Key {}
sig Stage { declares: set Key, consumes: set Key, ranged: set Key }
one sig Manifest { keys: set Key }
fact stageShape { all s: Stage | s.consumes in s.declares and s.ranged in s.declares }
-- binds = declares ∩ manifest ; success iff every manifest key bound by some stage
pred compileOk { Manifest.keys in Stage.declares }
fun binds[s: Stage]: set Key { s.declares & Manifest.keys }

-- B-EX-5: success => every manifest tensor is bound in some stage κ-map.
assert partitionCovers { compileOk implies Manifest.keys in Stage.(binds) }
check partitionCovers for 4 expect 0
-- B-EX-6: success => every manifest tensor is CONSUMED by some stage. Refuted at this level:
-- the check is on declared names (graph.tensor_names), not on node inputs; it is the
-- builder (team A area) that makes declared = consumed.
assert partitionConsumes { compileOk implies Manifest.keys in Stage.consumes }
check partitionConsumes for 4 expect 1
-- B-EX-7: a key bound by two stages binds the same κ (tied embedding): κ is a function of
-- the key in the manifest, so holds by construction.
sig Kap {}
one sig KMap { kappaOf: Key -> one Kap }
fun stageMap[s: Stage]: Key -> Kap { binds[s] <: KMap.kappaOf }
assert sharedKeySameKappa {
  all s1, s2: Stage, k: binds[s1] & binds[s2] | stageMap[s1][k] = stageMap[s2][k]
}
check sharedKeySameKappa for 4 expect 0
pred stagesNonVacuous { compileOk and some disj s1, s2: Stage | some binds[s1] & binds[s2] }
run stagesNonVacuous for 4 expect 1

------------------------------------------------------------------------
-- Part 3: dispatch is not injective on semantics
------------------------------------------------------------------------
abstract sig Sem {}
one sig ErfGelu, TanhGelu, LowerTri, Id, Unknown, SoftmaxLast, SoftmaxAxis0 extends Sem {}
abstract sig Kern {}
one sig KGelu, KIdentity, KSoftmax extends Kern {}
-- facts transcribed from dispatch.rs (header claim: "every desugaring exact"):
--   Gelu -> OpKind::Gelu, GeluApprox -> OpKind::Gelu (upstream gelu_f is the tanh form)
--   Trilu -> Identity, Opaque -> Identity, Softmax{axis} -> Softmax (axis dropped)
one sig Dispatch { k: Sem -> one Kern }
fact transcribed {
  Dispatch.k = ErfGelu -> KGelu + TanhGelu -> KGelu + LowerTri -> KIdentity + Id -> KIdentity
             + Unknown -> KIdentity + SoftmaxLast -> KSoftmax + SoftmaxAxis0 -> KSoftmax
}
-- B-EX-8: same kernel => same semantics. Refuted by the transcribed table.
assert dispatchFaithful { all a, b: Sem | Dispatch.k[a] = Dispatch.k[b] implies a = b }
check dispatchFaithful for 7 expect 1
