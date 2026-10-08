// Copyright (c) 2026 SNAPKITTYAGENT9NOVA
// SPDX-License-Identifier: AGPL-3.0-only
use hologram_ai_common::ir::param::AiParam;
use hologram_ai_common::ir::{
    dtype::DType,
    graph::{AiGraph, TensorInfo},
    node::{AiNode, TensorId},
    op::AiOp,
    shape::{DimExpr, Shape},
};
use std::collections::HashMap;

pub struct GraphBuilder {
    graph: AiGraph,
    next_id: u32,
}

impl GraphBuilder {
    pub fn new(name: String) -> Self {
        Self {
            graph: AiGraph {
                name,
                nodes: Vec::new(),
                inputs: Vec::new(),
                outputs: Vec::new(),
                input_names: Vec::new(),
                output_names: Vec::new(),
                params: HashMap::new(),
                tensor_info: HashMap::new(),
                metadata: HashMap::new(),
                warnings: Vec::new(),
                dim_vars: Default::default(),
                shape_constraints: Default::default(),
                subgraphs: HashMap::new(),
                tensor_names: HashMap::new(),
                topo_cache: Default::default(),
            },
            next_id: 1,
        }
    }

    pub fn register_var(&mut self, name: &str) -> DimExpr {
        DimExpr::Var(self.graph.dim_vars.intern(name))
    }

    pub fn add_tensor(&mut self, name: &str, dtype: DType, shape: Vec<DimExpr>) -> TensorId {
        let id = self.next_id;
        self.next_id += 1;
        self.graph.tensor_names.insert(id, name.to_string());

        let mut shape_vec = Shape::new();
        for dim in shape {
            shape_vec.push(dim);
        }
        self.graph
            .tensor_info
            .insert(id, TensorInfo::new(dtype, shape_vec));
        id
    }

    pub fn add_input(&mut self, name: &str, dtype: DType, shape: Vec<DimExpr>) -> TensorId {
        let id = self.add_tensor(name, dtype, shape);
        self.graph.inputs.push(id);
        self.graph.input_names.push(name.to_string());
        id
    }

    pub fn add_output(&mut self, id: TensorId, name: &str) {
        self.graph.outputs.push(id);
        self.graph.output_names.push(name.to_string());
    }

    pub fn add_param(
        &mut self,
        name: &str,
        dtype: DType,
        shape: Vec<DimExpr>,
        param: AiParam,
    ) -> TensorId {
        let id = self.add_tensor(name, dtype, shape);
        self.graph.params.insert(id, param);
        id
    }

    pub fn add_node(&mut self, op: AiOp, inputs: Vec<TensorId>, outputs: Vec<TensorId>) {
        let node_id = self.next_id;
        self.next_id += 1;
        self.graph
            .nodes
            .push(AiNode::new(node_id, op, inputs, outputs));
    }

    pub fn build(self) -> AiGraph {
        self.graph
    }
}
