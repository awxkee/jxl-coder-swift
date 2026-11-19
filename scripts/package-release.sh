#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <version> <owner/repository> <output-directory>" >&2
    exit 1
fi

version="$1"
repository="$2"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Expected a release version in X.Y.Z form, got '$version'." >&2
    exit 1
fi
if [[ ! "$repository" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ || "$repository" == */. || "$repository" == */.. ]]; then
    echo "Expected a GitHub repository in owner/repository form, got '$repository'." >&2
    exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
framework="Sources/Frameworks/JxlRust.xcframework"
if [[ ! -f "$root/$framework/Info.plist" ]]; then
    echo "Missing $framework. Run scripts/build-rust-xcframework.sh first." >&2
    exit 1
fi
for notice in LICENSE LICENSE-APACHE; do
    if ! cmp -s "$root/Rust/$notice" "$root/$framework/$notice"; then
        echo "Missing or outdated $notice in $framework. Rebuild the XCFramework first." >&2
        exit 1
    fi
done

mkdir -p -- "$3"
output="$(cd -- "$3" >/dev/null && pwd -P)"
stage="$output/.package-release"
if ! mkdir "$stage"; then
    echo "Could not stage the release in $output." >&2
    exit 1
fi
trap 'rm -rf "$stage"' EXIT
for file in JxlRust.xcframework.zip JxlCoder-CocoaPods.zip Package.swift JxlCoder.podspec; do
    if [[ -e "$output/$file" || -L "$output/$file" ]]; then
        echo "Refusing to replace $output/$file. Choose a fresh output directory." >&2
        exit 1
    fi
done

(
    cd "$root/Sources/Frameworks"
    zip -q -X -r "$stage/JxlRust.xcframework.zip" JxlRust.xcframework -x '*/.DS_Store'
)
(
    cd "$root"
    zip -q -X -r "$stage/JxlCoder-CocoaPods.zip" LICENSE LICENSE-APACHE \
        Sources/JxlCoder/*.swift "$framework" -x '*/.DS_Store'
)
swift_checksum="$(swift package compute-checksum "$stage/JxlRust.xcframework.zip")"
pod_checksum="$(shasum -a 256 "$stage/JxlCoder-CocoaPods.zip" | awk '{print $1}')"

python3 - "$root" "$stage" "$version" "$repository" "$swift_checksum" "$pod_checksum" <<'PYTHON'
import re
import sys
from pathlib import Path

root, stage = map(Path, sys.argv[1:3])
version, repository, swift_checksum, pod_checksum = sys.argv[3:]
download_url = f"https://github.com/{repository}/releases/download/{version}"


def replace_once(text, pattern, replacement, label):
    updated, count = re.subn(pattern, replacement, text, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"Expected one {label} declaration, found {count}.")
    return updated


package = replace_once(
    (root / "Package.swift").read_text(),
    r'^        \.binaryTarget\(\s*name:\s*"JxlRust",[^)]*\)',
    f'''        .binaryTarget(
            name: "JxlRust",
            url: "{download_url}/JxlRust.xcframework.zip",
            checksum: "{swift_checksum}"
        )''',
    "Package.swift JxlRust binary target",
)
podspec = replace_once(
    (root / "JxlCoder.podspec").read_text(),
    r"^(    s\.version\s*= ).+$",
    rf"\g<1>'{version}'",
    "podspec version",
)
podspec = replace_once(
    podspec,
    r"^(    s\.source\s*= ).+$",
    rf"\g<1>{{ :http => '{download_url}/JxlCoder-CocoaPods.zip', :sha256 => '{pod_checksum}' }}",
    "podspec source",
)
(stage / "Package.swift").write_text(package)
(stage / "JxlCoder.podspec").write_text(podspec)
PYTHON

mv -n "$stage/JxlRust.xcframework.zip" "$stage/JxlCoder-CocoaPods.zip" \
    "$stage/Package.swift" "$stage/JxlCoder.podspec" "$output/"
echo "Release archives and package manifests written to $output"
