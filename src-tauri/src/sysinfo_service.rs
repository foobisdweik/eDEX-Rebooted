//! Compatibility re-export for the JS wire-shape contract tests and native panel code.
//!
//! The implementation now lives in `edex-core` so it can be reused by the
//! future Swift/AppKit app without any Tauri dependency.

pub use edex_core::sysinfo::*;
