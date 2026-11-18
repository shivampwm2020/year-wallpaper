#!/usr/bin/env bash
# Build YearWallpaper from source into ./bin/YearWallpaper
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="bin/YearWallpaper"
mkdir -p bin

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found." >&2
  echo "Install Apple's Command Line Tools:  xcode-select --install" >&2
  exit 1
fi

echo "Building $OUT ..."
swiftc -O Sources/YearWallpaper.swift -o "$OUT"

echo "Done. Binary at $(pwd)/$OUT"
echo
"$OUT" --preview /tmp/year-wallpaper-preview.png --size 2560x1440
