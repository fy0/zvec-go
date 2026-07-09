#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ZVEC_DIR="$REPO_ROOT/zvec"
BUILD_DIR="$ZVEC_DIR/build"
DIST_DIR="$REPO_ROOT/dist/static"
STATIC_VENDOR_PLATFORM="linux_amd64_static"
STATIC_VENDOR_DIR="$DIST_DIR/vendor"
STATIC_VENDOR_LIB_DIR="$STATIC_VENDOR_DIR/$STATIC_VENDOR_PLATFORM"
STATIC_VENDOR_INCLUDE_DIR="$STATIC_VENDOR_DIR/include/zvec"
STATIC_VENDOR_ARCHIVE_NAME="zvec-libs-linux-x64-static.tar.gz"
STATIC_VENDOR_ARCHIVE="$DIST_DIR/$STATIC_VENDOR_ARCHIVE_NAME"
TEMP_LIB_CREATED=0

cleanup() {
  if [[ "$TEMP_LIB_CREATED" -eq 1 ]]; then
    rm -rf "$REPO_ROOT/lib"
  fi
}
trap cleanup EXIT

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

mkdir -p "$STATIC_VENDOR_LIB_DIR" "$STATIC_VENDOR_INCLUDE_DIR"
vendor_static_archive="$STATIC_VENDOR_LIB_DIR/libzvec_c_api_static.a"
rm -f "$vendor_static_archive"
{
  echo "CREATE $vendor_static_archive"
  for archive in "${link_archives[@]}"; do
    echo "ADDLIB $archive"
  done
  echo "SAVE"
  echo "END"
} | ar -M
ranlib "$vendor_static_archive"
cp "$ZVEC_DIR/src/include/zvec/c_api.h" "$STATIC_VENDOR_INCLUDE_DIR/"

(
  cd "$STATIC_VENDOR_DIR"
  tar -czf "$STATIC_VENDOR_ARCHIVE" .
)
(
  cd "$DIST_DIR"
  sha256sum "$STATIC_VENDOR_ARCHIVE_NAME" > "$STATIC_VENDOR_ARCHIVE_NAME.sha256"
)

go build \
  -tags "source source_static" \
  -trimpath \
  -ldflags="-s -w -linkmode external -extldflags '-static -static-libstdc++ -static-libgcc'" \
  -o "$DIST_DIR/zvec-static-smoke" \
  ./cmd/static-smoke

if [[ -e "$REPO_ROOT/lib" ]]; then
  echo "lib/ already exists; skipping vendor_static smoke build" >&2
else
  TEMP_LIB_CREATED=1
  mkdir -p "$REPO_ROOT/lib"
  cp -R "$STATIC_VENDOR_DIR/." "$REPO_ROOT/lib/"

  go build \
    -tags "vendor_static" \
    -trimpath \
    -ldflags="-s -w -linkmode external -extldflags '-static -static-libstdc++ -static-libgcc'" \
    -o "$DIST_DIR/zvec-vendor-static-smoke" \
    ./cmd/static-smoke
fi

{
  echo "== archives =="
  du -h "${internal_archives[@]}" | sort -h
  echo
  echo "== vendor static archive =="
  du -h "$vendor_static_archive" "$STATIC_VENDOR_ARCHIVE"
  cat "$STATIC_VENDOR_ARCHIVE.sha256"
  echo
  echo "== source static binary =="
  ls -lh "$DIST_DIR/zvec-static-smoke"
  file "$DIST_DIR/zvec-static-smoke"
  echo
  if [[ -f "$DIST_DIR/zvec-vendor-static-smoke" ]]; then
    echo "== vendor static binary =="
    ls -lh "$DIST_DIR/zvec-vendor-static-smoke"
    file "$DIST_DIR/zvec-vendor-static-smoke"
    echo
  fi
  echo "== source static dynamic dependencies =="
  if ldd "$DIST_DIR/zvec-static-smoke" 2>&1; then
    :
  fi
  if [[ -f "$DIST_DIR/zvec-vendor-static-smoke" ]]; then
    echo
    echo "== vendor static dynamic dependencies =="
    if ldd "$DIST_DIR/zvec-vendor-static-smoke" 2>&1; then
      :
    fi
  fi
} | tee "$DIST_DIR/size-report.txt"

verify_static_binary() {
  local binary="$1"
  local ldd_output
  ldd_output="$(ldd "$binary" 2>&1 || true)"
  if grep -q "not a dynamic executable" <<<"$ldd_output"; then
    echo "static binary verified: $binary"
  else
    echo "binary is not fully static: $binary" >&2
    exit 1
  fi
}

verify_static_binary "$DIST_DIR/zvec-static-smoke"
if [[ -f "$DIST_DIR/zvec-vendor-static-smoke" ]]; then
  verify_static_binary "$DIST_DIR/zvec-vendor-static-smoke"
fi
