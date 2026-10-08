// Copyright (c) 2026 SNAPKITTYAGENT9NOVA
// SPDX-License-Identifier: AGPL-3.0-only
// Drain a safetensors checkpoint into its parametric decoder graph.
use hologram_ai_common::ir::shape::DimExpr;
use hologram_ai_safetensors::build_graph_from_safetensors;
use std::collections::HashMap;

fn main() {
    let dir = std::env::args().nth(1).expect("usage: drain <fixture-dir>");
    let config = std::fs::read_to_string(format!("{dir}/config.json")).unwrap();
    let weights = std::fs::read(format!("{dir}/model.safetensors")).unwrap();

    let graph = build_graph_from_safetensors(&config, &[&weights[..]])
        .expect("graph build failed");

    println!("graph: {}", graph.name);
    println!("nodes: {}", graph.nodes.len());
    println!("inputs: {:?} -> outputs: {:?}", graph.input_names, graph.output_names);
    println!("tensors: {}", graph.tensor_info.len());

    let mut by_dtype: HashMap<String, (usize, u64)> = HashMap::new();
    for info in graph.tensor_info.values() {
        let elems: u64 = info.shape.iter().map(|d| match d {
            DimExpr::Concrete(n) => *n,
            _ => 0,
        }).product();
        let e = by_dtype.entry(format!("{:?}", info.logical_dtype)).or_insert((0, 0));
        e.0 += 1;
        e.1 += elems;
    }
    let mut total = 0u64;
    let mut rows: Vec<_> = by_dtype.iter().collect();
    rows.sort();
    for (dtype, (n, elems)) in rows {
        println!("  {dtype}: {n} tensors, {elems} elements");
        total += elems;
    }
    println!("total elements: {total}");

    let mut by_op: HashMap<String, usize> = HashMap::new();
    for node in &graph.nodes {
        *by_op.entry(format!("{:?}", node.op)).or_insert(0) += 1;
    }
    let mut ops: Vec<_> = by_op.iter().collect();
    ops.sort();
    println!("ops:");
    for (op, n) in ops {
        let short = op.split('(').next().unwrap_or(op);
        println!("  {short}: {n}");
    }

    if !graph.warnings.is_empty() {
        println!("warnings:");
        for w in &graph.warnings {
            println!("  - {w:?}");
        }
    }
    let mut names: Vec<&String> = graph.tensor_names.values().collect();
    names.sort();
    println!("tensor sample: {:?}", &names[..names.len().min(5)]);
}
