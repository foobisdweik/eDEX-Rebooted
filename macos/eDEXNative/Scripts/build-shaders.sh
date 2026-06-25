#!/usr/bin/env bash
# Offline shader compilation for the native app (Spike 0+).
#
# DECIDED: shaders are precompiled to a `.metallib` offline and bundled as a
# package resource — there is NO runtime shader compilation. This script is the
# single source of truth for producing
# macos/eDEXNative/Sources/EdexRenderingSupport/Shaders/default.metallib
# from the `.metal` sources in the same directory, pinned to the Metal 4.1
# baseline (macOS 27 toolchain floor).
#
# Run it after editing any `.metal` source, then commit the regenerated
# `default.metallib` alongside the source change.
set -euo pipefail

std="metal4.1"
shaders_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../Sources/EdexRenderingSupport/Shaders" && pwd)"
out="${shaders_dir}/default.metallib"

shopt -s nullglob
sources=("${shaders_dir}"/*.metal)
if [[ ${#sources[@]} -eq 0 ]]; then
  echo "build-shaders: no .metal sources in ${shaders_dir}" >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

airs=()
for src in "${sources[@]}"; do
  air="${workdir}/$(basename "${src%.metal}").air"
  echo "+ metal -std=${std} -c ${src}"
  xcrun --sdk macosx metal -std="${std}" -c "${src}" -o "${air}"
  airs+=("${air}")
done

echo "+ metallib -> ${out}"
xcrun --sdk macosx metallib "${airs[@]}" -o "${out}"
echo "build-shaders: wrote ${out}"
