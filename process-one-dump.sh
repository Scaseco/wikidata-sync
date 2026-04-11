#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

GROOVY_SCRIPT="$SCRIPT_DIR/wikidata-release-status.groovy"
# NQPATCH="$SCRIPT_DIR/nqpatch"
NQPATCH="nqpatch"

CONF_FILE="./wikidata-sync.conf.json"

show_usage() {
    echo "Usage: $0 [--init]" >&2
    echo "  --init    Initialize state file with empty JSON" >&2
    echo "  (no args) Process the next available Wikidata dump" >&2
    exit 1
}

# Download a file into a given directory and return its filename
# XXX Perhaps separate filename retrieval from download?
resolve_filename() {
    local url="$1"
    # Get filename from header
    local filename=$(curl -s -I "$url" | grep -oP 'filename=\K[^;]+')

    # Fallback to URL path if not found
    filename=${filename:-$(basename "$url")}

    # Optional: Remove special characters
    # filename=${filename//[^a-zA-Z0-9._-]/}

    echo "$filename"
}

download_dump() {
    local url="$1"
    local output_path="$2"
    
    # Get filename from header
    local filename=$(resolve_filename "$url")

    wget -c -P "$output_path" "$url"
    echo "$filename"
}

if [[ "${1:-}" == "--init" ]]; then
    [ ! -f "$CONF_FILE" ] || { echo "Statefile already exists"; exit 1; }
    echo "{ \"repo\": \"https://dumps.wikimedia.org/wikidatawiki/entities/\", \"publishFolder\": \"publish\" }" | jq '.' > "$CONF_FILE"
    echo "Initialized $CONF_FILE" >&2
    exit 0
fi

if [[ -n "${1:-}" ]]; then
    show_usage
fi

# Begin of readState
if [[ ! -f "$CONF_FILE" ]]; then
    echo "Error: State file not found. Run with --init first." >&2
    exit 1
fi

confJson=$(cat "$CONF_FILE")

REPO_URL=$(jq -r '.repo // ""' <<< "$confJson")
PUBLISH_FOLDER=$(jq -r '.publishFolder // ""' <<< "$confJson")
SORT_OPTS==$(jq -r '.sortOptions // ""' <<< "$confJson")

echo "Repo URL: $REPO_URL" >&2

# Publish folder must be configured
[ -n "$PUBLISH_FOLDER" ] || { echo "publishFolder key not set in state file." >&2 ; exit 1; }
mkdir -p "$PUBLISH_FOLDER"
[ -d "$PUBLISH_FOLDER" ] || { echo "Not a directory: $PUBLISH_FOLDER" >&2 ; exit 1; }

LATEST_STATE_FILE="$PUBLISH_FOLDER/publish-latest.json"
[[ ! -e latest.json || -L latest.json ]] || { echo "Error: latest.json must be a symlink or absent" >&2; exit 1; }

PUBLISH_OLD_STATE_FILENAME=""
if [ -f "$LATEST_STATE_FILE" ]; then
    stateJson=$(cat "$LATEST_STATE_FILE")
    PUBLISH_OLD_STATE_FILENAME=$(readlink "$LATEST_STATE_FILE")
else
    stateJson="{}"
fi

OLD_DATE=$(jq -r '.date // ""' <<< "$stateJson")
[[ -z "$OLD_DATE" || "$OLD_DATE" == "null" ]] && OLD_DATE=""
OLD_SORTED_FILENAME=$(jq -r '.dump.filename // ""'<<< "$stateJson")
[[ -z "$OLD_SORTED_FILENAME" || "$OLD_SORTED_FILENAME" == "null" ]] && OLD_SORTED_FILENAME=""

# End of readState

# Begin of fetch wikidata release state

if [[ -n "$OLD_DATE" ]]; then
    response=$("$GROOVY_SCRIPT" "$REPO_URL" --since "$OLD_DATE")
else
    response=$("$GROOVY_SCRIPT" "$REPO_URL")
fi

count=$(echo "$response" | jq '.["truthy-BETA"] | length' 2>/dev/null) || count=0

if [[ "$count" -eq 0 ]]; then
    echo "No new dumps available" >&2
    # No new dumps available
    exit 1
fi

first_entry=$(echo "$response" | jq '.["truthy-BETA"][0]' 2>/dev/null)

NEW_DATE=$(echo "$first_entry" | jq -r '.date' 2>/dev/null)
NEW_URL=$(echo "$first_entry" | jq -r '.url' 2>/dev/null)
NEW_YEAR="${NEW_DATE:0:4}"

# End of fetch wikidata release state

echo "Processing dump: $NEW_DATE" >&2
echo "URL: $NEW_URL" >&2

orig_dir="truthy-BETA/$NEW_YEAR/origs"
dump_dir="truthy-BETA/$NEW_YEAR/dumps"
mkdir -p "$orig_dir"
mkdir -p "$dump_dir"

orig_filename=$(download_dump "$NEW_URL" "$orig_dir")
orig_path="$orig_dir/$orig_filename"
echo "Downloaded: $orig_path" >&2

# local sorted_filename="${base_name}.sorted${ext}"
sorted_filename=$(echo "$orig_filename" | sed -E 's|^(.*)(.nt.bz2)$|\1.sorted\2|')
sorted_path="$dump_dir/$sorted_filename"
echo "Sorted file: $sorted_path" >&2

if [ ! -f "$sorted_path" ]; then
    echo "Sorting $orig_path..." >&2
    "$NQPATCH" track sort "$orig_path" "$sorted_path" $SORT_OPTS
    echo "Sort complete" >&2
else
    echo "Already sorted: $sorted_path <- $orig_path" >&2
fi

json_obj='{"date": "'$NEW_DATE'"}'


if [ -n "$PUBLISH_OLD_STATE_FILENAME" ]; then
    echo "$OLD_DATE --- $PUBLISH_OLD_STATE_FILENAME"
    json_obj=$(echo "$json_obj" | \
        jq --arg d "$OLD_DATE" \
           --arg p "$PUBLISH_OLD_STATE_FILENAME" \
           '. + {prevDate: $d, prevPublishFile: $p}')
fi

json_obj=$(echo "$json_obj" | \
    jq --arg f "$orig_path" \
       --arg s "$orig_path.sha1" \
       '. + {orig: {filename: $f, sha1: $s}}')

json_obj=$(echo "$json_obj" | \
    jq --arg f "$sorted_path" \
       --arg s "$sorted_path.sha1" \
       --arg o "$sorted_path.sha1-original" \
       '. + {dump: {filename: $f, sha1: $s, "sha1-original": $o}}')

if [[ -n "$OLD_DATE" && -n "$OLD_SORTED_FILENAME" ]]; then
    old_year="${OLD_DATE:0:4}"
    diff_dir="truthy-BETA/$old_year/diffs"
    mkdir -p "$diff_dir"

    diff_filename="wikidata-${OLD_DATE}-to-${NEW_DATE}-truthy-BETA.sorted.rdfp.bz2"
    diff_path="$diff_dir/$diff_filename"

    if [ ! -f "$diff_path" ]; then
        echo "Creating diff: $diff_path" >&2
        echo "  from: $OLD_SORTED_FILENAME" >&2
        echo "  to:   $sorted_path" >&2
        "$NQPATCH" track create "$OLD_SORTED_FILENAME" "$sorted_path" "$diff_path"
        echo "Diff complete" >&2
    else
        echo "Already diffed: $diff_path" >&2
    fi

    json_obj=$(echo "$json_obj" | \
        jq --arg f "$diff_path" \
           --arg s "$diff_path.sha1" \
           --arg from "$diff_path.sha1-from" \
           --arg to "$diff_path.sha1-to" \
           '. + {diff: {filename: $f, sha1: $s, "sha1-from": $from, "sha1-to": $to }}')
else
    echo "No diff created (no previous state)" >&2
fi

NEW_STATE_FILENAME="publish-$NEW_DATE.json"
NEW_STATE_FILE="$PUBLISH_FOLDER/$NEW_STATE_FILENAME"
echo "$json_obj" > "$NEW_STATE_FILE"

# Update latest statefile link.
rm -f "$LATEST_STATE_FILE"
ln -s "$NEW_STATE_FILENAME" "$LATEST_STATE_FILE"

# relative_sorted_path="truthy-BETA/$NEW_YEAR/dumps/$sorted_filename"
# write_state "$NEW_DATE" "$relative_sorted_path"
# echo "{ \"repo\": \"$REPO_URL\", \"date\": \"$NEW_DATE\", \"sortedFile\": \"$relative_sorted_path\" }" | jq '.' > "$STATE_FILE"

echo "State updated" >&2
echo "Done" >&2

