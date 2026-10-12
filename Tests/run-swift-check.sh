#!/usr/bin/env bash
# Compiles Shared/*.swift (Foundation only) with Tests/ModelCheck/main.swift and runs it.
# Works on macOS (Xcode or Command Line Tools) and on Linux with a Swift toolchain.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/vf-modelcheck"
swiftc -O -o "$out" Shared/VisionModel.swift Shared/DistanceEstimator.swift Shared/SharedStore.swift Tests/ModelCheck/main.swift
"$out" Tests/vectors.json
