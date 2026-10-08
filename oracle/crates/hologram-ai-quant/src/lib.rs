// Copyright (c) 2026 SNAPKITTYAGENT9NOVA
// SPDX-License-Identifier: AGPL-3.0-only
//! Quantization primitives for hologram-ai.
//!
//! Provides block-quantized weight formats (Q4_0, Q8_0, etc.) with fast
//! dequantization. No IR dependency — safe to use from any crate.
//!
//! `no_std` runtime core (V&V class NS): dequantization runs on-device
//! (wasm / embedded), so this crate is `#![no_std]` + `alloc`.
#![no_std]

extern crate alloc;

/// `no_std`-safe f32 absolute value via libm (`f32::abs` is not in core
/// on all toolchains — same reason `round_f32` exists below).
#[inline(always)]
pub(crate) fn abs_f32(x: f32) -> f32 {
    libm::fabsf(x)
}

pub mod encode;
pub mod q4_0;
pub mod q8_0;
pub mod scheme;

pub use encode::encode_int8_per_channel;
pub use q4_0::{dequant_q4_0, dequant_q4_0_block, Q4_0Block, Q4_0_BLOCK_SIZE};
pub use q8_0::{dequant_q8_0, dequant_q8_0_block, Q8_0Block, Q8_0_BLOCK_SIZE};
pub use scheme::{QuantDescriptor, QuantScheme, ScaleDtype};
