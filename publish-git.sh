# publish-git.sh — git backend, sourced by publish.sh
#
# Defines the functions the backend-agnostic orchestrator (publish.sh) calls.
# The orchestrator handles all file I/O; these functions only receive the
# manifest JSON content plus the files to publish.
#
# Configured by a plain KEY=VALUE file alongside this script (publish-git.conf),
# overridable via PUBLISH_GIT_CONF.

GIT_BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
git_conf="${PUBLISH_GIT_CONF:-$GIT_BACKEND_DIR/publish-git.conf}"
if [[ -f "$git_conf" ]]; then
    source "$git_conf"
fi

if [[ -z "${PUBLISH_GIT_REPO:-}" || ! -d "${PUBLISH_GIT_REPO:-}" ]]; then
    echo "Error: PUBLISH_GIT_REPO not set or not a directory (configure $git_conf)" >&2
    exit 1
fi

publish_one_file() {
    local manifest="$1"
    local key="$2"
    local file="$3"
    echo "Publishing $key: $file" >&2
    ( cd "$PUBLISH_GIT_REPO" && git add "$file" )
}

publish_one_manifest() {
    local manifest="$1"
    local date
    date=$(jq -r '.date // empty' <<< "$manifest")
    local message="Publish ${date:-manifest}"

    ( cd "$PUBLISH_GIT_REPO" && ( git diff --cached --quiet || {
        git commit -m "$message"
        git push
    } ) )
}
