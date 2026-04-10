#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GROOVY_SCRIPT="$SCRIPT_DIR/wikidata-release-status.groovy"
# NQPATCH="$SCRIPT_DIR/nqpatch"
NQPATCH="nqpatch"

STATE_FILE="./wikidata-sync.json"

show_usage() {
    echo "Usage: $0 [--init]" >&2
    echo "  --init    Initialize state file with empty JSON" >&2
    echo "  (no args) Process the next available Wikidata dump" >&2
    exit 1
}

#write_state() {
#    local new_date="$1"
#    local new_sorted_file="$2"
#    echo "{ \"date\": \"$new_date\", \"sortedFile\": \"$new_sorted_file\" }" | jq '.' > "$STATE_FILE"
#}

# Download a file into a given directory and return its filename
download_dump() {
    local url="$1"
    local output_path="$2"
    # filename=$(basename "$url")
    
    # Get filename from header
    local filename=$(curl -s -I "$url" | grep -oP 'filename=\K[^;]+')

    # Fallback to URL path if not found
    filename=${filename:-$(basename "$url")}

    # Optional: Remove special characters
    # filename=${filename//[^a-zA-Z0-9._-]/}

    wget -c -P "$output_path" "$url"
    echo "$filename"
}

if [[ "${1:-}" == "--init" ]]; then
    [ ! -f "$STATE_FILE" ] || { echo "Statefile already exists"; exit 1; }
    echo "{ \"repo\": \"https://dumps.wikimedia.org/wikidatawiki/entities/\" }" | jq '.' > "$STATE_FILE"
    echo "Initialized $STATE_FILE" >&2
    exit 0
fi

if [[ -n "${1:-}" ]]; then
    show_usage
fi

# Begin of readState
if [[ ! -f "$STATE_FILE" ]]; then
    echo "Error: State file not found. Run with --init first." >&2
    exit 1
fi

content=$(cat "$STATE_FILE" 2>/dev/null) || true

REPO_URL=$(echo "$content" | jq -r '.repo // ""' 2>/dev/null) || true
echo "Repo URL: $REPO_URL" >&2

if [[ -z "$content" || "$content" == "{}" || "$content" == "null" || "$content" == "" ]]; then
    OLD_DATE=""
    OLD_SORTED_FILENAME=""
else
    OLD_DATE=$(echo "$content" | jq -r '.date // ""' 2>/dev/null) || true
    [[ -z "$OLD_DATE" || "$OLD_DATE" == "null" ]] && OLD_DATE=""
    OLD_SORTED_FILENAME=$(echo "$content" | jq -r '.sortedFile // ""' 2>/dev/null) || true
    [[ -z "$OLD_SORTED_FILENAME" || "$OLD_SORTED_FILENAME" == "null" ]] && OLD_SORTED_FILENAME=""
fi
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

echo "Sorting $orig_path..." >&2
"$NQPATCH" track sort "$orig_path" "$sorted_path"
echo "Sort complete" >&2

if [[ -n "$OLD_DATE" && -n "$OLD_SORTED_FILENAME" ]]; then
    old_year="${OLD_DATE:0:4}"
    diff_dir="truthy-BETA/$old_year/diffs"
    mkdir -p "$diff_dir"

    diff_filename="wikidata-${OLD_DATE}-to-${NEW_DATE}-truthy-BETA.sorted.rdfp.bz2"
    diff_path="$diff_dir/$diff_filename"
    echo "Creating diff: $diff_path" >&2
    echo "  from: $OLD_SORTED_FILENAME" >&2
    echo "  to:   $sorted_path" >&2
    "$NQPATCH" track create "$OLD_SORTED_FILENAME" "$sorted_path" "$diff_path"
    echo "Diff complete" >&2
else
    echo "No diff created (no previous state)" >&2
fi

relative_sorted_path="truthy-BETA/$NEW_YEAR/dumps/$sorted_filename"
# write_state "$NEW_DATE" "$relative_sorted_path"
echo "{ \"repo\": \"$REPO_URL\", \"date\": \"$NEW_DATE\", \"sortedFile\": \"$relative_sorted_path\" }" | jq '.' > "$STATE_FILE"

echo "State updated" >&2
echo "Done" >&2



