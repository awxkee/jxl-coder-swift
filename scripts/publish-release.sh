#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || ! "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Usage: $0 <X.Y.Z> <packaged-release-directory>" >&2
    exit 1
fi

version="$1"
release_dir="$2"
tag_ref="refs/tags/$version"
source_commit="$(git rev-parse HEAD)"
assets=(JxlRust.xcframework.zip JxlCoder-CocoaPods.zip)

fail() {
    echo "$*" >&2
    exit 1
}

for file in Package.swift JxlCoder.podspec "${assets[@]}"; do
    [[ -s "$release_dir/$file" ]] || fail "Missing release file: $release_dir/$file"
done

index_dir="$(mktemp -d)"
trap 'rm -rf "$index_dir"' EXIT
release_tree="$(
    export GIT_INDEX_FILE="$index_dir/index"
    git read-tree "$source_commit"
    for file in Package.swift JxlCoder.podspec; do
        blob="$(git hash-object -w "$release_dir/$file")"
        git update-index --add --cacheinfo "100644,$blob,$file"
    done
    git write-tree
)"

# Recreate the same commit when rerunning the publish job with the same archives.
release_date="$(git show -s --format=%cI "$source_commit")"
release_commit="$(
    GIT_AUTHOR_NAME='github-actions[bot]' GIT_COMMITTER_NAME='github-actions[bot]' \
    GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com' \
    GIT_COMMITTER_EMAIL='41898282+github-actions[bot]@users.noreply.github.com' \
    GIT_AUTHOR_DATE="$release_date" GIT_COMMITTER_DATE="$release_date" \
        git -c commit.gpgsign=false commit-tree "$release_tree" -p "$source_commit" \
        -m "Prepare JxlCoder $version"
)"
remote_tag="$(git ls-remote --refs origin "$tag_ref" | cut -f 1)"
if [[ -n "$remote_tag" && "$remote_tag" != "$release_commit" ]]; then
    fail "Tag $version already points to a different commit."
fi

if ! release="$(gh release view "$version" --json isDraft,targetCommitish,assets)"; then
    [[ -z "$remote_tag" ]] || fail "Tag $version already exists without a matching release."
    gh release create "$version" --draft --target "$source_commit" --title "$version" --generate-notes
    release="$(gh release view "$version" --json isDraft,targetCommitish,assets)"
fi

is_draft="$(jq -r '.isDraft' <<< "$release")"
draft_target="$(jq -r '.targetCommitish' <<< "$release")"
if [[ "$is_draft" == true && "$draft_target" != "$source_commit" ]]; then
    fail "Draft release $version targets a different source revision."
fi
if [[ "$is_draft" == false && -z "$remote_tag" ]]; then
    fail "Release $version is already published."
fi

for asset in "${assets[@]}"; do
    expected_digest="sha256:$(sha256sum "$release_dir/$asset" | cut -d ' ' -f 1)"
    uploaded_asset="$(jq -c --arg asset "$asset" '.assets[] | select(.name == $asset)' <<< "$release")"
    if [[ -z "$uploaded_asset" && "$is_draft" == true ]]; then
        gh release upload "$version" "$release_dir/$asset"
        uploaded_asset="$(gh release view "$version" --json assets |
            jq -c --arg asset "$asset" '.assets[] | select(.name == $asset)')"
    fi
    jq -e --arg digest "$expected_digest" \
        'select(.state == "uploaded" and .digest == $digest)' <<< "$uploaded_asset" >/dev/null ||
        fail "Release $version has a missing or different $asset."
done

if [[ "$is_draft" == true ]]; then
    git push origin "$release_commit:$tag_ref"
    gh release edit "$version" --draft=false --verify-tag
fi
