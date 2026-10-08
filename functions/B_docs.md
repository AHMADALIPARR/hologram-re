<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# B_docs — claims in the B surface, and the verdict

Team B catalog. Source pin: hologram-ai @ `c9609c0`. Prose claims below are the ones the function notes already contradicted or confirmed. This is not a full pass over `docs/`.

| Claim | Where it appears | Verdict | Function |
|---|---|---|---|
| Desugaring is exact | `dispatch.rs` header, architecture §5.2 comment | Absent for GeluApprox, Softmax axis, Trilu, KvSlot, Opaque | EX-03 |
| KV-cache is removed; reuse is content-addressed | `dispatch.rs:584` | Implemented as a relabel to Identity; elision does not replace a KV cache on a single `input_ids` input | EL-04 |
| Served window is at least the request | `SessionProvider` doc, `engine.rs:114` | Implemented for `GrowableStagedSession`; Absent for `GrowableSession` past `max_window` | SA-02, SA-03 |
| Geometric buckets, capped at the model's context | `engine.rs:39–44` | Implemented | SA-01 |
| Temperature 0.0 policy, including per domain | CNL README / ADR-001 prose | Marketing | CN-01 P3–P4 |
| Generation is gated by the CNL invariants | `apps/hologram-api` log lines | Asserted-only | the gate blocks only `"all"`; the allowed branch does not call a model (CN-02) |
| Event order decides the terminal state | `app_domain_events.feature` | Asserted-only | SE-01 P2 |
| Session trim continues rather than dead-ending | `session_window.feature`, `Chat.tsx:262` | Asserted-only | SE-03 P3; an oversized pending message still fails in the engine |
| Recorded peak residency bounds live weight | `stage_residency_cache` / staged execution prose | Absent | EL-01 P2 |
| A κ verified once in a session stays the same bytes | `session_verified_kappa.feature` | Absent (stated as a feature) | EL-02 P2 |
| Honesty audit means the cited authority was consulted | model crate docs | Absent | CF-01 P3 |
