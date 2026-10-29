#!/usr/bin/env bash
# Build the small router interpreter only on GitHub for actual filesystem/UCI tests.
set -euo pipefail
fixture_root="${RUNNER_TEMP:?}/yala-ucode"
fixture_prefix="$fixture_root/install"
mkdir -p "$fixture_root"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends cmake libjson-c-dev libmd-dev
build_source() {
  local repo="$1" revision="$2" name="$3"
  mkdir -p "$fixture_root/$name"
  curl -fsSL --retry 2 "https://github.com/$repo/archive/$revision.tar.gz" |
    tar -xz --strip-components=1 -C "$fixture_root/$name"
  cmake -S "$fixture_root/$name" -B "$fixture_root/$name/build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$fixture_prefix" \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_PREFIX_PATH="$fixture_prefix" \
    -DBUILD_LUA=OFF -DBUILD_EXAMPLES=OFF
  cmake --build "$fixture_root/$name/build" --parallel 2
  cmake --install "$fixture_root/$name/build"
}
build_source openwrt/libubox da2d205a5cf3e877c45a2eec488218cbaf452e7d libubox
build_source openwrt/uci 74f6277aabffc943d026f406df57c22595134c42 uci
build_source jow-/ucode aabdeb4f5060c91c5929bf6d7af745c6aabf5ec5 ucode
echo "$fixture_prefix/bin" >> "$GITHUB_PATH"
echo "LD_LIBRARY_PATH=$fixture_prefix/lib" >> "$GITHUB_ENV"
echo 'YALA_UCODE_INTEGRATION=1' >> "$GITHUB_ENV"
