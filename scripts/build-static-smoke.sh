#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ZVEC_DIR="$REPO_ROOT/zvec"
BUILD_DIR="$ZVEC_DIR/build"
DIST_DIR="$REPO_ROOT/dist/static"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "static smoke build is currently Linux-only" >&2
  exit 1
fi

cd "$REPO_ROOT"
git submodule update --init --recursive
bash "$REPO_ROOT/scripts/apply-zvec-static-patch.sh"

if git -C "$ZVEC_DIR" rev-parse --is-shallow-repository >/dev/null 2>&1; then
  git -C "$ZVEC_DIR" fetch --tags --unshallow 2>/dev/null || git -C "$ZVEC_DIR" fetch --tags
else
  git -C "$ZVEC_DIR" fetch --tags
fi

NPROC="$(nproc 2>/dev/null || echo 2)"
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

cmake -S "$ZVEC_DIR" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DBUILD_C_BINDINGS=ON \
  -DZVEC_C_API_STATIC=ON \
  -DBUILD_ZVEC_SHARED=OFF \
  -DBUILD_ZVEC_AILEGO_SHARED=OFF \
  -DBUILD_ZVEC_CORE_SHARED=OFF \
  -DBUILD_TOOLS=OFF

cmake --build "$BUILD_DIR" --target zvec_c_api -j "$NPROC"

internal_archives=(
  "$BUILD_DIR/lib/libzvec_c_api.a"
  "$BUILD_DIR/lib/libzvec.a"
  "$BUILD_DIR/lib/libzvec_core.a"
  "$BUILD_DIR/lib/libzvec_ailego.a"
  "$BUILD_DIR/lib/libzvec_turbo.a"
)

for archive in "${internal_archives[@]}"; do
  if [[ ! -f "$archive" ]]; then
    echo "missing expected archive: $archive" >&2
    find "$BUILD_DIR" -name '*.a' -print | sort >&2
    exit 1
  fi
done

mapfile -t all_archives < <(
  find "$BUILD_DIR/lib" "$BUILD_DIR/external/usr/local/lib" -name '*.a' -print 2>/dev/null | sort
)

other_archives=()
for archive in "${all_archives[@]}"; do
  keep=1
  for internal in "${internal_archives[@]}"; do
    if [[ "$archive" == "$internal" ]]; then
      keep=0
      break
    fi
  done
  if [[ "$keep" -eq 1 ]]; then
    other_archives+=("$archive")
  fi
done

export CGO_ENABLED=1
link_archives=("${internal_archives[@]}" "${other_archives[@]}")
export CGO_LDFLAGS="-Wl,--start-group ${link_archives[*]} -Wl,--end-group -lstdc++ -lm -ldl -lpthread -lrt"

go build \
  -tags "source source_static" \
  -trimpath \
  -ldflags="-s -w -linkmode external -extldflags '-static -static-libstdc++ -static-libgcc'" \
  -o "$DIST_DIR/zvec-static-smoke" \
  ./cmd/static-smoke

{
  echo "== archives =="
  du -h "${internal_archives[@]}" | sort -h
  echo
  echo "== binary =="
  ls -lh "$DIST_DIR/zvec-static-smoke"
  file "$DIST_DIR/zvec-static-smoke"
  echo
  echo "== dynamic dependencies =="
  if ldd "$DIST_DIR/zvec-static-smoke" 2>&1; then
    :
  fi
} | tee "$DIST_DIR/size-report.txt"

ldd_output="$(ldd "$DIST_DIR/zvec-static-smoke" 2>&1 || true)"
if grep -q "not a dynamic executable" <<<"$ldd_output"; then
  echo "static binary verified"
else
  echo "binary is not fully static" >&2
  exit 1
fi
