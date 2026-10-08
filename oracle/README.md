<!--
  Copyright (C) 2026 hologram-re contributors
  SPDX-License-Identifier: AGPL-3.0-only
-->

# oracle — executable oracle for the hologram-ai analysis

This directory holds a standalone, working reimplementation of the
tensor-extraction and quantization machinery from
[SNAPKITTYAGENT9NOVA/hologram-ai](https://github.com/SNAPKITTYAGENT9NOVA/hologram-ai),
rebuilt as an **independent executable oracle** for the analysis in
`../functions/`, `../alloy/`, and `../checks/`.

Where the analysis writes each upstream operation as a formal function with a
verdict, this oracle *runs*: feed it a `config.json` plus a safetensors file
and it builds the parametric decoder graph; feed it a regex pattern and text
and it runs the pre-tokenizer split; run the WAT kernels and they dequantize
bit-exactly.

## Crates

- `crates/hologram-ai-safetensors` — parametric decoder-graph builder.
  Entry point: `build_graph_from_safetensors(config_json, safetensors_shards)`.
  Examples: `drain` (checkpoint → graph inventory), `strip` (checkpoint →
  JSON tensor manifest).
- `crates/hologram-ai-common` — the canonical AI IR (`ir` module).
- `crates/hologram-ai-quant` — Q4_0 / Q8_0 block quantization, `no_std`.
- `crates/hologram-ai-tokenizer` — native BPE / Unigram / WordPiece core,
  `no_std`.
- `crates/hologram-ai-regex` — standalone regex pre-tokenizer
  (`RegexSplitter`, verbatim `split_fragments` logic). Example: `split` CLI.

## WebAssembly

`wasm/dequant.wat` holds hand-written WebAssembly Text for the quant kernels —
`f16_to_f32` (full IEEE 754: signed zero, subnormals, infinities, NaN),
`dequant_q8_0_block`, `dequant_q4_0_block`. Verified by `wasm/verify.mjs`
(15 checks) and differential-tested bit-identical against the Rust
implementation.

## Provenance and licensing

The Rust crates were rebuilt out of the upstream repository's sources. Those
source files carry no per-file license headers (upstream declares
`MIT OR Apache-2.0` in its `Cargo.toml` only); rebuilding them here under
`AGPL-3.0-only` was done under an explicit, source-specific waiver of the
per-file-header extraction rule, granted 2026-10-07. The WAT kernels, the
verify script, and the examples are hand-written for this project.
Everything in this directory is `AGPL-3.0-only`, matching the repository
`LICENSE`.

## Build

```sh
cargo build   # Rust 1.75+
cargo test
```
