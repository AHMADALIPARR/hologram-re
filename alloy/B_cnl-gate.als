-- SPDX-License-Identifier: AGPL-3.0-only
-- Team B reverse-engineering model of hologram-cnl + apps/hologram-api
-- Analyzed source: hologram-ai @ c9609c0 (MIT OR Apache-2.0)
--   crates/hologram-cnl/src/lib.rs:118-204 (compile_command; action scan 129-150, token loop 155-180), :40-49 (enforce_all)
--   apps/hologram-api/src/main.rs:115-170 (handle_request)
-- Integer-only model. Alloy checks this model, not the Rust.
module B_cnl_gate

abstract sig Bool {}
one sig True, False extends Bool {}

-- Lexer atoms: the arms of the token loop at lib.rs:155-180, value = prime from code.
abstract sig Tok { p: Int }
one sig TDeploy, TScale, TWebService, TCluster, TOn, TWith, TReplicas,
        TThree, TFive, TTwo, TTemperature, TZero, TMust, TBe, TRevoke, TIt, TAll extends Tok {}
fact tokValues {
  TDeploy.p = 2 and TScale.p = 3 and TWebService.p = 5 and TCluster.p = 7 and TOn.p = 5
  and TWith.p = 11 and TReplicas.p = 13 and TThree.p = 17 and TFive.p = 23 and TTwo.p = 29
  and TTemperature.p = 23 and TZero.p = 29 and TMust.p = 31 and TBe.p = 37 and TRevoke.p = 19
  and TIt.p = 5 and TAll.p = 1
}

-- A whitespace-separated word of the prompt.
--   lex   : the token after to_lowercase() (none = "Unknown token" error, lib.rs:178)
--   lower : the word is already lowercase, so the case-sensitive action scan
--           (tokens.contains(&"deploy") etc., lib.rs:129-150) sees it
--   isDestroy : the word is "destroy" -- present in LEXICON and in the action scan,
--               but there is no "destroy" arm in the token loop, so lex = none
sig Word { lex: lone Tok, lower: one Bool, isDestroy: one Bool }
fact destroyHasNoLexArm { all w: Word | w.isDestroy = True implies (no w.lex and w.lower = True) }

abstract sig Action {}
one sig AConfigTempZero, ADeploy, AScale, ADestroy, ARevoke, ANone extends Action {}

abstract sig Domain {}
one sig Legal, Medical, General extends Domain {}

one sig Req {
  words: seq Word,
  domain: one Domain
}

fun exactSeen[t: Tok]: set Word { { w: Req.words.elems | w.lower = True and w.lex = t } }

-- compile_command returns Err(..)
pred compileErr { Req.words.isEmpty or (some w: Req.words.elems | no w.lex) }

-- PhaseMirrorInvariants::enforce_all on StratumBoundary(ast): Err iff ast = Ap(1),
-- which happens iff the prompt is exactly one word lexing to p = 1 ("all").
pred diagnostic { not compileErr and #Req.words = 1 and Req.words.first.lex.p = 1 }

-- Action scan priority (lib.rs:129-150); temperature+zero first.
fun action: one Action {
  (some exactSeen[TTemperature] and some exactSeen[TZero]) => AConfigTempZero
  else (some exactSeen[TDeploy]) => ADeploy
  else (some exactSeen[TScale]) => AScale
  else (some w: Req.words.elems | w.isDestroy = True) => ADestroy
  else (some exactSeen[TRevoke]) => ARevoke
  else ANone
}

-- handle_request "hologram_generate" (main.rs:126-162): generation is allowed iff
-- compile_command is Ok and invariants_passed().
pred generationAllowed { not compileErr and not diagnostic }

-- B-CNL-1: a blocked (diagnostic) request never reaches generation. Holds by construction.
assert blockedNeverGenerates { diagnostic implies not generationAllowed }
check blockedNeverGenerates for 5 but 7 int, 4 seq expect 0

-- B-CNL-2: the gate blocks exactly the single-word prompt "all" (case-insensitive).
assert gateIsSingletonAll {
  (not compileErr and not generationAllowed) iff (#Req.words = 1 and Req.words.first.lex = TAll)
}
check gateIsSingletonAll for 5 but 7 int, 4 seq expect 0

-- B-CNL-3 (README claim "Temperature = 0.0" policy): allowed generation implies the
-- temperature-zero action. Refuted: e.g. "temperature 5", "deploy", "all all" pass.
assert temperaturePolicyEnforced { generationAllowed implies action = AConfigTempZero }
check temperaturePolicyEnforced for 5 but 7 int, 4 seq expect 1

-- B-CNL-4: domain-specific policy (ADR-001 "verifying temperature = 0.0 for specific
-- domains"). The domain never enters the gate, so this is refuted.
assert legalDomainRequiresTempZero {
  (generationAllowed and Req.domain = Legal) implies action = AConfigTempZero
}
check legalDomainRequiresTempZero for 5 but 7 int, 4 seq expect 1

-- B-CNL-5: the Destroy action can never be allowed (no lexer arm). Non-vacuity style run
-- that is expected to have NO instance.
pred destroyAllowed { generationAllowed and action = ADestroy }
run destroyAllowed for 5 but 7 int, 4 seq expect 0

-- Non-vacuity runs.
pred someBlocked { diagnostic }
run someBlocked for 5 but 7 int, 4 seq expect 1
pred someAllowedNonZeroTemp { generationAllowed and action != AConfigTempZero }
run someAllowedNonZeroTemp for 5 but 7 int, 4 seq expect 1
