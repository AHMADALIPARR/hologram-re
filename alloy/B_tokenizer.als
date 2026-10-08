-- SPDX-License-Identifier: AGPL-3.0-only
-- Team B model: native tokenizer special-token handling (eos/bos resolution, decode filter).
-- Analyzed source: hologram-ai @ c9609c0 (MIT OR Apache-2.0)
--   crates/hologram-ai-tokenizer/src/native.rs:311-338 (encode/decode), :364-399 (parse_special_tokens)
--   crates/hologram-ai/src/commands/generate.rs:307 (eos = cfg.eos or tokenizer.eos_token_id())
-- Integer ids as atoms; the BPE/unigram merge procedures are not modelled here (they are
-- specified as total functions in functions/B_tokenizer.md). Alloy checks this model, not the Rust.
module B_tokenizer

sig Id {}
one sig Id2 extends Id {}                       -- the literal default `eos_id.unwrap_or(2)`
abstract sig Content {}
one sig LtS, EndS, Unk, Pad, OtherSpecial extends Content {}   -- "<s>", "</s>", "<unk>", "<pad>", other
sig Added { id: one Id, content: one Content }  -- tokenizer.json added_tokens
one sig Tok {
  normal: set Id,                               -- ids of ordinary vocabulary pieces
  declaredEos: one Id                           -- the model's real EOS (generation_config / tokenizer_config)
}
-- parse_special_tokens: a "</s>" entry sets eos, otherwise 2; "<s>" sets bos. Later entries
-- with the same content overwrite earlier ones (loop order); modelled as "some entry".
fun eosId: one Id { (some a: Added | a.content = EndS) => { a: Added | a.content = EndS }.id else Id2 }
fun bosId: lone Id { { a: Added | a.content = LtS }.id }
fact oneEntryPerContent { all c: LtS + EndS | lone content.c }
fact addedNotNormal { no Added.id & Tok.normal }

-- decode filters bos and eos before decode_raw
fun keptByDecode[ids: set Id]: set Id { ids - eosId - bosId }

-- B-TK-1: the EOS used by generation is the model's declared EOS. Refuted whenever the
-- declared EOS is not spelled "</s>" (e.g. "<|endoftext|>", "<|im_end|>"): eos falls back to 2.
assert eosIsDeclared { eosId = Tok.declaredEos }
check eosIsDeclared for 4 expect 1

-- B-TK-2: decode never drops an ordinary vocabulary piece. Refuted when the fallback id 2 is
-- an ordinary piece: decode filters it (and generation stops on it).
assert decodeKeepsNormal { keptByDecode[Tok.normal] = Tok.normal }
check decodeKeepsNormal for 4 expect 1

-- B-TK-3: when "</s>" is an added token, decode keeps every ordinary piece.
assert decodeKeepsNormalWithEndS {
  (some a: Added | a.content = EndS) implies keptByDecode[Tok.normal] = Tok.normal
}
check decodeKeepsNormalWithEndS for 4 expect 0

pred tokNonVacuous { some Tok.normal and some a: Added | a.content = EndS }
run tokNonVacuous for 4 expect 1
