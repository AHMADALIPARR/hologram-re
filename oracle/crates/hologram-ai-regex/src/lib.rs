// Copyright (c) 2026 SNAPKITTYAGENT9NOVA
// SPDX-License-Identifier: AGPL-3.0-only
//! Standalone regex pre-tokenizer, stripped out of the hologram-ai tokenizer.
//!
//! This is the "regex" heart of BPE tokenization: the GPT-2 / LLaMA-3 style
//! split that chops raw text into pre-token fragments before merge rules run.
//! The splitting logic is taken verbatim from `BpeEncoder::split_fragments`
//! in the original `hologram-ai-tokenizer` crate.

#![no_std]

extern crate alloc;

use alloc::vec::Vec;

/// GPT-2 style pre-tokenizer split pattern, in the look-around-free form that
/// `regex_automata` can compile (the classic pattern's `\s+(?!\S)` uses a
/// negative look-ahead, which regex-automata does not support — the original
/// code's `.ok()` fallback would silently pass text through unsplit).
pub const GPT2_SPLIT_PATTERN: &str = r"'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+";

/// Compiled regex splitter. Mirrors the original construction:
/// the pattern is compiled once with `regex_automata::meta::Regex`,
/// and a pattern that fails to compile leaves the splitter in the
/// pass-through state (`split` returns the whole text).
pub struct RegexSplitter {
    split_re: Option<regex_automata::meta::Regex>,
}

impl RegexSplitter {
    /// Compile `pattern` once. A pattern that fails to compile is not an
    /// error here — it falls back to pass-through, exactly like the original.
    pub fn new(pattern: &str) -> Self {
        let split_re = regex_automata::meta::Regex::new(pattern).ok();
        Self { split_re }
    }

    /// Whether the pattern compiled successfully.
    pub fn is_compiled(&self) -> bool {
        self.split_re.is_some()
    }

    /// Split `text` into pre-token fragments using the compiled regex,
    /// falling back to the whole text when no pattern compiled.
    /// Verbatim from `BpeEncoder::split_fragments`.
    pub fn split<'t>(&self, text: &'t str) -> Vec<&'t str> {
        match &self.split_re {
            Some(re) => re.find_iter(text).map(|m| &text[m.range()]).collect(),
            None => alloc::vec![text],
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::vec;

    #[test]
    fn gpt2_split_matches_original_behavior() {
        let splitter = RegexSplitter::new(GPT2_SPLIT_PATTERN);
        assert!(splitter.is_compiled());
        let frags = splitter.split("Hello, world! It's 2026.");
        assert_eq!(
            frags,
            vec![
                "Hello", ",", " world", "!", " It", "'s", " 2026", "."
            ]
        );
    }

    #[test]
    fn bad_pattern_falls_through() {
        let splitter = RegexSplitter::new("([");
        assert!(!splitter.is_compiled());
        assert_eq!(splitter.split("abc"), vec!["abc"]);
    }

    #[test]
    fn empty_text_yields_no_fragments() {
        let splitter = RegexSplitter::new(GPT2_SPLIT_PATTERN);
        assert!(splitter.split("").is_empty());
    }
}
