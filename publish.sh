#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=""
for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && DRY_RUN="1"
done

# PUBLISH_FOLDER="$SCRIPT_DIR/publish"
PUBLISH_FOLDER="publish"
STATE_FILE="publisher-state.txt"

CONF_FILE="$SCRIPT_DIR/wikidata-sync.conf.json"
confJson=""
[[ -f "$CONF_FILE" ]] && confJson=$(cat "$CONF_FILE")

backend=""
if [[ -n "$confJson" ]]; then
    backend=$(jq -r '.publishBackend // empty' <<< "$confJson")
fi
[[ -z "$backend" ]] && backend="publish-git.sh"
[[ "$backend" != /* ]] && backend="$SCRIPT_DIR/$backend"
if [[ -n "$DRY_RUN" ]]; then
    backend="$SCRIPT_DIR/publish-dryrun.sh"
fi
PUBLISH_BACKEND="$backend"

if [[ ! -f "$PUBLISH_BACKEND" ]]; then
    echo "Error: publish backend not found: $PUBLISH_BACKEND" >&2
    exit 1
fi
source "$PUBLISH_BACKEND"


resolve_json_path() {
    local filename="$1"
    if [[ "$filename" == /* ]]; then
        echo "$filename"
    else
        echo "$PUBLISH_FOLDER/$filename"
    fi
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
        "orig.meta"
        "dump.file"
        "dump.meta"
        "diff.file"
        "diff.meta"
    )

    for key in "${keys[@]}"; do
        # Publish a sorted dump ONLY if it is the first of the year
        # XXX Also publish a dump if there is no OLD_YEAR value? right now we require a previous date.
        if [[ "$key" == "dump.file" && (-z "$OLD_YEAR" || "$NEW_YEAR" == "$OLD_YEAR") ]]; then
            continue
        fi
    
        value="$(jq -r --arg k "$key" 'getpath($k | split(".")) // empty' <<< "$json_content")"
        if [ -n "$value" ]; then
            publish_one_file "$json_content" "$key" "$value"
        fi
    done

    publish_one_manifest "$json_content"
}


main() {
    [[ -n "$DRY_RUN" ]] && echo "DRY RUN: no files will be published and the state file will not change" >&2

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

        if [[ -z "$DRY_RUN" ]]; then
            echo "$publish_file" > "$STATE_FILE"
        fi
    done
    
    echo "Done" >&2
}

main "$@"

