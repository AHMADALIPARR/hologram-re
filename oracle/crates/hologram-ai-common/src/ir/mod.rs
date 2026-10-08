// Copyright (c) 2026 SNAPKITTYAGENT9NOVA
// SPDX-License-Identifier: AGPL-3.0-only
pub mod dtype;
pub mod graph;
pub mod node;
pub mod op;
pub mod param;
pub mod shape;

pub use dtype::DType;
pub use graph::{AiGraph, ImportWarning, MetaValue, SemanticHint, TensorInfo, ValidationError};
pub use node::{AiNode, NodeId, TensorId};
pub use op::{AiOp, KvLayout, OpCategory, ScatterReduce};
pub use param::AiParam;
pub use shape::{canonical_vars, DimVarEntry, DimVarSource, DimVarTable};
pub use shape::{shape_from_concrete, Dim, DimExpr, DimVarId, Shape};
pub use shape::{ConstraintStore, ShapeConstraint, ShapeError};
