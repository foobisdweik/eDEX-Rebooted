#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${APP_DIR}/../.." && pwd)"
FFI_DIR="${REPO_ROOT}/crates/edex-ffi"
RUST_LIB="${FFI_DIR}/target/release/libedex_ffi.dylib"
GENERATED_DIR="${APP_DIR}/Generated"

cd "${FFI_DIR}"
cargo build --release
mkdir -p "${GENERATED_DIR}"
cargo run --bin uniffi-bindgen -- generate \
  --library "${RUST_LIB}" \
  --language swift \
  --out-dir "${GENERATED_DIR}"

cd "${APP_DIR}"
swift run eDEXNative
