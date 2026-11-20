// Copyright (c) Radzivon Bartoshyk 11/2026. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

#![feature(allocator_ext, f16)]

#[repr(i32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Error {
    InvalidInput = 1,
    OutOfMemory,
    Decode,
    Encode,
    Unsupported,
    MissingGainMap,
    Panic,
}

impl From<std::collections::TryReserveError> for Error {
    fn from(_: std::collections::TryReserveError) -> Self {
        Self::OutOfMemory
    }
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let message = match self {
            Self::InvalidInput => "Invalid JPEG XL input or options",
            Self::OutOfMemory => "Could not allocate codec memory",
            Self::Decode => "JPEG XL decoding failed",
            Self::Encode => "JPEG XL encoding failed",
            Self::Unsupported => "Unsupported JPEG XL feature or color encoding",
            Self::MissingGainMap => "The JPEG XL image has no gain map",
            Self::Panic => "The JPEG XL codec encountered an unexpected error",
        };
        f.write_str(message)
    }
}

impl std::error::Error for Error {}

pub type Result<T> = std::result::Result<T, Error>;

pub mod decode;
pub mod encode;
mod ffi;
pub mod gainmap;
#[cfg(all(target_arch = "aarch64", target_feature = "neon"))]
mod neon;
mod premultiply;
