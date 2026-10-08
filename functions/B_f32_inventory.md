<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# B_f32_inventory — floating-point paths in the B surface

Team B catalog. Source pin: hologram-ai @ `c9609c0`. Counts are `grep -c` of the token `f32` / `f64` in the file, not a count of semantic uses. Exact functions in the other B files are the specification; each row here is an approximation of one of them.

| File | f32 | f64 | What the floats do |
|---|---:|---:|---|
| `crates/hologram-ai/src/commands/generate.rs` | 10 | 10 | Logit row is `bytemuck::cast_slice` to `&[f32]`. `argmax` seeds `NEG_INFINITY` and uses strict `>`. `sample` divides by `temperature` in f32, shifts by f32 max, `exp`s in f64, accumulates in f64. `next_unit` is a 53-bit SplitMix64 mapped through f64. Attention mask is `vec![1.0; cur_len]` and position ids are `p as f64`, then encoded. |
| `crates/hologram-ai/src/engine.rs` | 0 | 0 | Window arithmetic is `usize`. No float. |
| `crates/hologram-ai/src/staged.rs` | 0 | 0 | Residency is byte counts. No float. |
| `crates/hologram-ai-tokenizer/src/native.rs` | 2 | 1 | Not on the special-token path. Unigram score tables (not re-derived). |
| `crates/hologram-cnl/src/lib.rs` | 1 | 2 | `ConfigTempZero.temperature : f32 = 0.0`. The value is stored and never compared. |
| `crates/hologram-ai-core/src/reducer.rs` | 0 | 0 | No float. |
| `crates/hologram-ai-common/src/lower/dispatch.rs` | 9 | 1 | Attribute payloads (`Lrn` alpha/beta/bias, `Attention.rope_base`). Not evaluated by the collapse in EX-03. |

Breaks against the exact functions:

- SA-05. A NaN logit never wins strict `>`. An all-NaN row returns index 0. `+0.0` and `-0.0` compare equal, so the first wins, matching the exact first-maximal rule.
- SA-06. `partial_cmp` of a NaN yields `None`, and the sort treats that as `Equal`, so a NaN can sit anywhere in a tie group. The inverse-CDF uses f64 `exp` of an f32 quotient; two seeds can pick different indices for logits that are equal as exact rationals after rounding. Temperature `≤ 0` skips all of this.
- CN-01. The stored `0.0` is not a policy check. Exact temperature is irrelevant to the gate.
- Execution-parity scenarios that say "within tolerance" are approximations of an exact logit equality the code does not claim. Not traced past the title (`B_gherkin.md`).
