#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# PUBLISH_FOLDER="$SCRIPT_DIR/publish"
PUBLISH_FOLDER="publish"
STATE_FILE="publisher-state.txt"


resolve_json_path() {
    local filename="$1"
    if [[ "$filename" == /* ]]; then
        echo "$filename"
    else
        echo "$PUBLISH_FOLDER/$filename"
    fi
}


publish_one_file() {
    local key="$1"
    local file="$2"
    echo "Publishing $1: $2" >&2
}

publish_from_json() {
    local json_file="$1"
    local json_content
    json_content=$(cat "$json_file")

    OLD_DATE=$(jq -r '.prevDate // empty' <<< "$json_content")
    OLD_YEAR="${OLD_DATE%????}"

    NEW_DATE=$(jq -r '.date // empty' <<< "$json_content")
    NEW_YEAR="${NEW_DATE%????}"

    [ -n "$NEW_YEAR" ] || { echo "Failed to extract year. Date string was [$NEW_DATE]" >&2; exit 1; }

    keys=(
        "orig.filename"
        "orig.sha1"
        "dump.filename"
        "dump.sha1"
        "dump.sha1-original"
        "diff.filename"
        "diff.sha1"
        "diff.sha1-from" # hyphen is no problem due to getpath!
        "diff.sha1-to"
    )

    for key in "${keys[@]}"; do
        # Publish a sorted dump ONLY if it is the first of the year
        # XXX Also publish a dump if there is no OLD_YEAR value? right now we require a previous date.
        if [[ "$key" == "orig.filename" && -n "$OLD_YEAR" && "$NEW_YEAR" == "$OLD_YEAR" ]]; then
            continue
        fi
    
        value="$(jq -r --arg k "$key" 'getpath($k | split(".")) // empty' <<< "$json_content")"
        if [ -n "$value" ]; then
            publish_one_file "$key" "$value"
        fi
    done
}


publish_once() {

    echo "$publish_file" > "$STATE_FILE"
}

main() {
    local latest_link="$PUBLISH_FOLDER/publish-latest.json"
    
    if [[ ! -e "$latest_link" ]]; then
        echo "Error: $latest_link does not exist" >&2
        exit 1
    fi
    
    local last_published=""
    if [[ -f "$STATE_FILE" ]]; then
        last_published=$(cat "$STATE_FILE")
    fi

    local current_file=$(readlink "$latest_link")
    
    local files_to_process=()
    while true; do
        local resolved_path=$(resolve_json_path "$current_file")
        
        if [[ "$current_file" == "$last_published" ]]; then
            break
        fi

        echo "Reading: $resolved_path" >&2

        local json_content=$(cat "$resolved_path")
        local prev_file=$(jq -r '.prevPublishFile // empty' <<< "$json_content")

        files_to_process+=("$current_file")
        
        if [[ -z "$prev_file" ]]; then
            break
        fi
        
        current_file="$prev_file"
    done
    
    if [[ ${#files_to_process[@]} -eq 0 ]]; then
        echo "No files to process" >&2
        exit 0
    fi
    
    for ((i=${#files_to_process[@]}-1; i>=0; i--)); do
        local publish_file="${files_to_process[i]}"
        local publish_path=$(resolve_json_path "$publish_file")
        
        echo "Processing: $publish_path" >&2
        
        publish_from_json "$publish_path"
        
        echo "$publish_file" > "$STATE_FILE"
    done
    
    echo "Done" >&2
}

main "$@"

