// Copyright (c) 2026 SNAPKITTYAGENT9NOVA
// SPDX-License-Identifier: AGPL-3.0-only
//! Standalone streaming κ-hasher, extracted from the hologram-ai browser pipeline.
//!
//! Provenance: `KappaHasher` at `crates/hologram-ai-wasm/src/lib.rs:498-524`
//! of SNAPKITTYAGENT9NOVA/hologram-ai — the `#[wasm_bindgen]` streaming
//! BLAKE3 hasher the web app's `download.worker.ts` (`streamRun`) feeds in
//! arbitrary network slices, one fresh hasher per tensor, comparing each
//! `finalize()` label against the manifest's expected κ. Extraction is
//! authorized under the user's 2026-10-07 per-source waiver for
//! SNAPKITTYAGENT9NOVA/hologram-ai (waiver noted in the oracle README).
//! The logic below is the original's, minus the `wasm_bindgen` glue.
//!
//! Purpose: independent oracle for `functions/A_addressing.md` AD-03
//! (`chunked_kappa`) in AHMADALIPARR/hologram-re. The catalog asserts
//! `∀ b c. chunked_kappa(b, c) = kappa_of(b)` — chunked/incremental hashing
//! equals whole-input hashing — but marks it **Asserted-only**: the product
//! path wraps the same `blake3::Hasher`, so the property is inherited, yet
//! no scenario ever drives the chunking code. This crate replays the
//! browser's exact feeding pattern (arbitrary slice sizes, per-tensor
//! hasher reset) against the real `blake3` crate — pinned to the same 1.5.5
//! the product locks — and checks the property across adversarial chunkings.

/// Label prefix used by the product: `"blake3:" ++ hex(digest)`.
pub const KAPPA_PREFIX: &str = "blake3:";

/// Streaming κ-hasher — the original `KappaHasher` API surface:
/// `new`, `update`, `finalize`.
#[derive(Clone, Debug, Default)]
pub struct KappaHasher {
    hasher: blake3::Hasher,
}

impl KappaHasher {
    /// Fresh hasher. Mirrors `KappaHasher::new()`; the worker constructs one
    /// per tensor (`hasher = new KappaHasher()` after each `finalizeTensor`).
    pub fn new() -> Self {
        Self {
            hasher: blake3::Hasher::new(),
        }
    }

    /// Feed the next slice. Mirrors `update(&mut self, bytes: &[u8])` — the
    /// worker calls this once per network read, with whatever size the
    /// fetch reader happened to yield.
    pub fn update(&mut self, bytes: &[u8]) {
        self.hasher.update(bytes);
    }

    /// Final digest label. Mirrors `finalize(self) -> String`:
    /// `format!("blake3:{}", hash.to_hex())`.
    pub fn finalize(self) -> String {
        let hash = self.hasher.finalize();
        format!("{KAPPA_PREFIX}{}", hash.to_hex())
    }
}

/// Whole-input κ label: `kappa_of(b) = "blake3:" ++ hex(BLAKE3(b))`
/// (catalog AD-01; the worker compares each streamed digest against this).
pub fn kappa_of(bytes: &[u8]) -> String {
    format!("{KAPPA_PREFIX}{}", blake3::hash(bytes).to_hex())
}

/// Feed `bytes` through a fresh [`KappaHasher`] in the given chunk sizes —
/// the test-side model of the browser's network-slice feeding. `chunks`
/// must partition the input exactly (a shortfall panics: a partition that
/// silently dropped bytes would make the property check vacuous); surplus
/// chunk sizes past the end are ignored.
pub fn chunked_kappa(bytes: &[u8], chunks: &[usize]) -> String {
    let mut h = KappaHasher::new();
    let mut pos = 0;
    for &c in chunks {
        if pos >= bytes.len() {
            break;
        }
        let end = (pos + c).min(bytes.len());
        h.update(&bytes[pos..end]);
        pos = end;
    }
    assert_eq!(
        pos,
        bytes.len(),
        "chunked_kappa: chunk sizes {chunks:?} cover only {pos} of {} bytes",
        bytes.len()
    );
    h.finalize()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Tiny deterministic PRNG (xorshift64*) so the chunking fuzz is
    /// reproducible with no extra dependencies.
    struct Rng(u64);
    impl Rng {
        fn next(&mut self) -> u64 {
            let mut x = self.0;
            x ^= x >> 12;
            x ^= x << 25;
            x ^= x >> 27;
            self.0 = x;
            x.wrapping_mul(0x2545_F491_4F6C_DD1D)
        }
        fn below(&mut self, n: u64) -> u64 {
            self.next() % n
        }
    }

    fn pseudo_random_bytes(rng: &mut Rng, len: usize) -> Vec<u8> {
        (0..len).map(|_| rng.below(256) as u8).collect()
    }

    #[test]
    fn label_format_matches_catalog_ad01() {
        // AD-01 postcondition: |kappa_of(b)| = 71, prefix "blake3:".
        for len in [0, 1, 63, 64, 65, 1024] {
            let label = kappa_of(&vec![0xA5; len]);
            assert!(label.starts_with(KAPPA_PREFIX), "{label}");
            assert_eq!(label.len(), 71, "{label}");
            assert!(
                label[KAPPA_PREFIX.len()..].chars().all(|c| c.is_ascii_hexdigit()),
                "{label}"
            );
        }
    }

    #[test]
    fn chunked_equals_whole_across_adversarial_chunkings() {
        // AD-03: ∀ b c. chunked_kappa(b, c) = kappa_of(b).
        // Lengths straddle BLAKE3's 1024-byte chunk and 64-byte block edges;
        // chunkings include 1-byte slices (the worker's worst case), random
        // network-style slices, exact-chunk feeds, and single whole feeds.
        let mut rng = Rng(0xC0FFEE);
        let lens = [
            0usize, 1, 2, 63, 64, 65, 127, 128, 1023, 1024, 1025, 2048, 2049, 5000,
            65536,
        ];
        for &len in &lens {
            let bytes = pseudo_random_bytes(&mut rng, len);
            let whole = kappa_of(&bytes);
            for trial in 0..8 {
                let mut chunks = Vec::new();
                let mut remaining = len;
                while remaining > 0 {
                    let c = match trial % 4 {
                        0 => 1,                                     // 1-byte slices
                        1 => (rng.below(3 * 1024 + 1) + 1) as usize, // random ≤ 3 KiB
                        2 => 1024,                                  // BLAKE3 chunk size
                        _ => remaining,                             // whole remainder
                    };
                    let take = c.min(remaining);
                    chunks.push(take);
                    remaining -= take;
                }
                assert_eq!(
                    chunked_kappa(&bytes, &chunks),
                    whole,
                    "len={len} trial={trial} chunks={chunks:?}"
                );
            }
        }
    }

    #[test]
    fn empty_updates_do_not_perturb_digest() {
        let mut h = KappaHasher::new();
        h.update(b"");
        h.update(b"abc");
        h.update(b"");
        assert_eq!(h.finalize(), kappa_of(b"abc"));
    }

    #[test]
    fn per_tensor_hasher_reset_matches_oneshot() {
        // The worker news up a KappaHasher per tensor; tensors hashed
        // separately must equal their one-shot labels.
        let t1 = b"tensor-zero-payload";
        let t2 = b"tensor-one-payload-longer";
        let mut h1 = KappaHasher::new();
        h1.update(t1);
        let mut h2 = KappaHasher::new();
        h2.update(&t2[..7]);
        h2.update(&t2[7..]);
        assert_eq!(h1.finalize(), kappa_of(t1));
        assert_eq!(h2.finalize(), kappa_of(t2));
    }

    /// Official BLAKE3 test vectors. Inputs follow the KAT generator rule
    /// (`input[i] = i % 251`, confirmed in the vendored `blake3-1.5.5`
    /// `src/test.rs` `paint_test_input`). Expected hashes are the first 32
    /// bytes of the KAT `hash` field, read from
    /// `hologram-ai-source/oracles/blake3/test_vectors.json` — whose sha256
    /// (`dcb91ea8…f624`) matches the repo's own verification log
    /// (`checks/logs/A_external_authorities-*.txt`: byte-identical to
    /// BLAKE3-team/BLAKE3 master). Not recalled; copied and machine-checked.
    fn kat_input(len: usize) -> Vec<u8> {
        (0..len).map(|i| (i % 251) as u8).collect()
    }

    #[test]
    fn known_answer_vectors() {
        let cases: &[(usize, &str)] = &[
            (0, "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"),
            (1, "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213"),
            (1023, "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11"),
            (1024, "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7"),
            (102400, "bc3e3d41a1146b069abffad3c0d44860cf664390afce4d9661f7902e7943e085"),
        ];
        for &(len, expected_hex) in cases {
            assert_eq!(expected_hex.len(), 64, "vector typo: len={len}");
            let label = kappa_of(&kat_input(len));
            assert_eq!(label, format!("{KAPPA_PREFIX}{expected_hex}"), "len={len}");
        }
    }
}
