#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
toolchain="${JXL_RUST_TOOLCHAIN:-nightly-2026-11-01}"
target_dir="${CARGO_TARGET_DIR:-$root/Rust/target}"
destination="$root/Sources/Frameworks/JxlRust.xcframework"
sysroot="$(rustc "+$toolchain" --print sysroot)"
host="$(rustc "+$toolchain" -vV | awk '/^host:/ {print $2}')"
objcopy="$sysroot/lib/rustlib/$host/bin/llvm-objcopy"
if [[ ! -x "$objcopy" ]]; then
    echo "Install llvm-tools for $toolchain with rustup component add --toolchain $toolchain llvm-tools." >&2
    exit 1
fi
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

export IPHONEOS_DEPLOYMENT_TARGET=13.0
export MACOSX_DEPLOYMENT_TARGET=12.0

build() {
    local target="$1"
    local sdk="$2"
    SDKROOT="$(xcrun --sdk "$sdk" --show-sdk-path)" \
        cargo "+$toolchain" build --release --locked --manifest-path "$root/Rust/Cargo.toml" \
        --target-dir "$target_dir" --target "$target"
    # Apple clients link the native objects. Remove the Rust toolchain's LLVM
    # sections before creating universal archives with the Apple tools.
    "$objcopy" --strip-debug --remove-section=__LLVM,__bitcode --remove-section=__LLVM,__cmdline \
        "$target_dir/$target/release/libjxl_coder.a" "$stage/$target.a"
}

build aarch64-apple-ios iphoneos
build aarch64-apple-ios-sim iphonesimulator
build x86_64-apple-ios iphonesimulator
build aarch64-apple-darwin macosx
build x86_64-apple-darwin macosx

mkdir -p "$stage/ios" "$stage/simulator" "$stage/macos"
cp "$stage/aarch64-apple-ios.a" "$stage/ios/libjxl_rust.a"
xcrun lipo -create \
    "$stage/aarch64-apple-ios-sim.a" \
    "$stage/x86_64-apple-ios.a" \
    -output "$stage/simulator/libjxl_rust.a"
xcrun lipo -create \
    "$stage/aarch64-apple-darwin.a" \
    "$stage/x86_64-apple-darwin.a" \
    -output "$stage/macos/libjxl_rust.a"

# Xcode copies the headers of every static-library XCFramework into one shared
# include/ folder, so a top-level module.modulemap collides with other packages
# that do the same (e.g. AvifPixart). Keep ours in Headers/JxlRust/.
headers="$stage/headers"
mkdir -p "$headers/JxlRust"
cp "$root/Sources/JxlRust/include/JxlRust.h" "$root/Sources/JxlRust/include/module.modulemap" "$headers/JxlRust/"
xcodebuild -create-xcframework \
    -library "$stage/ios/libjxl_rust.a" -headers "$headers" \
    -library "$stage/simulator/libjxl_rust.a" -headers "$headers" \
    -library "$stage/macos/libjxl_rust.a" -headers "$headers" \
    -output "$stage/JxlRust.xcframework"
cp "$root/Rust/LICENSE" "$root/Rust/LICENSE-APACHE" "$stage/JxlRust.xcframework/"
mkdir -p "$(dirname "$destination")"
rm -rf "$destination"
mv "$stage/JxlRust.xcframework" "$destination"
