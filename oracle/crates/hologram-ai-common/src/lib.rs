// Copyright (c) 2026 SNAPKITTYAGENT9NOVA
// SPDX-License-Identifier: AGPL-3.0-only
//! hologram-ai-common (parametric rebuild): the canonical AI IR used by the
//! safetensors parametric graph builder. This trimmed crate ships only the
//! `ir` module — no lowering, execution, or external runtime dependencies.

pub mod ir;

// Flat re-exports for convenience.
pub use ir::{
    canonical_vars, shape_from_concrete, AiGraph, AiNode, AiOp, AiParam, ConstraintStore, DType,
    Dim, DimExpr, DimVarEntry, DimVarId, DimVarSource, DimVarTable, ImportWarning, KvLayout,
    MetaValue, NodeId, ScatterReduce, SemanticHint, Shape, ShapeConstraint, ShapeError, TensorId,
    TensorInfo, ValidationError,
};
