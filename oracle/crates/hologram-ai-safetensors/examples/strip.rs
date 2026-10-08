// Copyright (c) 2026 SNAPKITTYAGENT9NOVA
// SPDX-License-Identifier: AGPL-3.0-only
//! Strip a .safetensors checkpoint down to its tensor manifest:
//! name, dtype, shape, and byte offsets — the exact input the parametric
//! builder consumes. Works for any safetensors file, regardless of whether
//! its architecture family is in the builder registry.

use serde_json::{json, Value};

fn dtype_bytes(dtype: &str) -> u64 {
    match dtype {
        "BOOL" | "U8" | "I8" => 1,
        "I16" | "U16" | "F16" | "BF16" => 2,
        "I32" | "U32" | "F32" => 4,
        "F64" | "I64" | "U64" => 8,
        _ => 0,
    }
}

fn main() {
    let path = std::env::args().nth(1).expect("usage: strip <model.safetensors>");
    let bytes = std::fs::read(&path).expect("read safetensors");

    let header_len =
        u64::from_le_bytes(bytes[0..8].try_into().expect("header len")) as usize;
    let header: Value =
        serde_json::from_slice(&bytes[8..8 + header_len]).expect("parse header JSON");
    let obj = header.as_object().expect("header is an object");

    let mut names: Vec<&String> =
        obj.keys().filter(|k| k.as_str() != "__metadata__").collect();
    names.sort();

    let mut total_elems: u64 = 0;
    let mut total_bytes: u64 = 0;
    let manifest: Vec<Value> = names
        .iter()
        .map(|name| {
            let t = &obj[*name];
            let dtype = t["dtype"].as_str().unwrap_or("?");
            let shape: Vec<u64> =
                t["shape"].as_array().unwrap().iter().map(|d| d.as_u64().unwrap()).collect();
            let offsets = t["data_offsets"].as_array().unwrap();
            let (start, end) = (offsets[0].as_u64().unwrap(), offsets[1].as_u64().unwrap());
            let elems: u64 = shape.iter().product();
            total_elems += elems;
            total_bytes += end - start;
            json!({
                "name": name,
                "dtype": dtype,
                "shape": shape,
                "elements": elems,
                "data_offsets": [start, end],
                "bytes_per_element": dtype_bytes(dtype),
            })
        })
        .collect();

    println!(
        "{}",
        json!({
            "file": path,
            "tensors": manifest.len(),
            "total_elements": total_elems,
            "total_data_bytes": total_bytes,
            "manifest": manifest,
        })
    );
    eprintln!(
        "stripped {}: {} tensors, {} elements, {} data bytes",
        path, manifest.len(), total_elems, total_bytes
    );
}
