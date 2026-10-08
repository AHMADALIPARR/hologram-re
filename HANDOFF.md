<!-- SPDX-License-Identifier: AGPL-3.0-only -->
# HANDOFF

Pinned upstream: `SNAPKITTYAGENT9NOVA/hologram-ai` @ `c9609c0`. Nothing from upstream is copied here.

## Landed

- Team A function catalog: `functions/A_*.md` (addressing through f32 inventory).
- Team A Alloy: `alloy/A_addressing.als`, `alloy/A_quant.als`, runner `alloy/run-A.sh`.
- Team A checks: `checks/A_*.sh` with logs from 2026-10-07.
- Team B Alloy (already on the first commit, written before the function notes): `alloy/B_*.als`.
- Team B function catalog (this continuation): `functions/B_execution.md`, `B_sampling.md`, `B_elision.md`, `B_tokenizer.md`, `B_cnl.md`, `B_session.md`, `B_conformance.md`, `B_gherkin.md`, `B_f32_inventory.md`, `B_docs.md`.
- Team B runner: `alloy/run-B.sh`. Not executed in the continuation that wrote the notes (no Alloy jar in that environment).

## Not done

- Step-body trace of every s3/s4 Then. `functions/B_gherkin.md` marks those rows "not traced".
- `checks/B_*.sh` against external authorities (tokenizer reference, ONNX Runtime parity lane).
- An Alloy log under `alloy/logs/` for the B models. Expected results are written next to each property (`expected UNSAT` / `expected SAT`); they are predictions from the model text, not a recorded run.
- Team A still owns quant layout, safetensors, ONNX, acquisition. Do not re-open those unless a B scenario cites them (`quantized_transit`, `kappa_materialization`).

## Reading order for the next pass

1. `functions/B_gherkin.md` rows marked not traced, starting with `execution_parity` and `chunked_head` (they are the numeric claims).
2. `crates/hologram-ai-conformance/tests/bdd.rs` step bodies for those scenarios.
3. Run `alloy/run-B.sh` and commit the log. Set `ALLOY_SKIP_WINDOW64=1` if the 10-bit file is too slow for the box.
