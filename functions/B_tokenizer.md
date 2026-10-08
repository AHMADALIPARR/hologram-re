<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# B_tokenizer — special-token resolution and the decode filter

Team B catalog. Source pin: hologram-ai @ `c9609c0`. Alloy: `alloy/B_tokenizer.als`. The BPE and unigram merge procedures are total functions of the vocabulary tables; they are not re-derived here. The Alloy model is the special-token fragment only.

---

### TK-01 `parse_special_tokens`
- Source: `crates/hologram-ai-tokenizer/src/native.rs:364–399`
- Signature: `parse_special_tokens : Json → Result<SpecialTokens, Error>`
- Definition: walk `added_tokens`. A content equal to `"</s>"` sets `eos_id`; `"<s>"` sets `bos_id`; `"<unk>"` and `"<pad>"` set those ids. Later entries with the same content overwrite earlier ones. If no `"</s>"` entry, `eos_id = 2` (`:394`).
- P1 the EOS used by generation is the model's declared EOS — **Absent** whenever the declared end token is not spelled `"</s>"` (`<|endoftext|>`, `<|im_end|>`, and the rest). `generate_stream` takes `cfg.eos` or `tokenizer.eos_token_id()` (`generate.rs:307`), and `eos_token_id` returns this field (`native.rs:340`). Alloy `check eosIsDeclared` expected SAT (`B-TK-1`).
- The unit test at `native.rs:579` pins the fallback: a fixture with no `"</s>"` reports eos 2, and `:633` shows id 2 spelling `"</s>"` only in that fixture.

### TK-02 `encode` / `decode`
- Source: `native.rs:311–338`
- `encode`: optional BOS, then `encode_raw`, then EOS if `add_eos`.
- `decode`: drop every id equal to `bos_id` (if any) or `eos_id`, then `decode_raw`.
- P1 decode never drops an ordinary vocabulary piece — **Absent** when the fallback eos id 2 is an ordinary piece. Generation also stops on that id (SA-04). Alloy `check decodeKeepsNormal` expected SAT (`B-TK-2`).
- P2 if `"</s>"` is an added token, decode keeps every ordinary piece — **Implemented** under the model fact that added ids are disjoint from ordinary ids. Alloy `check decodeKeepsNormalWithEndS` expected UNSAT (`B-TK-3`).
- Scenario `tokenizer_parity.feature` "encode matches the reference on a representative corpus" / "decode round-trips the corpus" is a corpus test, not a check of the fallback. Verdict on the corpus claim: **Asserted-only** until the step body is read against a pinned reference tokenizer (not done in this pass).

### TK-03 generation stop vs decode filter
- `generate_stream` stops when the sampled id equals `eos`, then decodes `generated`, which does not include that eos (`generate.rs` break before `generated.push`). The decode filter still matters for any eos/bos that arrived inside the prompt tokens or was pushed by `add_eos` on encode.
- P1 round-trip `decode(encode(t)) = t` — **Asserted-only**. False if `add_bos` or `add_eos` is set, and false if an ordinary piece collides with the fallback eos id.
