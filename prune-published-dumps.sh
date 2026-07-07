#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PUBLISH_FOLDER="$SCRIPT_DIR/publish"
STATE_FILE="$SCRIPT_DIR/publisher-state.txt"
DRY_RUN=false
ALSO_META=false

usage() {
    echo "Usage: $0 [--also-meta] [--dry-run] N" >&2
    echo "  N                         Number of previous published dumps to retain" >&2
    echo "  --also-meta               Also delete publish-DATE.json metadata files" >&2
    echo "  --dry-run                 Show what would be deleted without deleting" >&2
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --also-meta)
            ALSO_META=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            ;;
        *)
            if [[ -z "${N:-}" ]]; then
                N="$1"
            else
                echo "Unexpected argument: $1" >&2
                usage
            fi
            shift
            ;;
    esac
done

if [[ -z "${N:-}" ]]; then
    echo "Error: N is required" >&2
    usage
fi

if [[ ! -f "$STATE_FILE" ]]; then
    echo "Error: State file not found: $STATE_FILE" >&2
    exit 1
fi

CURRENT_PUBLISH_FILE=$(cat "$STATE_FILE")
CURRENT_PUBLISH_PATH="$PUBLISH_FOLDER/$CURRENT_PUBLISH_FILE"

if [[ ! -f "$CURRENT_PUBLISH_PATH" ]]; then
    echo "Error: Current publish file not found: $CURRENT_PUBLISH_PATH" >&2
    exit 1
fi

resolve_path() {
    local file="$1"
    if [[ "$file" == /* ]]; then
        echo "$file"
    else
        echo "$SCRIPT_DIR/$file"
    fi
}

# Collect all manifests in chain from current backward
declare -a MANIFEST_CHAIN=()
declare -A MANIFEST_DATA=()

current="$CURRENT_PUBLISH_FILE"
while [[ -n "$current" ]]; do
    manifest_path="$PUBLISH_FOLDER/$current"
    if [[ ! -f "$manifest_path" ]]; then
        break
    fi
    
    MANIFEST_CHAIN+=("$current")
    MANIFEST_DATA["$current"]=$(cat "$manifest_path")
    
    prev_file=$(jq -r '.prevPublishFile // empty' <<< "${MANIFEST_DATA[$current]}")
    current="$prev_file"
done

if [[ ${#MANIFEST_CHAIN[@]} -eq 0 ]]; then
    echo "Error: No manifests found in chain" >&2
    exit 1
fi

echo "Manifest chain (${#MANIFEST_CHAIN[@]} files):" >&2
for m in "${MANIFEST_CHAIN[@]}"; do
    echo "  $m" >&2
done

# Determine which manifests to delete
# Skip first (current state) + N manifests, delete the rest
SKIP_COUNT=$((1 + N))
DELETE_START=$SKIP_COUNT

if [[ $DELETE_START -ge ${#MANIFEST_CHAIN[@]} ]]; then
    echo "No manifests to delete (skip count: $SKIP_COUNT, chain length: ${#MANIFEST_CHAIN[@]})" >&2
    exit 0
fi

echo "Deleting manifests from index $DELETE_START onwards:" >&2
for ((i=DELETE_START; i<${#MANIFEST_CHAIN[@]}; i++)); do
    echo "  ${MANIFEST_CHAIN[$i]}" >&2
done

# Track files to delete to avoid duplicates
declare -A FILES_TO_DELETE=()

# Collect files from manifests to delete
for ((i=DELETE_START; i<${#MANIFEST_CHAIN[@]}; i++)); do
    manifest_name="${MANIFEST_CHAIN[$i]}"
    manifest_json="${MANIFEST_DATA[$manifest_name]}"
    
    echo "Processing: $manifest_name" >&2
    
    # Extract file paths from manifest
    keys=("orig.file" "orig.meta" "dump.file" "dump.meta" "diff.file" "diff.meta")
    
    for key in "${keys[@]}"; do
        file_path=$(jq -r --arg k "$key" 'getpath($k | split(".")) // empty' <<< "$manifest_json")
        if [[ -n "$file_path" ]]; then
            full_path=$(resolve_path "$file_path")
            FILES_TO_DELETE["$full_path"]=1
        fi
    done
done

# Print files to delete
echo "" >&2
echo "Files to delete:" >&2
for file in "${!FILES_TO_DELETE[@]}"; do
    echo "  $file" >&2
done

# Also delete manifest files if --also-meta
if [[ "$ALSO_META" == true ]]; then
    for ((i=DELETE_START; i<${#MANIFEST_CHAIN[@]}; i++)); do
        manifest_name="${MANIFEST_CHAIN[$i]}"
        manifest_path="$PUBLISH_FOLDER/$manifest_name"
        FILES_TO_DELETE["$manifest_path"]=1
    done
fi

# Dry run mode
if [[ "$DRY_RUN" == true ]]; then
    echo "" >&2
    echo "[DRY-RUN] Would delete ${#FILES_TO_DELETE[@]} files" >&2
    exit 0
fi

# Actually delete files
echo "" >&2
echo "Deleting files..." >&2
deleted_count=0
for file in "${!FILES_TO_DELETE[@]}"; do
    if [[ -f "$file" ]]; then
        rm -v "$file"
        ((deleted_count++)) || true
    fi
done

# Clean empty directories
echo "" >&2
echo "Cleaning empty directories..." >&2

# Find all year directories
for year_dir in "$SCRIPT_DIR"/truthy-BETA/*/; do
    [[ -d "$year_dir" ]] || continue
    
    year=$(basename "$year_dir")
    echo "  Checking year: $year" >&2
    
    for subdir in origs dumps diffs; do
        dir="$year_dir$subdir"
        if [[ -d "$dir" ]]; then
            if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
                rmdir "$dir" 2>/dev/null && echo "    Removed empty: $dir" >&2
            fi
        fi
    done
    
    if [[ -d "$year_dir" ]]; then
        if [[ -z "$(ls -A "$year_dir" 2>/dev/null)" ]]; then
            rmdir "$year_dir" 2>/dev/null && echo "    Removed empty: $year_dir" >&2
        fi
    fi
done

echo "" >&2
echo "Deleted $deleted_count files" >&2
echo "Done" >&2
