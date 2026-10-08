<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# B_cnl — the command gate in front of generation

Team B catalog. Source pin: hologram-ai @ `c9609c0`. Alloy: `alloy/B_cnl-gate.als`. Integers in the model are the prime token values from the lexer arms, not temperatures.

---

### CN-01 `compile_command`
- Source: `crates/hologram-cnl/src/lib.rs:118–180`
- Signature: `compile_command : String → Result<CompilationResult, String>`
- Definition, two phases:
  1. Action scan on the whitespace tokens, case-sensitive, priority order (`:129–150`): `temperature` and `zero` both present → `ConfigTempZero { temperature: 0.0 }`; else `deploy`; else `scale`; else `destroy`; else `revoke`; else none.
  2. Token loop (`:155–180`): each token lowercased, mapped to a prime (`deploy=2`, `scale=3`, `web-service=5`, `cluster=7`, `on=5`, `with=11`, `replicas=13`, `3=17`, `5=23`, `2=29`, `temperature=23`, `zero=29`, `must=31`, `be=37`, `revoke|cancel=19`, `it=5`, `all=1`). Unknown token → `Err`. Empty input → `Err`. `"destroy"` is in the action scan and in the lexicon comment, and has no arm in the token loop, so a destroy prompt fails the lexer.
- AST: first token is `Ap(p)`, later tokens are applied. `PhaseMirrorInvariants::enforce_all` (`:40–49`) returns `Err` iff the AST is `Ap(1)`, i.e. the prompt is exactly the one word that lexes to 1 (`"all"`, any case, because the loop lowercases).
- P1 a diagnostic (blocked) request never reaches generation — **Implemented** by construction of CN-02. Alloy `check blockedNeverGenerates` expected UNSAT (`B-CNL-1`).
- P2 the gate blocks exactly the single-word prompt `"all"` — **Implemented** among prompts that lex. Alloy `check gateIsSingletonAll` expected UNSAT (`B-CNL-2`). `"All"`, `"ALL"` also block; `"all all"` does not.
- P3 allowed generation implies the temperature-zero action — **Absent**. `"temperature 5"`, `"deploy"`, `"all all"` lex and are not `Ap(1)`. Alloy `check temperaturePolicyEnforced` expected SAT (`B-CNL-3`).
- P4 legal (or medical) domain requires temperature 0 — **Absent**. The domain never enters the gate. Alloy `check legalDomainRequiresTempZero` expected SAT (`B-CNL-4`). ADR-001 prose that says otherwise is **Marketing**.
- P5 the Destroy action can be allowed — **Absent** (no lexer arm). Alloy `run destroyAllowed` expected no instance (`B-CNL-5`).

### CN-02 `handle_request` on `hologram_generate`
- Source: `apps/hologram-api/src/main.rs:115–170`, branch at `:125–162`
- Definition: missing `prompt` → JSON-RPC `-32602`. `compile_command` error → `-32002` and an `MCP_TOOL_ERROR` log. `Ok` but not `invariants_passed()` → error "CNL Invariants failed: Generation Blocked." and `MCP_TOOL_BLOCKED`. `Ok` and passed → log `MCP_TOOL_CALL` allowed, and the handler returns without calling a model. The allowed branch logs the action and the routed model name; it does not generate.
- P1 the API enforces temperature 0 before generation — **Absent**. The only reject is CN-01's singleton `"all"`, and the success path does not call generation in this handler.
- P2 unknown methods fail closed — **Implemented** (`-32601` "Method not found").
