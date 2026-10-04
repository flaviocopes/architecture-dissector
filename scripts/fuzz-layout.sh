#!/bin/sh
# Lays out 400 random architectures at every level, 300 random flows and 300 random data schemas, and checks that
# every card is placed and no cards or boxes overlap.
# Usage: scripts/fuzz-layout.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/fuzz-layout"
mkdir -p "$(dirname "$OUT")"
find "$ROOT/Blueprint" -name '*.swift' ! -name BlueprintApp.swift -print0 |
  xargs -0 swiftc -O -swift-version 6 -parse-as-library "$ROOT/scripts/fuzz-layout.swift" -o "$OUT"
"$OUT"
