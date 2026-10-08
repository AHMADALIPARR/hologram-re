<!--
  Copyright (C) 2026 hologram-re contributors
  SPDX-License-Identifier: AGPL-3.0-only
-->

# hologram-re

A reverse-engineering analysis of
[SNAPKITTYAGENT9NOVA/hologram-ai](https://github.com/SNAPKITTYAGENT9NOVA/hologram-ai)
at commit `c9609c0`. The upstream project is a Rust workspace (about 50,000
lines, licensed MIT OR Apache-2.0) that downloads Hugging Face models,
compiles them into content-addressed `.holo` archives, runs inference natively
and in WebAssembly, gates requests through a policy check, and logs runs to a
hash-chained ledger. Nothing from upstream is copied here; this repository holds
only analysis.

**Status: work in progress.** Files are added as the analysis lands.

## Method

1. Every mathematical operation and every claimed property in the Rust crates
   is written out as a full function: signature, exact definition, constants
   taken from the code, preconditions, postconditions, and the upstream
   `path:line` it comes from.
2. Every Gherkin scenario under `features/` and every claim in the upstream
   docs and `model/*.toml` is written the same way, as a formal predicate, and
   traced to the step code that is supposed to check it.
3. Functions are defined without `f32`/`f64`, using exact integers, exact
   rationals, or the Goldilocks field $p = 2^{64} - 2^{32} + 1$. Each
   floating-point code path upstream is recorded as an approximation of the
   exact function, with its rounding steps and where it breaks a parity or
   determinism claim.
4. Structural invariants are modeled in Alloy 6. A `check` with no
   counterexample means the property holds in the model, not in the Rust.

Each property gets one verdict:

| Verdict | Meaning |
|---|---|
| Implemented | The code enforces it for every input in the stated domain. |
| Asserted-only | A test, scenario, or doc asserts it, but the code does not enforce it in general. |
| Marketing | Prose only, with no mechanism and no test. |
| Absent | The mechanism does not exist, or the code does the opposite. |

## Layout

| Path | Contents |
|---|---|
| `functions/A_*.md` | Addressing (BLAKE3, kappa), acquisition, safetensors, ONNX, quantization, compilation, ledger, Gherkin s0 to s2, docs, f32 inventory |
| `functions/B_*.md` | Execution ops, sampling, cache-free decoding, tokenizer, CNL gate, session and API, Gherkin s3 to s4, docs, f32 inventory |
| `alloy/` | Alloy 6 models and the scripts that run them |
| `checks/` | Shell checks against external authorities, with logs |

## License

AGPL-3.0-only. See [`LICENSE`](LICENSE). The analyzed upstream project is
licensed MIT OR Apache-2.0 by its authors.
