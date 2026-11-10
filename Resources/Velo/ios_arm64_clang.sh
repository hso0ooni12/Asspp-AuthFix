#!/bin/sh
# Force the iOS arm64 target even for compiler-probe invocations that bypass
# CMake's CFLAGS. Unicorn's CMakeLists inspects predefined macros by calling
# the raw compiler; on Intel Macs, an unwrapped probe otherwise sees x86_64
# and wrongly injects -mcx16 into arm64 iOS compilation.
exec "$(xcrun --sdk iphoneos --find clang)" -target arm64-apple-ios17.0 "$@"
