#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PATCH_FILE="$REPO_ROOT/scripts/patches/zvec-c-api-static.patch"
ZVEC_DIR="$REPO_ROOT/zvec"

if [[ ! -d "$ZVEC_DIR" ]]; then
  echo "zvec submodule is missing. Run: git submodule update --init --recursive" >&2
  exit 1
fi

if grep -q "ZVEC_C_API_STATIC" "$ZVEC_DIR/src/binding/c/CMakeLists.txt"; then
  echo "zvec static C API patch already applied"
  exit 0
fi

git -C "$ZVEC_DIR" apply "$PATCH_FILE"
echo "applied zvec static C API patch"
