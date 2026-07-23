#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "USAGE: $(basename "$0") AOSP-SRC [TAG]"
    exit 1
}

[[ "$#" -lt 1 ]] && usage

src=$1
tag=${2:-}
history_depth=${PATCH_HISTORY_DEPTH:-256}

if [[ -z "$tag" ]]; then
    echo 'detect AOSP tag from manifest'
    tag=$(basename "$(xmllint --xpath 'string(/manifest/default/@revision)' \
        "$src/.repo/manifests/default.xml")")
fi

patch_root=$(dirname "$(realpath "$0")")/$tag
if [[ ! -d "$patch_root" ]]; then
    echo "patches for $tag not exist"
    exit 1
fi

if ! [[ "$history_depth" =~ ^[1-9][0-9]*$ ]]; then
    echo "invalid PATCH_HISTORY_DEPTH: $history_depth"
    exit 1
fi

echo "===== AOSP SRC: $src"
echo "===== AOSP TAG: $tag"
echo "===== HISTORY DEPTH: $history_depth"

failed=0
while IFS= read -r patch_directory; do
    project=$(realpath --relative-to="$patch_root" "$patch_directory")
    repo="$src/$project"
    echo
    echo "verify project: $project"

    if [[ ! -d "$repo/.git" ]]; then
        echo "*****[ERROR]***** source repository not found: $repo"
        failed=1
        continue
    fi

    # Stable patch IDs compare the actual diff while ignoring commit metadata.
    history=$(git -C "$repo" log -p --no-merges --max-count="$history_depth" \
        --format='commit %H' | git patch-id --stable)

    while IFS= read -r patch; do
        patch_id=$(git patch-id --stable <"$patch" | awk 'NR == 1 { print $1 }')
        if [[ -z "$patch_id" ]]; then
            echo "*****[ERROR]***** cannot calculate patch ID: $(basename "$patch")"
            failed=1
            continue
        fi

        commit=$(awk -v expected="$patch_id" '$1 == expected { print $2; exit }' <<<"$history")
        if [[ -z "$commit" ]]; then
            echo "*****[ERROR]***** missing: $(basename "$patch")"
            failed=1
        else
            echo "present: $(basename "$patch") commit=$commit"
        fi
    done < <(find "$patch_directory" -maxdepth 1 -type f -name '*.patch' | sort)
done < <(
    find "$patch_root" -type f -name '*.patch' -printf '%h\n' | sort -u
)

if [[ "$failed" -ne 0 ]]; then
    echo 'patch verification failed'
    exit 2
fi

echo
echo 'patch verification passed'
