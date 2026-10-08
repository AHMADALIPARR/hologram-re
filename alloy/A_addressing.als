-- SPDX-License-Identifier: AGPL-3.0-only
-- Team A model: κ-labels, κ-store, κ-map keys, verified materialization.
-- Analyzed source: hologram-ai @ c9609c0 (MIT OR Apache-2.0).
-- Catalog: functions/A_addressing.md (AD-01, AD-04..AD-08, AD-13, AD-15).
-- Alloy checks THIS MODEL, not the Rust. Every fact below is a reading of the
-- code; a wrong reading makes the result wrong. BLAKE3 collision resistance is
-- an ASSUMPTION (pred kappaInjective), never a fact: assertions that need it
-- say so in their antecedent.
module A_addressing

open util/ordering[Label] as LO

sig Blob {}
sig Label {}
-- AD-01 kappa_of: a total function Blob -> Label
one sig K { kappa: Blob -> one Label }

pred kappaInjective { all disj a, b: Blob | K.kappa[a] != K.kappa[b] }

-- A κ-map key (AD-09): the text between ':' and '@'. Not validated by the code.
abstract sig Key {}
sig LabelKey extends Key { lab: one Label }   -- a well-formed "blake3:<64 hex>"
sig Traversal extends Key {}                  -- e.g. "../../x" or "/abs/x"

abstract sig Loc {}
sig InStore extends Loc {}
sig Outside extends Loc {}

-- AD-05: root.join(k ++ ".bin")
one sig Join { at: Key -> one Loc }
fact joinShape {
  all k: LabelKey | Join.at[k] in InStore
  all k: Traversal | Join.at[k] in Outside
  all k1, k2: LabelKey | Join.at[k1] = Join.at[k2] iff k1.lab = k2.lab
}

sig FS { content: Loc -> lone Blob }

-- AD-05 DirKappaStore::resolve: read the joined file; no re-hash
pred resolve[fs: FS, k: Key, b: Blob] { fs.content[Join.at[k]] = b }

-- AD-08 non-bypass path: accept only content that hashes to the key
pred verifiedRead[fs: FS, k: LabelKey, b: Blob] {
  resolve[fs, k, b]
  K.kappa[b] = k.lab
}

-- AD-06 invalidate: remove the joined location, nothing else changes
pred invalidate[fs, fs2: FS, k: Key] {
  no fs2.content[Join.at[k]]
  all l: Loc - Join.at[k] | fs2.content[l] = fs.content[l]
}

-- AD-08 mismatch branch. A Traversal key is never a label, so its content
-- can never hash to it: the mismatch branch is always taken.
pred mismatchEvicts[fs, fs2: FS, k: Key, b: Blob] {
  resolve[fs, k, b]
  k in LabelKey implies K.kappa[b] != k.lab
  invalidate[fs, fs2, k]
}

-- AD-13 compose_model sorts its parts first; the composite is a function of
-- the sorted sequence. Lemma: two sorted sequences with equal multiplicities
-- are equal, so input order cannot matter.
sig Parts { s: seq Label }
pred sorted[q: seq Label] {
  all i: q.inds - q.lastIdx | LO/lte[q[i], q[plus[i, 1]]]
}
pred sameMultiset[a, b: seq Label] { all l: Label | #(a.l) = #(b.l) }

---------------------------------------------------------------- checks
-- AD-08 P1: a verified read returns the unique blob with that label
-- (needs the injectivity assumption).
assert materializeReturnsVerified {
  all fs: FS, k: LabelKey, b, b2: Blob |
    (kappaInjective and verifiedRead[fs, k, b] and K.kappa[b2] = k.lab) implies b = b2
}
check materializeReturnsVerified for 4

-- AD-06 fix witness: if every key were a well-formed label, eviction could
-- never touch a location outside the store.
assert validatedKeysStayInside {
  all fs, fs2: FS, k: LabelKey, b: Blob |
    mismatchEvicts[fs, fs2, k, b] implies (all o: Outside | fs2.content[o] = fs.content[o])
}
check validatedKeysStayInside for 4

-- AD-15 / 01-k-representation "equality of κ is equality of content",
-- under the assumption.
assert dedupIsIdentity {
  kappaInjective implies (all a, b: Blob | K.kappa[a] = K.kappa[b] iff a = b)
}
check dedupIsIdentity for 5

-- AD-13 P1
assert composeOrderFree {
  all p1, p2: Parts |
    (sorted[p1.s] and sorted[p2.s] and sameMultiset[p1.s, p2.s]) implies p1.s = p2.s
}
check composeOrderFree for 4 but 4 seq, 5 Int

---------------------------------------------------------------- runs
-- non-vacuity: a verified read exists
run someVerifiedRead { some fs: FS, k: LabelKey, b: Blob | verifiedRead[fs, k, b] } for 3
-- non-vacuity: two different orderings of the same parts sort to one sequence
run permutedPartsExist {
  some disj p1, p2: Parts, p3: Parts |
    #p1.s = 3 and p1.s != p2.s and sameMultiset[p1.s, p2.s] and sorted[p3.s]
    and sameMultiset[p3.s, p1.s]
} for 4 but 4 seq, 5 Int
-- GAP AD-05 P1: the store primitive returns content that does not hash to its key
run gap_storeResolveUnverified {
  some fs: FS, k: LabelKey, b: Blob | resolve[fs, k, b] and K.kappa[b] != k.lab
} for 3
-- GAP AD-06 P1: an unvalidated κ-map key deletes a file outside the store
run gap_traversalDeletesOutside {
  some fs, fs2: FS, k: Traversal, b: Blob |
    mismatchEvicts[fs, fs2, k, b] and some fs.content[Join.at[k]]
} for 3
-- GAP AD-08: a κ verified once in the session is trusted on a later read
-- (time-of-check / time-of-use between two reads)
run gap_secondReadTrusted {
  some fs1, fs2: FS, k: LabelKey, b1, b2: Blob |
    verifiedRead[fs1, k, b1] and resolve[fs2, k, b2] and K.kappa[b2] != k.lab
} for 3
-- GAP AD-01 P3: without the assumption, two contents can share a κ
run gap_dedupWithoutInjectivity { some disj a, b: Blob | K.kappa[a] = K.kappa[b] } for 3
