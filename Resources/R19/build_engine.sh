#!/usr/bin/env bash
set -euo pipefail
core_dir="$1"
output_dir="$2"
mkdir -p "$output_dir"
python3 Resources/R19/prepare_core.py "$core_dir/fpcore.c"

# Native bounds/failure checks on the runner, with no Apple account or license.
clang -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer \
  -Werror=implicit-function-declaration -I "$core_dir" -I Resources/R19 \
  Resources/R19/DirectFairPlayed.c Resources/R19/NativeChecks.c \
  -o "$output_dir/native-checks"
"$output_dir/native-checks" | tee "$output_dir/direct-engine-checks.log"

ios_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$ios_sdk" \
  -miphoneos-version-min=17.0 -O2 -Werror=implicit-function-declaration \
  -I "$core_dir" -I Resources/R19 -c Resources/R19/DirectFairPlayed.c \
  -o "$output_dir/DirectFairPlayed.o"
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$ios_sdk" \
  -miphoneos-version-min=17.0 -O2 -fobjc-arc \
  -c Resources/R19/InstalledBundle.m -o "$output_dir/InstalledBundle.o"
xcrun ar rcs "$output_dir/libAssppDirectFairPlayed.a" \
  "$output_dir/DirectFairPlayed.o" "$output_dir/InstalledBundle.o"
xcrun nm -gU "$output_dir/libAssppDirectFairPlayed.a" > "$output_dir/direct-exports.txt"
for symbol in AssppFPInspect AssppFPProcess AssppFPResolveInstalled; do
  grep -Eq "[[:space:]]_${symbol}$" "$output_dir/direct-exports.txt"
done
