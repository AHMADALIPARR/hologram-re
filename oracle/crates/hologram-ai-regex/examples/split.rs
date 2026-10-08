// Copyright (c) 2026 SNAPKITTYAGENT9NOVA
// SPDX-License-Identifier: AGPL-3.0-only
//! CLI: split text into pre-token fragments with a regex pattern.
//! Usage: split [pattern] <text>  (default pattern: GPT-2 split)

use hologram_ai_regex::{RegexSplitter, GPT2_SPLIT_PATTERN};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (pattern, text) = match args.len() {
        0 => {
            eprintln!("usage: split [pattern] <text>");
            std::process::exit(1);
        }
        1 => (GPT2_SPLIT_PATTERN.to_string(), args[0].clone()),
        _ => (args[0].clone(), args[1..].join(" ")),
    };

    let splitter = RegexSplitter::new(&pattern);
    if !splitter.is_compiled() {
        eprintln!("warning: pattern failed to compile; passing text through");
    }
    for frag in splitter.split(&text) {
        println!("{frag:?}");
    }
}
