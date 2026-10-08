<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# B_execution — graph validation, stage partition, dispatch collapse

Team B, reverse-engineering catalog. Analyzed source: hologram-ai (MIT OR Apache-2.0), HEAD `c9609c0`, cloned read-only at `/tmp/hologram-ai-src`. Line numbers below were checked against that tree. Alloy checks the models in `alloy/B_execution-ops.als`, not the Rust.

Verdicts: **Implemented** (the code enforces it for every input in the stated domain) · **Asserted-only** (a test, scenario or doc asserts it, but the code does not enforce it in general) · **Marketing** (prose only, no mechanism and no test) · **Absent** (the mechanism does not exist, or the code does the opposite).

Arithmetic domain: node and tensor identities, finite sets, byte counts. No tensor values. `dispatch.rs` carries f32 attributes (`Lrn.alpha`, `Attention.rope_base`); those attributes are not evaluated here. See `B_f32_inventory.md`.

---

### EX-01 `AiGraph::validate`
- Source: `crates/hologram-ai-common/src/ir/graph.rs:200`
- Signature: `validate : AiGraph → Seq<ValidationError>`
- Definition: collect missing `tensor_info` for every graph input, graph output, node input, node output, and param key; reject empty inline params; push `"graph contains a cycle"` if `has_cycle()`; recurse into subgraphs.
- `has_cycle` compares the length of the (possibly cached) Kahn order with `nodes.len()` (`graph.rs:284–300`, `compute_topo_order` at `:323`).
- P1 every referenced tensor id is registered — **Implemented** (the only positive check).
- P2 SSA: at most one producer per tensor — **Absent**. The producer map is a `HashMap` filled in vector order; a later node silently overwrites an earlier producer. Alloy `check validateSingleProducer` is expected SAT (`B-EX-2`).
- P3 every consumed tensor is produced, a graph input, or a param — **Absent**. Registration in `tensor_info` is enough. Alloy `check validateInputsBound` expected SAT (`B-EX-3`).
- P4 `validate` implies acyclic — **Asserted-only**. True only if the topo cache was invalidated after the last mutation. A stale full-length cache makes `has_cycle` return false. The comment states the precondition; nothing enforces it. Alloy `check validateAcyclicEvenIfCached` expected SAT (`B-EX-4`).

### EX-02 `compile_stages`
- Source: `crates/hologram-ai/src/staged.rs:48`
- Signature: `compile_stages : (config, keys, kappas, shapes, dtypes, window?, layers_per_stage) → Result<Seq<ArchiveBytes>, Error>`
- Definition (partition half, the part the Alloy model covers): each stage declares a set of κ keys; success requires every manifest key to appear in some stage's declared set. The κ of a key is taken from the manifest, so a key bound by two stages carries the same κ by construction.
- P1 success ⇒ every manifest tensor is bound in some stage κ-map — **Implemented** at this layer. Alloy `check partitionCovers` expected UNSAT (`B-EX-5`). Scenario `features/suites/s3_execution/staged_execution.feature` "the stage κ-maps partition the monolithic κ-map exactly" asserts the stronger consumer reading.
- P2 success ⇒ every manifest tensor is *consumed* by some stage — **Asserted-only**. The check is on declared names (`graph.tensor_names`), not on node inputs. Equality of declared and consumed is a builder property (team A). Alloy `check partitionConsumes` expected SAT (`B-EX-6`).
- P3 a key bound by two stages binds the same κ — **Implemented** (κ is a function of the key in the manifest). Alloy `check sharedKeySameKappa` expected UNSAT (`B-EX-7`).

### EX-03 `dispatch` (op collapse)
- Source: `crates/hologram-ai-common/src/lower/dispatch.rs:273`, `:277`, `:579–595`
- Header claim in that file: desugaring is exact. The transcribed arms are not injective.
- Definition of the relevant arms:
  - `Gelu | GeluApprox → OpKind::Gelu` (`:273`). Upstream `gelu_f` is the tanh approximation, so the erf form and the tanh form share a kernel.
  - `Softmax { axis } → OpKind::Softmax` (`:277`). The axis is dropped.
  - `Trilu | Identity → Identity` (`:582`). Comment: triangular zeroing folds at import when the operand is a constant; otherwise it is a structural relabel realized as Identity over the masked value. A runtime `Trilu` does not zero the triangle.
  - `KvSlotWrite | KvSlotRead → Identity` (`:585`). Comment: KV-cache injection does not run.
  - `Opaque { op_type } → Identity` (`:587–595`). Comment: an opaque marker is an import defect; a surviving one is relabeled as identity so the graph stays well-formed. `op_type` is discarded.
- P1 same kernel ⇒ same semantics — **Absent**. Alloy `check dispatchFaithful` expected SAT (`B-EX-8`).
- P2 "every desugaring exact" — **Marketing** for GeluApprox, Softmax-axis, Trilu, KvSlot, and Opaque. The importer conformance class IM is what the Opaque comment relies on; that class is a witness scenario (`structural_im.feature`), not a check inside `dispatch`.
