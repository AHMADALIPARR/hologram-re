<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# B_session — domain reducer, routing table, browser trim

Team B catalog. Source pin: hologram-ai @ `c9609c0`. Alloy: `alloy/B_session-app.als`. Token counts in the trim model are additive (template + sum of message sizes). Real BPE counts of a concatenation are not additive, so "fits" results are about that abstraction.

---

### SE-01 `reduce` / `apply_event`
- Source: `crates/hologram-ai-core/src/reducer.rs:11–152`; completion lookup `:103–113`; fail lookup `:124–132` (`mark_failed` only reads pending and completed)
- Definition on one request key, starting from Absent:
  - Submit → Pending, failed-request flag cleared.
  - Start → state unchanged (the running flag is not in this projection).
  - Complete → Completed if the request is pending, already completed, or failed-with-request; otherwise the event is dropped (Absent).
  - Fail → Failed. The stored request is cloned from pending or completed only. A second Fail, finding neither, stores `request = None`.
- P1 the same event stream reduces to the same view — **Implemented** (pure function, no clock). Scenario `app_domain_events.feature` "the same event stream reduces to the same view".
- P2 the later terminal event wins — **Absent** without a prior Submit, and **Absent** with two Fails. `[Fail, Complete]` ends Absent. `[Submit, Fail, Fail, Complete]` ends Absent: the second Fail stored `request = None`, and Complete then finds no request. Alloy `check laterTerminalWins` and `check laterTerminalWinsAfterSubmit` expected SAT (`B-SA-1`, `B-SA-2`). With at most one Fail after a Submit, the later terminal wins. Alloy `check laterTerminalWinsAfterSubmitOneFail` expected UNSAT (`B-SA-2b`).
- The scenario "order decides the terminal state of a request" is **Asserted-only**: true on the traces the steps build, not on every trace.

### SE-02 routing table
- Source: `apps/hologram-api/src/routing.rs:19–26` (`load_from_yaml`, `resolve_model`), table `apps/hologram-api/routing.yaml`
- Definition: `resolve(domain)` is the model of the first route whose domain equals the ASCII-folded query, else `default_model`. `load_from_yaml` is serde deserialization with no uniqueness check.
- P1 resolve is total and single-valued — **Implemented**. Alloy `check resolveTotal` expected UNSAT (`B-SA-3`).
- P2 the loaded table is unambiguous — **Absent**. A later duplicate domain is dead. Alloy `check tableUnambiguous` expected SAT (`B-SA-4`).

### SE-03 browser session trim
- Source: `apps/web/src/pages/Chat.tsx:102–123` (`buildMultiTurnPrompt`), `:262–284` (trim loop)
- Definition: pending user message is already the tail. While `countTokens(template(prompt)) > ctx` and `history.length > 2`, drop the first two messages and rebuild. On a counting error, send untrimmed. If `ctx` or the tokenizer is missing, send untrimmed.
- P1 the pending message survives — **Implemented** (the loop stops at length 2, and the tail is the pending user turn). Alloy `check pendingSurvives` expected UNSAT (`B-SA-5`).
- P2 the result fits, or only the last ≤ 2 messages remain — **Implemented** in the additive model, and in the TS loop by the same guard. Alloy `check fitsOrMinimal` expected UNSAT (`B-SA-6`).
- P3 the result always fits the context — **Absent**. A single pending message larger than the context is sent anyway. The engine then fails loud (SA-04). Alloy `check alwaysFits` expected SAT (`B-SA-7`). Scenario `session_window.feature` "a transcript outgrowing the context trims oldest-first and continues" is **Asserted-only** (true when some suffix of turn-pairs fits).
- P4 the trimmed prompt leaves room for at least one generated token — **Absent**. `tokens = ctx` passes the loop (`>`), and `generate_stream`'s budget is then 0. Alloy `check roomToGenerate` expected SAT (`B-SA-8`).
