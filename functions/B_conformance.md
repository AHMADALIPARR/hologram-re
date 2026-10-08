<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# B_conformance — honesty meta-gate, BDD runner, anti-hardcode scan

Team B catalog. Source pin: hologram-ai @ `c9609c0`. Alloy: `alloy/B_conformance.als`. This file is about what the gates check, not about whether each scenario's Then is true.

---

### CF-01 model `validate` + honesty `audit`
- Source: `crates/hologram-ai-model/src/lib.rs:231` (`validate`); `crates/hologram-ai-model/src/honesty.rs:43` (`audit`)
- `validate` (subset used here): every row cites a non-empty set of known oracle ids.
- `audit`: tags present; suite rows (Verified, Build) carry no skip tag and no `@target`; Open rows carry `@target`.
- P1 the meta-gate implies every gating feature's steps are defined — **Absent**. The audit never opens the step bodies. Alloy `check gateImpliesStepsDefined` expected SAT (`B-CF-1`).
- P2 the meta-gate implies each gating row cites an independent authority — **Absent**. Any known oracle id passes, including a self-authored journey reference. Alloy `check gateImpliesIndependentAuthority` expected SAT (`B-CF-2`).
- P3 the meta-gate implies the cited authority is consulted by step code — **Absent**. Alloy `check gateImpliesConsulted` expected SAT (`B-CF-3`).

### CF-02 default-lane BDD runner
- Source: `crates/hologram-ai-conformance/tests/bdd.rs` main, fail-on-skipped and the "selected features ran" assert (file is about 5,000 lines; the runner tail is past `:4960`)
- Definition: select rust / default-lane features without `@target`. An undefined step is skipped, and `fail_on_skipped` plus a skipped-count assert fail the run.
- P1 a green default-lane run implies every selected feature's steps are defined — **Implemented** (that is what fail-on-skipped checks). Alloy `check greenImpliesDefined` expected UNSAT (`B-CF-4`).
- P2 a green run implies each Then checks its postcondition — **Absent**. A step that only prints passes. The `@target` rows documented as "reported, never asserted" are the example, when they are selected. Alloy `check greenImpliesThenChecked` expected SAT (`B-CF-5`).

### CF-03 `scripts/anti-hardcode.sh`
- Definition transcribed into the model: the scan globs `safetensors/src/*.rs` and `wasm/src/*.rs` (plus web URL patterns) and stops at the first `#[cfg(test)]`.
- P1 a passing scan implies no model-specific constant in non-test source — **Absent**. Files outside those globs are invisible, and a constant after the first `#[cfg(test)]` in a scanned file is invisible. Alloy `check antiHardcodeComplete` expected SAT (`B-CF-6`).
