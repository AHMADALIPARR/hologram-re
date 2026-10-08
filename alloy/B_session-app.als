-- SPDX-License-Identifier: AGPL-3.0-only
-- Team B model: domain-event reducer, domain routing table, browser session trimming.
-- Analyzed source: hologram-ai @ c9609c0 (MIT OR Apache-2.0)
--   crates/hologram-ai-core/src/reducer.rs:11-152 (reduce, apply_event, mark_*)
--   apps/hologram-api/src/routing.rs:19-26 (load_from_yaml, resolve_model), apps/hologram-api/routing.yaml
--   apps/web/src/pages/Chat.tsx:102-123 (buildMultiTurnPrompt), :266-284 (trim loop)
-- Integer-only. Token counts are modelled as additive per message (template + sum of
-- message sizes); real BPE counts of a concatenation are not additive, so results about
-- "fits" are about this abstraction. Alloy checks this model, not the Rust/TypeScript.
module B_session_app

open util/ordering[Ev] as EO

------------------------------------------------------------------------
-- Part 1: reducer, one request, a trace of events
------------------------------------------------------------------------
abstract sig Kind {}
one sig Submit, Start, Complete, Fail extends Kind {}
abstract sig Status {}
one sig Absent, Pending, Completed, Failed extends Status {}
abstract sig YN {}
one sig Yes, No extends YN {}

sig Ev { kind: one Kind, st: one Status, failedReq: one YN }   -- state AFTER the event

-- state transformer apply_event restricted to one request key
pred step[pst: Status, pfr: YN, e: Ev] {
  e.kind = Submit => (e.st = Pending and e.failedReq = No)
  else e.kind = Start => (e.st = pst and e.failedReq = pfr)          -- only Pending -> Running
  else e.kind = Complete => (
    -- request_for_completion: pending, else completed, else failed.request
    let known = (pst in Pending + Completed or (pst = Failed and pfr = Yes)) |
      (known => e.st = Completed else e.st = Absent) and e.failedReq = No)
  else (                                                             -- Fail
    e.st = Failed and (pst in Pending + Completed => e.failedReq = Yes else e.failedReq = No))
}
fact trace {
  step[Absent, No, EO/first]
  all e: Ev - EO/last | step[e.st, e.failedReq, EO/next[e]]
}
fun lastTerminal: lone Ev { { e: Ev | e.kind in Complete + Fail and no f: EO/nexts[e] | f.kind in Complete + Fail } }
fun final: Status { EO/last.st }

-- B-SA-1 (app_domain_events.feature "event order decides the terminal state"): the later
-- terminal event wins. Refuted without a prior submission: [Fail, Complete] leaves Absent.
assert laterTerminalWins {
  some lastTerminal implies
    (lastTerminal.kind = Complete => final = Completed else final = Failed)
  -- (events after the last terminal are Submit/Start; restrict to traces ending in it)
  or some f: EO/nexts[lastTerminal] | f.kind = Submit
}
check laterTerminalWins for 4 but 7 int expect 1

-- B-SA-2: with a submission before the first terminal event, the later terminal event wins.
-- Refuted: [Submit, Fail, Fail, Complete] ends Absent. The second Fail looks for the request
-- only in pending/completed (reducer.rs:124-132), stores request = None, and the Complete then
-- finds no request (reducer.rs:103-113) and drops the job.
assert laterTerminalWinsAfterSubmit {
  (some s: Ev | s.kind = Submit and all t: Ev | t.kind in Complete + Fail implies EO/lt[s, t])
  and (no f: EO/nexts[lastTerminal] | f.kind = Submit) and some lastTerminal
    implies (lastTerminal.kind = Complete => final = Completed else final = Failed)
}
check laterTerminalWinsAfterSubmit for 4 but 7 int expect 1

-- B-SA-2b: same, when the trace has at most one Fail event.
assert laterTerminalWinsAfterSubmitOneFail {
  (some s: Ev | s.kind = Submit and all t: Ev | t.kind in Complete + Fail implies EO/lt[s, t])
  and (lone e: Ev | e.kind = Fail)
  and (no f: EO/nexts[lastTerminal] | f.kind = Submit) and some lastTerminal
    implies (lastTerminal.kind = Complete => final = Completed else final = Failed)
}
check laterTerminalWinsAfterSubmitOneFail for 6 but 7 int expect 0

pred reducerNonVacuous { some e: Ev | e.kind = Complete and e.st = Absent }
run reducerNonVacuous for 4 but 7 int expect 1

------------------------------------------------------------------------
-- Part 2: routing table
------------------------------------------------------------------------
sig Dom {}        -- domain string after ASCII case folding
sig Model {}
sig Route { dom: one Dom, model: one Model }
one sig Table { routes: seq Route, default: one Model }
fun resolve[d: Dom]: one Model {
  (some i: Table.routes.inds | Table.routes[i].dom = d)
    => Table.routes[min[{ i: Table.routes.inds | Table.routes[i].dom = d }]].model
    else Table.default
}
-- B-SA-3: resolve is total and single-valued (first match wins, else default_model).
assert resolveTotal { all d: Dom | one resolve[d] }
check resolveTotal for 4 but 7 int expect 0
-- B-SA-4: the loaded table is unambiguous (no domain listed twice). Refuted: load_from_yaml
-- is plain serde deserialisation with no uniqueness check; a later duplicate is dead.
assert tableUnambiguous { all disj i, j: Table.routes.inds | Table.routes[i].dom != Table.routes[j].dom }
check tableUnambiguous for 4 but 7 int expect 1
pred routingNonVacuous { some d: Dom | resolve[d] != Table.default }
run routingNonVacuous for 4 but 7 int expect 1

------------------------------------------------------------------------
-- Part 3: browser session trimming
------------------------------------------------------------------------
abstract sig Role {}
one sig User, Assistant extends Role {}
sig Msg { role: one Role, size: Int }
one sig Chat { h: seq Msg, tmpl: Int, ctx: Int, k: Int }
fact chatRanges {
  all m: Msg | m.size >= 1 and m.size =< 6
  Chat.tmpl >= 0 and Chat.tmpl =< 4 and Chat.ctx >= 1 and Chat.ctx =< 20
  not Chat.h.isEmpty and Chat.h.last.role = User          -- pending user message at the tail
}
fun suffixFrom[j: Int]: seq Msg { Chat.h.subseq[j, minus[#Chat.h, 1]] }
fun tokens[s: seq Msg]: Int { plus[Chat.tmpl, sum i: s.inds | s[i].size] }
pred fits[s: seq Msg] { tokens[s] =< Chat.ctx }
-- the while loop drops 2 from the front while tokens > ctx and length > 2;
-- Chat.k = number of iterations
fact loopSemantics {
  Chat.k >= 0 and mul[2, Chat.k] < #Chat.h
  all j: Int | (j >= 0 and j < Chat.k) implies
     (not fits[suffixFrom[mul[2, j]]] and #suffixFrom[mul[2, j]] > 2)
  fits[suffixFrom[mul[2, Chat.k]]] or #suffixFrom[mul[2, Chat.k]] =< 2
}
fun result: seq Msg { suffixFrom[mul[2, Chat.k]] }

-- B-SA-5: the pending message survives trimming.
assert pendingSurvives { result.last = Chat.h.last }
check pendingSurvives for 5 but 7 int, 5 seq expect 0
-- B-SA-6: the result fits the context, or only the last <= 2 messages remain.
assert fitsOrMinimal { fits[result] or #result =< 2 }
check fitsOrMinimal for 5 but 7 int, 5 seq expect 0
-- B-SA-7 (session_window.feature "continues rather than dead-ending"): the result always
-- fits. Refuted: a single pending message larger than the context.
assert alwaysFits { fits[result] }
check alwaysFits for 5 but 7 int, 5 seq expect 1
-- B-SA-8: the trimmed prompt leaves room for at least one generated token. Refuted:
-- tokens = ctx passes the loop guard, and generate_stream's budget is then 0.
assert roomToGenerate { tokens[result] < Chat.ctx or not fits[result] }
check roomToGenerate for 5 but 7 int, 5 seq expect 1
pred trimNonVacuous { Chat.k = 1 and #Chat.h = 5 }
run trimNonVacuous for 5 but 7 int, 5 seq expect 1
