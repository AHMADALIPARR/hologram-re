<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# A_addressing — κ-labels, κ-store, κ-map, materialization

Team A, reverse-engineering catalog. Analyzed source: hologram-ai (MIT OR Apache-2.0), HEAD `c9609c0`, cloned read-only at `/workspace/hologram-ai-src`. Every `path:line` was checked with `rg -n` against that tree. Nothing here was executed against their Rust unless stated; verdicts come from reading.

Verdicts: **Implemented** (the code enforces it for every input in the stated domain) · **Asserted-only** (a test, scenario or doc asserts it, but the code does not enforce it in general, or the test exercises a stand-in) · **Marketing** (prose only, no mechanism and no test) · **Absent** (the mechanism does not exist, or the code does the opposite).

Arithmetic domain for this whole file: byte strings `B* = Seq(0..255)` and naturals. No f32/f64 appears in any function below (see `A_f32_inventory.md`: `address.rs` 0 uses, `materialize.rs` 0 uses).

Notation. `H32 : B* → B^32` is BLAKE3-256 (external, `hologram_host::HologramHasher`, substrate pin `18f553d8578997ce32e7b653786a0bcf9b09a2c0`). `S32 : B* → B^32` is SHA-256. `hex : B^32 → [0-9a-f]^64` lowercase. `Label = {"blake3:" ++ hex(d) | d ∈ B^32}`, so `|label| = 71`.

---

### AD-01 `kappa_of`
- Source: `crates/hologram-ai/src/materialize.rs:123`
- Signature: `kappa_of : B* → Label`
- Definition: `kappa_of(b) = "blake3:" ++ hex(H32(b))`. Total. No error path.
- Pre: none. Post: `|kappa_of(b)| = 71`, prefix `"blake3:"`.
- Properties
  - P1 deterministic (pure function of `b`) — **Implemented** — no state; test `materialize.rs:501`.
  - P2 equals BLAKE3 reference and `holospaces::address` on the 35 official KATs — **Implemented** — `features/s0_addressing/kappa_addressing.feature`, steps `crates/hologram-ai-conformance/tests/bdd.rs:877,897` (three-way compare: `kappa_of`, `holospaces::address`, `blake3::hash`). The KAT file is byte-identical to upstream BLAKE3 master (sha256 `dcb91ea8…f624`, `checks/logs/A_external_authorities-*.txt`).
  - P3 injective ("equality of κ is equality of content", `docs/conceptual-model/01-k-representation.md`) — **Absent** as a property of code; it is the BLAKE3 collision-resistance assumption, which no code can enforce. Alloy: `A_addressing.als` takes it as `fact kappaInjective` and every check that uses it is marked exactness/assumption-dependent.

### AD-02 `kat_input`
- Source: `crates/hologram-ai-conformance/tests/bdd.rs:873`
- Signature: `kat_input : ℕ → B*`; `kat_input(n) = [i mod 251 | i ∈ 0..n-1]`.
- Matches the generator described in the upstream BLAKE3 `test_vectors.json` comment. Total.
- P1 the test inputs are the official ones — **Implemented** (P2 of AD-01 would fail otherwise).

### AD-03 `chunked_kappa` (test model of incremental hashing)
- Source: `bdd.rs:931` (Given/When), `bdd.rs:954` (Then).
- Signature: `chunked_kappa : (b : B*, c : ℕ⁺) → Label`, `= "blake3:" ++ hex(fold(update, Hasher::new, chunks(b, c)))`, where `chunks` splits into `⌈|b|/c⌉` pieces of length `c` (last shorter). "whole" in the outline means `c = max(|b|, 1)`.
- Property: `∀ b c. chunked_kappa(b, c) = kappa_of(b)`.
  - As tested — **Implemented** for the `blake3` crate (`blake3::Hasher`), not for the product hasher.
  - As a product claim (browser `streamRun` feeds `KappaHasher` in arbitrary network slices, `apps/web/src/download.worker.ts:358`; `KappaHasher` at `crates/hologram-ai-wasm/src/lib.rs:498`) — **Asserted-only**: the product path wraps the same `blake3::Hasher`, so the property is inherited, but the scenario never drives the JS slicing code.

### AD-04 `DirKappaStore::insert`
- Source: `materialize.rs:83`
- Signature: `insert : (root : Path, b : B*) → Result<Label, IoError>`
- Definition: `k = kappa_of(b)`; `std::fs::write(root/(k ++ ".bin"), b)`; return `k`. Creates `root` if missing.
- Post: file `root/k.bin` has content `b` (if no I/O error).
- P1 idempotent overwrite with same bytes — **Implemented** (same path, same content).
- P2 atomic — **Absent**: `fs::write` truncates and writes; a crash leaves a short file under a valid name. Caught later only by AD-08 verification.

### AD-05 `DirKappaStore::resolve`
- Source: `materialize.rs:95`
- Signature: `resolve : (root : Path, k : String) → Result<B*, Error>`
- Definition: `read(root.join(k ++ ".bin"))`; on read error `Err("κ `{k}` not present in store")`.
- Pre (assumed, not checked): `k ∈ Label`. Not validated: `k` is any string from the archive κ-map.
- P1 returns bytes whose κ is `k` — **Absent** at this layer (no re-hash). The doc comment says verification happens in `materialize_archive`; true for AD-08, not for other callers (e.g. `quantized.rs:97`, which is itself uncompiled, see A_quant QU-12).
- P2 confined to `root` — **Absent**. `PathBuf::join` with an absolute `k` replaces `root`; `k` containing `../` walks out. Found by reading; not executed.

### AD-06 `DirKappaStore::invalidate`
- Source: `materialize.rs:100`
- Definition: `let _ = remove_file(root.join(k ++ ".bin"))`; errors ignored.
- P1 removes only store entries — **Absent**, same unvalidated join as AD-05. Reached from AD-08 when content fails verification, so an archive whose κ-map line names `../../x` and whose target `x.bin` does not hash to that string causes deletion of `x.bin` outside the store. Reading-only finding.

### AD-07 `KappaStore::resolve_range` (default) and `DirKappaStore::resolve_range`
- Source: default `materialize.rs:48`; dir store `materialize.rs:106`.
- Signature: `resolve_range : (k, off : u64, len : u64) → Result<B^len, Error>`
- Definition (default): `b = resolve(k)`; `start = off`, `end = off + len`; if `end > |b| ∨ start > end` then `Err`, else `b[start..end)`.
- Definition (dir): open, `seek(off)`, `read_exact(len)`; short read → `Err`.
- Edge: `off + len` is an unchecked `u64` add (wraps in release, panics in debug) — not reachable from a well-formed κ-map with small numbers, reachable from a crafted one.
- P1 never returns bytes outside `[off, off+len)` — **Implemented** modulo the overflow edge.

### AD-08 `patch_constants` (the content-verified resolution)
- Source: `materialize.rs:258` (verify block `:322–347`, range block `:349–365`).
- Signature: `patch_constants : (Archive, [KappaRequirement], Store, Verified : Set<Label>) → Result<Archive, Error>`
- Definition per requirement `r = (cid, k, range?)`:
  1. If `range = Some(o,l)` and `k ∈ Verified`: `bytes = store.resolve_range(k,o,l)`; slot/by-reference/empty checks are skipped (`:274–286`). (Session verified-set belongs to team B, see HANDOFF.)
  2. Else find constant slot `cid`; `Err` if missing ("slot drift", `:294`), if `by_reference` (`:302`), if non-empty ("refusing to overwrite", `:308`).
  3. `b = store.resolve(k)`; only if `k ∉ Verified`: if `kappa_of(b) ≠ k`: `store.invalidate(k)`, `b' = store.resolve(k)`; if `kappa_of(b') ≠ k` → `Err("κ integrity failure for ConstantId(n): store content hashes to `d`, expected `k`")`. On success insert `k` into `Verified`. If `k ∈ Verified` already (an earlier requirement in the same session), `b` is used without re-hashing: a second read of the same κ is trusted (time-of-check/time-of-use gap between the two reads).
  4. If `range = Some(o,l)`: require `o + l ≤ |b|`, take `b[o..o+l)`.
- Post (non-bypass path): every patched constant equals a slice of some `b` with `kappa_of(b) = k`.
- P1 "content is verified before use" — **Implemented** on the non-bypass path; test `materialize.rs:551`; scenario `content_verified_resolution.feature` (steps `bdd.rs:974–1048`). The scenario re-hashes in the test (`bdd.rs:990`), the product does it in step 3.
- P2 corrupt entry is evicted and re-resolved — **Implemented** (`:322–347`); but see AD-06 for the unvalidated path.
- P3 fail-closed naming the κ — **Implemented**; step `bdd.rs:1048` checks the error contains "integrity" and the κ.

### AD-09 `kappa_requirements` / `parse_kappa_map`
- Source: `materialize.rs:152`, `materialize.rs:169`; producer `crates/hologram-ai-common/src/lower/builder.rs:220–258`.
- Grammar (one line per external constant, `\n`-separated, UTF-8):
  `line ::= "ConstantId(" n ")" ":" k [ "@" off "+" len ]`, `n, off, len ∈ ℕ` decimal; `k` = everything between `:` and `@`/end.
- `kappa_requirements(a) = []` if the archive lacks extension `holospaces.kappa_map` (`KAPPA_MAP_EXTENSION`, `materialize.rs:22`), else `parse_kappa_map(ext)`.
- P1 round-trip `parse(emit(x)) = x` — **Implemented** for well-formed `k` (test `materialize.rs:534`).
- P2 `k` is a Label — **Absent**: neither producer nor parser validates; a κ containing `\n` or `@` (possible because the producer copies `AiParam::External.kappa` verbatim) changes the parse.

### AD-10 `materialize_archive` / `rebuild_archive` / `reassemble`
- Source: `materialize.rs:217`, `:229` (`_with`), `:373`, `:388`.
- Definition: if no requirements, return archive unchanged (test `:567`); else patch (AD-08) and reassemble: header 10 bytes (`4+2+2+2`), one 24-byte section entry per section (`1+7+8+8`), bodies, then a 32-byte footer `H32(all preceding bytes)`.
- P1 output footer is BLAKE3 of the body — **Implemented** (constant sizes from code; read only).

### AD-11 `ModelFormat::detect`
- Source: `crates/hologram-ai/src/address.rs:36`
- Signature: `detect : B* → Option<{Gguf, Json, Onnx}>`
- Definition: if `|b| ≥ 4 ∧ b[0..4] = "GGUF"` → Gguf; else let `c` = first byte not in ASCII whitespace; `c ∈ {'{','['}` → Json; any other `c` → Onnx; no such `c` → None.
- Edge: any non-JSON, non-GGUF garbage is classified Onnx (and then fails in the ONNX decoder).
- P1 matches the four unit tests `address.rs:146–171` — **Implemented**.

### AD-12 `model_kappa` / `model_kappa_label`
- Source: `address.rs:60`, `address.rs:76`
- Signature: `model_kappa : (Format, B*) → Result<AddressOutcome<71>>`; label = `"sha256:" ++ 64 hex` (test `address.rs:172`).
- Definition: delegates to `uor_addr::{onnx,gguf,json}::address` (crate `uor-addr = "0.2"`, `crates/hologram-ai/Cargo.toml:58`). The canonicalization is inside uor-addr and was not re-derived here.
- P1 byte-identical to uor-addr's own κ for pinned corpus models — **Asserted-only (opt-in)**: `crates/hologram-ai/tests/ma_external_models.rs`, only with `HOLOGRAM_AI_LIVE=1`; values copied from uor-addr 0.2.0. Not run by team A.

### AD-13 `component_kappa`, `compose_model`, `compose_models`
- Source: `address.rs:97`, `:125`, `:133`
- `component_kappa(b)` = uor-addr BLAKE3-axis label of `b`.
- `compose_model(ps) = hologram_archive::compose_model(sort_by(as_bytes, ps))`.
- P1 order independence of the composite — **Implemented** by the sort (the doc comment itself notes the underlying fold over 3+ operands is order-sensitive). Alloy: `A_addressing.als` `check composeOrderFree`.

### AD-14 `ConstantDeduplication::run`
- Source: `crates/hologram-ai-common/src/opt/const_dedup.rs:29`
- Definition: over constant tensors with `|data| ≥ 256` (smaller skipped, `:58`), in sorted tensor-id order (`:49`), key `= (holospaces::address(data), dtype, shape)` (`:44,:62`); the first tid per key survives, later uses are rewired to it.
- P1 merges only byte-equal tensors — **Asserted-only** (collision-resistance assumption; bytes are never compared). Tests `:158,:195,:215,:244`.
- P2 "uor-addr fingerprint" (doc comment) — **Absent**: the key is the holospaces BLAKE3 label, not uor-addr.

### AD-15 store-level claims from the feature/docs, as functions
- "Storage dedup is identity" (`01-k-representation.md`): `insert(b1) = insert(b2) ⇔ b1 = b2` — holds iff AD-01 P3 holds — **Asserted-only** (assumption).
- "Resolution only returns verified content" (dictionary row `content-verified-resolution`) — true for `materialize_archive`, false for `DirKappaStore::resolve` — **Implemented** (materialize path) / **Absent** (store path). Alloy: `check materializeReturnsVerified` (UNSAT) and `run gap_storeResolveUnverified` (SAT).
