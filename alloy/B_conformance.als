-- SPDX-License-Identifier: AGPL-3.0-only
-- Team B model: the honesty meta-gate (model validate + honesty audit) and the BDD runner.
-- Analyzed source: hologram-ai @ c9609c0 (MIT OR Apache-2.0)
--   crates/hologram-ai-model/src/lib.rs:231 (validate), crates/hologram-ai-model/src/honesty.rs:43 (audit)
--   crates/hologram-ai-conformance/tests/bdd.rs main (~4960+): fail_on_skipped, "selected features ran"
--   scripts/anti-hardcode.sh (file globs, stop at first #[cfg(test)])
-- No integers needed. Alloy checks this model, not the Rust/shell.
module B_conformance

abstract sig Level {}
one sig Verified, Build, Open extends Level {}
abstract sig Exec {}
one sig Rust, Browser extends Exec {}
abstract sig YN {}
one sig Y, N extends YN {}

sig Oracle { independent: one YN }        -- authored outside this repo AND outside its substrate
sig Step { defined: one YN, checksThen: one YN }
sig Feature { stepSet: some Step, tagsOk: one YN, skipTag: one YN, targetTag: one YN }
sig Row {
  level: one Level, exec: one Exec, defaultLane: one YN,
  oracles: set Oracle, consulted: set Oracle, feature: one Feature
}
fact { all r: Row | r.consulted in r.oracles }
fact { all f: Feature | some feature.f }            -- honesty: every on-disk feature is claimed

pred gating[r: Row] { r.level in Verified + Build }
-- lib.rs validate (subset relevant here): non-empty known oracles per row
pred validateOk { all r: Row | some r.oracles }
-- honesty.rs audit: tags present; suite rows carry no skip tags; target rows carry @target;
-- open rows are non-gating (true by construction of `gating`)
pred auditOk {
  all r: Row | r.feature.tagsOk = Y
  all r: Row | gating[r] implies r.feature.skipTag = N and r.feature.targetTag = N
  all r: Row | r.level = Open implies r.feature.targetTag = Y
}
-- default-lane runner: selects rust/default-lane features without @target; any undefined
-- step is "skipped" and fails the run (fail_on_skipped + skipped == 0 assert)
fun selected: set Row { { r: Row | r.exec = Rust and r.defaultLane = Y and r.feature.targetTag = N } }
pred runnerGreen { all r: selected, s: r.feature.stepSet | s.defined = Y }

-- B-CF-1: the meta-gate implies every gating feature's stepSet are defined. Refuted: the
-- audit never looks at step definitions.
assert gateImpliesStepsDefined {
  (validateOk and auditOk) implies (all r: Row | gating[r] implies (all s: r.feature.stepSet | s.defined = Y))
}
check gateImpliesStepsDefined for 4 expect 1

-- B-CF-2: the meta-gate implies each gating row cites an independent authority. Refuted:
-- any known oracle id passes, including the self-authored journey-reference.
assert gateImpliesIndependentAuthority {
  (validateOk and auditOk) implies (all r: Row | gating[r] implies some r.oracles & independent.Y)
}
check gateImpliesIndependentAuthority for 4 expect 1

-- B-CF-3: the meta-gate implies the cited authority is actually consulted by step code. Refuted.
assert gateImpliesConsulted {
  (validateOk and auditOk) implies (all r: Row | r.oracles in r.consulted)
}
check gateImpliesConsulted for 4 expect 1

-- B-CF-4: a green default-lane run implies every selected feature's stepSet are defined.
assert greenImpliesDefined { runnerGreen implies (all r: selected, s: r.feature.stepSet | s.defined = Y) }
check greenImpliesDefined for 4 expect 0

-- B-CF-5: a green run implies each Then really checks its postcondition. Refuted: a step
-- that only prints (e.g. the @target "reported, never asserted" rows when selected) passes.
assert greenImpliesThenChecked { runnerGreen implies (all r: selected, s: r.feature.stepSet | s.checksThen = Y) }
check greenImpliesThenChecked for 4 expect 1

pred gateNonVacuous { validateOk and auditOk and runnerGreen and some selected }
run gateNonVacuous for 4 expect 1

------------------------------------------------------------------------
-- anti-hardcode.sh: scanned file set and the "stop at first #[cfg(test)]" cut
------------------------------------------------------------------------
sig SrcFile { scanned: one YN, hasModelConstant: one YN, constantBeforeCfgTest: one YN }
pred antiHardcodePasses { all f: SrcFile | (f.scanned = Y and f.hasModelConstant = Y) implies f.constantBeforeCfgTest = N }
-- B-CF-6: passing anti-hardcode implies no model-specific constant in non-test source.
-- Refuted: only safetensors/src/*.rs and wasm/src/*.rs are scanned (plus web URL patterns).
assert antiHardcodeComplete {
  antiHardcodePasses implies (no f: SrcFile | f.hasModelConstant = Y and f.constantBeforeCfgTest = Y)
}
check antiHardcodeComplete for 3 expect 1
