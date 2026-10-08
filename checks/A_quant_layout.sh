#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Team A check: decode the repo's Q4_0 / Q8_0 golden blocks with exact
# arithmetic (jq numbers; every product here is a dyadic rational that jq's
# doubles hold exactly) under two layouts, and count element mismatches
# against the repo's "expected" arrays.
#   interleaved : out[2i] = (lo_i - 8)*d, out[2i+1] = (hi_i - 8)*d
#                 (crates/hologram-ai-quant/src/q4_0.rs:20)
#   ggml split  : y[i] = (lo_i - 8)*d, y[i+16] = (hi_i - 8)*d
#                 (ggml/src/ggml-quants.c dequantize_row_q4_0)
# Q8_0 has one layout: y[i] = int8(qs[i]) * d.
# Analyzed source: hologram-ai (MIT OR Apache-2.0), read-only.
set -euo pipefail
SRC="${SRC:-/workspace/hologram-ai-src}"
Q4="$SRC/oracles/quant/q4_0_golden.json"
Q8="$SRC/oracles/quant/q8_0_golden.json"
F16='def f16: (.[0] + 256*.[1]) as $b
  | (($b/32768)|floor) as $s | ((($b/1024)|floor)%32) as $e | ($b%1024) as $m
  | (if $e == 0 then $m*pow(2;-24)
     elif $e == 31 then error("f16 inf/nan scale: exact spec undefined")
     else (1024+$m)*pow(2;$e-25) end)
  * (if $s == 1 then -1 else 1 end);'
echo "=== A_quant_layout $(date -Iseconds) (PT) ==="
echo "q4_0 file sha256: $(sha256sum "$Q4" | cut -d' ' -f1)"
echo "q8_0 file sha256: $(sha256sum "$Q8" | cut -d' ' -f1)"
echo
echo "Q4_0  name  scale_bits  scale_exact  mismatches_vs_interleaved/32  mismatches_vs_ggml_split/32"
jq -r "$F16"'
  .[] | . as $v
  | ($v.block_bytes[0:2]) as $sb | ($sb|f16) as $d | ($v.block_bytes[2:18]) as $qs
  | [range(0;16) | ((($qs[.] % 16) - 8) * $d)] as $lo
  | [range(0;16) | (((($qs[.] / 16)|floor) - 8) * $d)] as $hi
  | [range(0;16) | ($lo[.], $hi[.])] as $inter
  | ($lo + $hi) as $split
  | [ $v.name, ($sb[0] + 256*$sb[1]), $d,
      ([range(0;32) | select($inter[.] != $v.expected[.])] | length),
      ([range(0;32) | select($split[.] != $v.expected[.])] | length) ] | @tsv' "$Q4"
echo
echo "Q8_0  name  scale_bits  scale_exact  mismatches_vs_ggml/32"
jq -r "$F16"'
  .[] | . as $v
  | ($v.block_bytes[0:2]) as $sb | ($sb|f16) as $d | ($v.block_bytes[2:34]) as $qs
  | [range(0;32) | (if $qs[.] < 128 then $qs[.] else $qs[.] - 256 end) * $d] as $y
  | [ $v.name, ($sb[0] + 256*$sb[1]), $d,
      ([range(0;32) | select($y[.] != $v.expected[.])] | length) ] | @tsv' "$Q8"
