<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# A_archivum — the "provenance ledger"

Team A catalog. Analyzed source: hologram-ai (MIT OR Apache-2.0), HEAD `c9609c0`, read-only. The crate is `crates/hologram-archivum/src/lib.rs`, 59 lines, with no tests. Verdicts follow `A_addressing.md`.

Exact domain: strings and bytes. There are no floats (0 f32/f64 uses).

Notation: `json(x)` is the `serde_json::to_string` output. Fields are serialized in struct declaration order with no whitespace. `S32` is SHA-256 and `hex` is lowercase.

---

### AR-01 `ArchivumLogger::new`
- Source: `crates/hologram-archivum/src/lib.rs:26`
- `new(path) = {log_path: path}`. No I/O happens here.

### AR-02 `ArchivumLogger::log_event`
- Source: `lib.rs:32`
- Signature: `(event_type, domain, payload : String) → Result<UnifiedWitness, String>`. This is an effect on a file, and it reads the wall clock.
- Definition:
  1. `e = {timestamp: Utc::now().to_rfc3339(), event_type, domain, payload}`.
  2. `h = hex(S32(json(e)))`.
  3. `w = {hash: h, event: e}`.
  4. If `open(log_path, create|append)` succeeds, `let _ = writeln!(file, json(w))`. Both a failed open and a failed write are ignored.
  5. Return `Ok(w)`.
- The function returns `Err` only if serde fails. That cannot happen for these all-String structs.
- Post: `w.hash = hex(S32(json(w.event)))`. The record may or may not be on disk.
- Ledger as a formal object: `L = [w₁, w₂, …]`, the lines of the file. There is no link between `wᵢ` and `wᵢ₊₁`.

Properties (README `:19`, `:31`; ADR-001 `:21–24`, `:40`):
- P1 each record's hash covers its event — **Implemented**. One SHA-256 per record, and it can be recomputed.
- P2 "immutable" ledger (README:31, ADR-001:23) — **Marketing**. `O_APPEND` only affects where this process writes. Any writer can truncate, edit, delete or reorder lines, and recomputing each line's own hash still validates.
- P3 "cryptographic chain of custody … enforced inherently" (ADR-001:40) — **Absent**:
  - there is no previous-hash field and no Merkle structure
  - there is no signature or key, and no external anchor
  - there is no read or verify API
  - Alloy: `A_archivum.als` `run gap_tamperUndetected` (SAT) shows that deleting a record leaves every remaining record self-consistent. `check chainWouldDetectDeletion` (UNSAT) shows a prev-hash chain would detect it, so the gap is in the design, not in the model.
- P4 "every inference event" is logged (README:31) — **Asserted-only**. Callers in `apps/hologram-api/src/main.rs` (`:42, :122, :139, :148, :151, :156`) discard the result with `let _ =`, and the logger swallows I/O errors. A full disk or an unwritable path drops events silently.
- P5 "absolute legal provenance" (README:31) — **Marketing**. Nothing here identifies who wrote a record or binds it to a time source beyond the local clock.
- P6 deterministic hash for the same event — **Absent** by design. The timestamp is part of the hashed event, so two identical calls give different hashes.
- P7 records are whole lines under concurrency — **Asserted-only**. The file is unbuffered, and `writeln!` may issue more than one `write` for the record and its newline. Two writers could interleave. This was found by reading and not tested.

### AR-03 Relation to "κ-provenance" (ADR-001:22)
- ADR-001 says "Hologram-AI already has perfect internal κ-provenance (`AiEvent` sequence)".
- The `AiEvent` re-exported from `hologram_ai_core` (`crates/hologram-ai/src/lib.rs:34`) is a different type from `hologram_archivum::AiEvent`. The archivum event carries free-text `payload` strings, not κ-labels.
- Verdict: **Marketing**. Archivum records no κ, and no code links an archivum record to an archive κ.
