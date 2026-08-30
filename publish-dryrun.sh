# publish-dryrun.sh — dry-run backend, sourced by publish.sh
# Prints the actions that would be taken without modifying anything.

publish_one_file() {
    local manifest="$1"
    local key="$2"
    local file="$3"
    echo "[DRY RUN] Would publish $key: $file" >&2
}

publish_one_manifest() {
    local manifest="$1"
    local date
    date=$(jq -r '.date // empty' <<< "$manifest")
    local message="Publish ${date:-manifest}"
    echo "[DRY RUN] Would commit/publish manifest ($message)" >&2
}
