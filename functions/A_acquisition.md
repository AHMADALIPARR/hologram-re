<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# A_acquisition — Hub resolution, native downloader, browser streamed download

Team A catalog. Analyzed source: hologram-ai (MIT OR Apache-2.0), HEAD `c9609c0`, read-only. Verdicts follow `A_addressing.md`.

Exact domains: strings, bytes, ℕ (byte offsets and HTTP status codes). Floats appear only in `format_size` and in browser progress text; see `A_f32_inventory.md`.

External authority: the Hugging Face Hub API (oracle `hf-hub`). Its responses below come from real GETs on 2026-10-07 (PT), logged in `checks/logs/A_external_authorities-*.txt`.

There are two acquisition paths and they are different code:
- **Native:** `crates/hologram-ai/src/download/`, the `hologram-ai download` CLI. Compiled only with feature `native` (`crates/hologram-ai/src/lib.rs:14`).
- **Browser:** `apps/web/src/download.worker.ts`. Safetensors only (`:535–546`).

The Rust BDD scenario `hf_model_resolution.feature` exercises neither path. It uses a test-local function, AQ-12.

---

## Native path

### AQ-01 `resolve_format`
- Source: `crates/hologram-ai/src/download/mod.rs:56`
- Signature: `(ModelInfo, DownloadFormat ∈ {Onnx, Auto}, quant : Option<String>) → ResolvedDownload`
- Definition:
  - If any sibling name ends in `.onnx`, return `Onnx{all such names}`.
  - Else, if any sibling name ends in `.safetensors`, return `Safetensors{all such names}`.
  - Otherwise **panic** with `"No ONNX or Safetensors files found in the repository."` (`:68`).
- The `format` argument has no effect, because `Onnx` and `Auto` take the same branch. `_quantization` is ignored.
- P1 "fails loud" — **Implemented**, but as a panic rather than an `Err` (tests `mod.rs:311,318` expect the panic).
- P2 a quantization selection is honored — **Absent**. Every `.onnx` variant in the repo is downloaded.

### AQ-02 `run_async`
- Source: `mod.rs:115`
- Definition:
  - `info = model_info(id)` (AQ-05).
  - `out = args.output` or `models/<last '/'-segment of id>`.
  - `resolve_format`, then `download_onnx` for **both** result variants (`:136–163`), then `print_summary`.
- Edge: model info always comes from the default branch. File downloads use `args.revision` (AQ-06), so the manifest and the bytes can come from different revisions.

### AQ-03 `download_onnx` / `download_companions`
- Source: `mod.rs:168`, `mod.rs:208`; `COMPANION_FILES` at `mod.rs:8` = `tokenizer.json, config.json, tokenizer_config.json, special_tokens_map.json`.
- Definition:
  - For each resolved file, call `download_file`, then `verify_checksum(sha256)` **only if** `sibling.lfs` is present (`:187`).
  - Then download every `*.onnx_data` / `*.onnx.data` sibling, with no checksum.
  - Then download each companion whose exact root name is a sibling, with no checksum.
- P1 downloaded weights are integrity-checked against the Hub's LFS sha256 — **Absent in practice**. `model_info` requests `/api/models/{id}` without `?blobs=true`. The live response has no `lfs` field on any sibling. The first sibling is `{"rfilename":".gitattributes"}`, and with `?blobs=true` the same sibling carries `size`. So the checksum branch is never reached.
- P2 companions include `generation_config.json` (`docs/conceptual-model/02-user-journey.md` lists config, tokenizer, tokenizer_config, generation_config) — **Absent**. The native list has no `generation_config.json` and adds `special_tokens_map.json`.

### AQ-04 `verify_checksum`
- Source: `mod.rs:232`
- Definition: `S32(file)` as lowercase hex, compared with `expected`; mismatch returns `Err("Checksum mismatch …")`.
- P1 — **Implemented** as a function. Its only call site is unreachable in practice (AQ-03 P1).

### AQ-05 `HfClient::model_info`
- Source: `crates/hologram-ai/src/download/hf_api.rs:54`
- Definition: `GET https://huggingface.co/api/models/{id}` (bearer token if set). Status handling:
  - `401 | 403` → `Err("This model requires authentication. Use --token or set HF_TOKEN env var.")`
  - `404` → `Err("Model not found: {id}")`
  - `≥ 400` → `Err("HuggingFace API error: HTTP {s}")`
  - otherwise the JSON body
- Live fact: the Hub answered **401** for `hologram-ai/this-repo-does-not-exist`, so an unknown repo produces the authentication message, which does not contain the repo id.
- P1 "resolution fails naming the repository" (scenario in `hf_model_resolution.feature`) — **Absent** in the product. It holds only for the test-local AQ-12, whose message embeds the repo.

### AQ-06 `HfClient::download_file` / `download_file_once`
- Source: `hf_api.rs:74`, `hf_api.rs:103`
- Definition:
  - URL `https://huggingface.co/{id}/resolve/{revision}/{filename}`.
  - `error_for_status`, `create(dest)`, stream chunks to the file, flush.
  - Up to 3 attempts. The sleep before attempt `a+1` is `2^a` seconds, i.e. 2 s and 4 s (`Duration::from_secs(1 << attempts)`).
- Not checked: the byte count against `Content-Length` or `sibling.size`.
- A failed final attempt leaves a partial file at `dest`.
- P1 "with retry" (`02-user-journey.md`) — **Implemented** (3 attempts).
- P2 "No stage publishes partial state" (`02-user-journey.md`) — **Absent** on this path. It writes in place, not through a temp file and rename.

### AQ-07 `format_size`
- Source: `mod.rs:264`; constants `KB = 1024`, `MB = 1024²`, `GB = 1024³`.
- Exact definition: for `b ≥ GB`, the decimal rendering of `b/2^30` rounded to 1 place, with ties to even on the exact rational. MB and KB work the same way; values below 1 KiB print as `"{b} B"`.
- `approx_format_size`:
  - (a) `mod.rs:268–275`.
  - (b) `b as f64` is exact for `b < 2^53`. Division by `2^k` is exact. Rust's `{:.1}` rounds the exact binary value.
  - (c) `|approx − exact| = 0` for `b < 2^53`.
  - (d) Above `2^53` the first conversion rounds. This is display only.

### AQ-08 `safetensors_stream.rs` — not compiled
- Source: `crates/hologram-ai/src/download/safetensors_stream.rs` (8 lines). No `mod safetensors_stream` exists anywhere (`rg`). Dead file.

## Browser path

### AQ-09 `fetchShardManifest`
- Source: `apps/web/src/download.worker.ts:119`
- Definition:
  - `n = le_u64(range 0–7)` as a JS Number. Reject unless `Number.isSafeInteger(n) ∧ n ≠ 0`.
  - `header = JSON.parse(range 8 .. 8+n−1)`.
  - Tensors are all entries except `__metadata__`, sorted by `data_offsets[0]`.
  - `etag` comes from the response: `x-linked-etag`, or else `etag`.
- Not checked: dtype, shape, `begin ≤ end`, overlap, `Π shape · size(dtype) = end − begin`.
- P1 header parsing per the safetensors spec — **Asserted-only** (same gap as A_safetensors ST-02). Malformed offsets lead to a wrong κ, but that κ is caught at materialization (A_addressing AD-08), not here.

### AQ-10 `streamRun` (incremental κ, one tensor in memory)
- Source: `download.worker.ts:358` (run loop at `:425–439`)
- Exact definition: for the tensors `t_from .. t_{to−1}` (contiguous unknowns), with `abs(t) = [8+n+begin, 8+n+end)`:
  - issue one ranged GET over the union
  - feed exactly the bytes of `abs(t)` into a fresh `KappaHasher` (`crates/hologram-ai-wasm/src/lib.rs:498`, which wraps `blake3::Hasher`; `finalize` = `"blake3:" ++ hex`)
  - buffer the same bytes, then call `finalizeTensor(t, κ, buffer)`
  - a `200` response (Range ignored) is handled by skipping the prefix
- Post: `κ(t) = kappa_of(bytes(abs(t)))` for non-overlapping, ordered offsets.
- P1 "incremental κ equals one-shot κ" — **Implemented** by inheritance from `blake3::Hasher` (A_addressing AD-03).
- P2 "peak memory is one tensor" (`docs/architecture/ARCHITECTURE.md:96–99`) — **Implemented** for the stream buffer: one tensor buffer plus one network chunk. Header JSON and manifests are extra.
- P3 for overlapping offsets, the cached bytes hash to the recorded κ — **Absent**. Bytes already consumed are not re-fed, so the hasher sees a suffix while the buffer has a zero tail. Materialization catches the mismatch.

### AQ-11 `finalizeTensor`, `writeEssential`, the network-skip prior
- Source: `download.worker.ts:319` (`finalizeTensor`), `:179` (`writeEssential`), `:144` (`pinFileName`), `:148/:160` (prior load/save), skip loop at `:425–439`.
- `finalizeTensor`:
  - records `kappaSources[κ] = {url, absolute range}` and `prior["begin-end"] = κ`
  - writes `tensors/κ.bin` only while `cached + size ≤ budget`
  - on the first refused write, sets `budget = 0` and continues
- `writeEssential`: retries a write after evicting cached `κ.bin` files, LIFO, until success or until nothing is left to evict.
- Skip: if the shard's ETag has a saved prior, a tensor whose exact `begin-end` key is in the prior is finalized with the recorded κ and no bytes are fetched.
- `pinFileName(etag)` strips characters outside `[A-Za-z0-9._-]`, so distinct ETags can map to one file. A collision is caught later, since κs are verified at materialization.
- P1 "known content never re-transits" (network-skip) — **Implemented** for exact range-key matches under the same ETag.
- P2 "never refused for resources" (memory-guard) — **Implemented** as written: caching stops, the download continues.
- P3 provenance URLs are immutable ("Revision-pinned URLs", `:240`) — **Asserted-only**. The default `rev` is `"main"`, which is a moving ref.

### AQ-12 `resolve_manifest` (bdd.rs, test-local)
- Source: `crates/hologram-ai-conformance/tests/bdd.rs:1067`; `COMPANIONS` at `bdd.rs:1065` = `config.json, tokenizer.json, generation_config.json`.
- Definition:
  - `GET /api/models/{repo}`. A non-2xx status gives `Err("resolving `{repo}` via the Hub API failed: HTTP s")`.
  - Otherwise return the list of `rfilename`s, failing if it is empty.
- This is not product code. Its companion list differs from both AQ-03 and `02-user-journey.md`.

### AQ-13 `fetch_authoritative_metadata_at` (test helper)
- Source: `crates/hologram-ai-conformance/tests/fetch_helper.rs:39`
- Definition: ranged-fetch the header of the named shard and parse it with ST-02. Each returned κ is **`format!("blake3:{}", entry.name)`** (`:133`), i.e. the tensor *name*, not a hash of content. `weight_bytes_fetched` counts bytes read past `8 + header_len` (`:115,:129`).
- Consequence: the `streamed_weightless_compile` and family-registry checks that "the kappa_map names every manifest weight tensor exactly once" (`bdd.rs:1670`) run with name-unique stand-in κs. With content κs, two byte-identical tensors share one κ, so "exactly once per tensor" cannot hold. Alloy: `A_compilation.als` `run gap_dupContentBreaksExactlyOnce`.
