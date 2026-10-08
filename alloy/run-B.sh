#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Team B Alloy runner. Same contract as run-A.sh: one JVM per command, never
# in parallel. check X: UNSAT = holds in the model (PASS); SAT = counterexample
# (FAIL). run X: SAT = an instance exists.
# Alloy checks the models, not the Rust (analyzed source: hologram-ai @ c9609c0,
# MIT OR Apache-2.0). B_window64.als is 10-bit Int and is slow; leave it in
# the glob unless ALLOY_SKIP_WINDOW64=1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
JAR="${ALLOY_JAR:-/workspace/hcalc/alloy/tools/org.alloytools.alloy.dist.jar}"
TS="$(date +%Y%m%dT%H%M%S)"
LOG="$ROOT/logs/B-$TS.txt"
OUT="$ROOT/logs/per-check-B-$TS"
mkdir -p "$OUT" "$ROOT/logs"
exec 9>"$ROOT/logs/.run-B.lock"
flock -n 9 || { echo "another run-B.sh is active; refusing to run in parallel" >&2; exit 2; }

shopt -s nullglob
FILES=("$ROOT"/B_*.als)
if [[ "${ALLOY_SKIP_WINDOW64:-0}" == 1 ]]; then
  FILES=("${FILES[@]/$ROOT\/B_window64.als}")
fi
[[ ${#FILES[@]} -gt 0 ]] || { echo "no B_*.als files" >&2; exit 2; }

{
  echo "=== Team B Alloy run $(date -Iseconds) ==="
  echo "jar: $JAR"
  java -version 2>&1 | head -1
  java -jar "$JAR" version 2>/dev/null || true
  PASS=0; FAIL=0; RUN_OK=0; RUN_BAD=0; GAP=0; ERR=0
  for ALS in "${FILES[@]}"; do
    [[ -f "$ALS" ]] || continue
    name="$(basename "$ALS" .als)"
    echo
    echo "--- $name  (sha256 $(sha256sum "$ALS" | cut -c1-16))"
    if ! mapfile -t LINES < <(java -jar "$JAR" commands "$ALS" 2>&1); then
      echo "ERROR: could not list commands"; ERR=$((ERR+1)); continue
    fi
    if ! printf '%s\n' "${LINES[@]}" | rg -q '^[0-9]+ \. (Check|Run) '; then
      printf '%s\n' "${LINES[@]}" | tail -8
      echo "ERROR: $name did not parse"; ERR=$((ERR+1)); continue
    fi
    for line in "${LINES[@]}"; do
      KIND=""; CMD=""
      if [[ "$line" =~ Check[[:space:]]+([A-Za-z0-9_]+) ]]; then KIND=check; CMD="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ Run[[:space:]]+([A-Za-z0-9_]+) ]]; then KIND=run; CMD="${BASH_REMATCH[1]}"
      else continue; fi
      o="$OUT/$name/$CMD"; rm -rf "$o"; mkdir -p "$(dirname "$o")"
      set +e
      out=$(java -jar "$JAR" exec -f -o "$o" -t text -c "$CMD" "$ALS" 2>&1)
      rc=$?
      set -e
      if echo "$out" | rg -q '\bUNSAT\b'; then res=UNSAT
      elif echo "$out" | rg -q '\bSAT\b'; then res=SAT
      else res="UNKNOWN(rc=$rc)"; fi
      if [[ "$KIND" == check ]]; then
        if [[ "$res" == UNSAT ]]; then printf '%-58s UNSAT (PASS)\n' "check $CMD"; PASS=$((PASS+1))
        else printf '%-58s %s (FAIL)\n' "check $CMD" "$res"; echo "$out" | tail -5; FAIL=$((FAIL+1)); fi
      else
        if [[ "$res" == SAT ]]; then
          if [[ "$CMD" == gap_* ]]; then printf '%-58s SAT (counterexample to repo claim)\n' "run $CMD"; GAP=$((GAP+1))
          else printf '%-58s SAT (instance, non-vacuous)\n' "run $CMD"; fi
          RUN_OK=$((RUN_OK+1))
        else printf '%-58s %s (RUN NOT SAT)\n' "run $CMD" "$res"; echo "$out" | tail -5; RUN_BAD=$((RUN_BAD+1)); fi
      fi
    done
  done
  echo
  echo "=== summary ==="
  echo "files=${#FILES[@]} checks_UNSAT_PASS=$PASS checks_FAIL=$FAIL runs_SAT=$RUN_OK (of which gap_=$GAP) runs_not_SAT=$RUN_BAD parse_errors=$ERR"
  echo "log: $LOG"
  echo "=== done ==="
  [[ "$FAIL" -eq 0 && "$RUN_BAD" -eq 0 && "$ERR" -eq 0 ]]
} 2>&1 | tee "$LOG"
