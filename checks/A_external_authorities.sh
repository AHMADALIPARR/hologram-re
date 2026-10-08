#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Team A check: consult the external authorities that the repo names, with
# read-only public GETs, and print what they say. No writes anywhere.
# Analyzed source: hologram-ai (MIT OR Apache-2.0), read-only.
set -uo pipefail
SRC="${SRC:-/workspace/hologram-ai-src}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "=== A_external_authorities $(date -Iseconds) (PT) ==="

echo; echo "--- 1. BLAKE3 KATs: repo copy vs upstream BLAKE3-team/BLAKE3 master ---"
curl -fsSL https://raw.githubusercontent.com/BLAKE3-team/BLAKE3/master/test_vectors/test_vectors.json -o "$TMP/up.json" \
  && echo "upstream sha256: $(sha256sum "$TMP/up.json" | cut -d' ' -f1)" || echo "upstream fetch FAILED"
echo "repo     sha256: $(sha256sum "$SRC/oracles/blake3/test_vectors.json" | cut -d' ' -f1)"
cmp -s "$TMP/up.json" "$SRC/oracles/blake3/test_vectors.json" && echo "byte-identical: yes" || echo "byte-identical: no"
echo "cases: $(jq '.cases|length' "$SRC/oracles/blake3/test_vectors.json")  input_len set: $(jq -c '[.cases[].input_len]' "$SRC/oracles/blake3/test_vectors.json")"

echo; echo "--- 2. GGML dequantize_row_q4_0 / q8_0 (ggml-org/ggml master) ---"
if curl -fsSL https://raw.githubusercontent.com/ggml-org/ggml/master/src/ggml-quants.c -o "$TMP/q.c"; then
  for fn in dequantize_row_q4_0 dequantize_row_q8_0; do
    start=$(rg -n "^void ${fn}\(" "$TMP/q.c" | head -1 | cut -d: -f1)
    echo "[$fn at ggml-quants.c:$start]"
    sed -n "${start},$((start+20))p" "$TMP/q.c" | awk '{print} /^}/{exit}'
  done
else echo "ggml fetch FAILED"; fi

echo; echo "--- 3. Hugging Face /api/models shape (what download/hf_api.rs requests) ---"
M=HuggingFaceTB/SmolLM2-135M
echo "GET /api/models/$M  -> first sibling (no ?blobs=true, as in hf_api.rs):"
curl -fsSL "https://huggingface.co/api/models/$M" | jq -c '.siblings[0]'
echo "GET /api/models/$M?blobs=true -> first sibling:"
curl -fsSL "https://huggingface.co/api/models/$M?blobs=true" | jq -c '.siblings[0] | {rfilename, size, lfs: (.lfs|type)}'
echo "GET /api/models/hologram-ai/this-repo-does-not-exist -> HTTP status:"
curl -s -o /dev/null -w '%{http_code}\n' "https://huggingface.co/api/models/hologram-ai/this-repo-does-not-exist"

echo; echo "--- 4. oracles.toml sha256 pins vs files on disk ---"
awk -F'"' '/^id *=/{id=$2} /path *=/{p=$2} /sha256 *=/{print id" "p" "$2}' "$SRC/model/oracles.toml" |
while read -r id p want; do
  [[ -z "$want" ]] && { echo "$id $p pin=EMPTY"; continue; }
  got=$(sha256sum "$SRC/$p" 2>/dev/null | cut -d' ' -f1)
  [[ "$got" == "$want" ]] && echo "$id $p match" || echo "$id $p MISMATCH got=$got want=$want"
done
