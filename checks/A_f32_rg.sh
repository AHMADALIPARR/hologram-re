#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Team A: raw listing of every f32/f64/bit-cast/half use in the slice source
# files (steering 2). Pattern from the brief: f32|f64|as f32|from_bits|to_bits|half::
# Analyzed source: hologram-ai (MIT OR Apache-2.0), read-only.
set -euo pipefail
SRC="${SRC:-/workspace/hologram-ai-src}"
cd "$SRC"
FILES=(
  crates/hologram-ai-quant/src
  crates/hologram-ai-onnx/src/dtype_map.rs
  crates/hologram-ai-onnx/src/tensor_map.rs
  crates/hologram-ai-onnx/src/lib.rs
  crates/hologram-ai-onnx/src/op_map.rs
  crates/hologram-ai-onnx/src/graph_builder.rs
  crates/hologram-ai-safetensors/src
  crates/hologram-ai-model/src
  crates/hologram-ai/src/download
  crates/hologram-ai/src/address.rs
  crates/hologram-ai/src/materialize.rs
  crates/hologram-ai/src/quantized.rs
  crates/hologram-ai/src/compiler.rs
  crates/hologram-ai/src/staged.rs
  crates/hologram-archivum/src
  crates/hologram-ai-common/src/opt/const_dedup.rs
  crates/hologram-ai-common/src/lower/quantize.rs
  crates/hologram-ai-common/src/ir/param.rs
  crates/hologram-ai-conformance/src/witness.rs
)
PAT='\bf32\b|\bf64\b|as f32|from_bits|to_bits|half::'
echo "=== A_f32_rg $(date -Iseconds) (PT)  HEAD $(git rev-parse --short HEAD)"
echo "--- matching-line counts per file"
rg -c "$PAT" "${FILES[@]}" | sort || true
echo "--- total matching lines: $(rg -n "$PAT" "${FILES[@]}" | wc -l)"
echo "--- files in the list with zero matches"
for f in "${FILES[@]}"; do
  n=$( { rg -c "$PAT" "$f" 2>/dev/null || true; } | awk -F: '{s+=$NF} END{print s+0}')
  if [[ "$n" == 0 ]]; then echo "$f"; fi
done
echo "--- raw lines"
rg -n "$PAT" "${FILES[@]}" | cut -c1-200
