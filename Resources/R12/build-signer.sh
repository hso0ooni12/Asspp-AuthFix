#!/usr/bin/env bash
set -euo pipefail

# Compile MIT-licensed zsign as an arm64 iOS static library, linking the
# OpenSSL binaries provided by the pinned ForgeSign iOS integration.
zsign_repo="${RUNNER_TEMP}/zsign-r12"
forge_repo="${RUNNER_TEMP}/forgesign-r12"
git clone https://github.com/zhlynn/zsign.git "$zsign_repo"
git -C "$zsign_repo" checkout --detach 9299685bab7ef99827e06e5dfda93af747386590
git clone https://github.com/Mesutcydev/ForgeSign-iOS.git "$forge_repo"
git -C "$forge_repo" checkout --detach b4ac4d853115cb216904ba9a8df26062f11abb46

sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
cc="$(xcrun --sdk iphoneos --find clang)"
cxx="$(xcrun --sdk iphoneos --find clang++)"
build="${RUNNER_TEMP}/AssppSignerBuild"
mkdir -p "$build"

includes=(
  -I"$zsign_repo/src"
  -I"$zsign_repo/src/common"
  -I"$zsign_repo/src/third-party/zlib"
  -I"$forge_repo/vendor/openssl/include"
)
objects=()
for src in "$zsign_repo"/src/*.cpp "$zsign_repo"/src/common/*.cpp "$GITHUB_WORKSPACE"/Resources/R12/SignerBridge.cpp; do
  [[ "${src##*/}" == "zsign.cpp" ]] && continue
  obj="$build/$(basename "$src").o"
  "$cxx" -std=c++11 -O2 -fPIC -target arm64-apple-ios17.0 -isysroot "$sdk" \
    -DZSIGN_VERSION=1.0.0 "${includes[@]}" -c "$src" -o "$obj"
  objects+=("$obj")
done
for src in "$zsign_repo"/src/third-party/zlib/*.c \
  "$zsign_repo"/src/third-party/minizip/ioapi.c \
  "$zsign_repo"/src/third-party/minizip/zip.c \
  "$zsign_repo"/src/third-party/minizip/unzip.c; do
  obj="$build/$(basename "$src").o"
  "$cc" -O2 -fPIC -target arm64-apple-ios17.0 -isysroot "$sdk" \
    "${includes[@]}" -c "$src" -o "$obj"
  objects+=("$obj")
done

libtool -static -o "$build/libAssppSigner.a" "${objects[@]}"
test -s "$build/libAssppSigner.a"
test -s "$forge_repo/vendor/openssl/libcrypto.a"
test -s "$forge_repo/vendor/openssl/libssl.a"
xcrun nm -g "$build/libAssppSigner.a" | grep -F '_AssppSignIPA'
echo "R12 iOS on-device signer compiled with pinned zsign and OpenSSL"
