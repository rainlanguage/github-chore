#!/bin/bash

set -euo pipefail

# Get the path from command line argument, default to current path
project_path="${1:-.}"

# Check if the path exists
if [ ! -d "$project_path" ]; then
    echo "❌ ERROR: Directory '$project_path' does not exist!"
    exit 1
fi

# Check if package.json exists in the directory
if [ ! -f "$project_path/package.json" ]; then
    echo "❌ ERROR: No package.json found in '$project_path'!"
    exit 1
fi

# Ensure dependencies are installed
if [ ! -d "$project_path/node_modules" ]; then
    echo "❌ ERROR: node_modules not found in '$project_path'. Install deps first (e.g., 'npm ci')."
    exit 1
fi

# ---

# Path to blacklist file (relative to script location)
blacklist_default_file="$(dirname "$0")/blacklist.txt"
blacklist_file="${2:-$blacklist_default_file}"

# Check if blacklist file exists
if [ ! -f "$blacklist_file" ]; then
    echo "❌ ERROR: Blacklist file '$blacklist_file' not found!"
    exit 1
fi

# Get extra blacklist file from third argument (optional)
additional_blacklist_file="${3:-""}"

# Get extra blacklist string from fourth argument (optional)
additional_blacklist_pkgs="${4:-""}"

# Build full blacklist
blacklist=$(cat "$blacklist_file")

if [ -n "$additional_blacklist_file" ] && [ -f "$additional_blacklist_file" ]; then
    blacklist="$blacklist"$'\n'"$(cat "$additional_blacklist_file")"
elif [ -n "$additional_blacklist_file" ]; then
    echo "⚠️ Warning: Additional blacklist file '$additional_blacklist_file' not found; ignoring."
fi

if [ -n "$additional_blacklist_pkgs" ]; then
    blacklist="$blacklist"$'\n'"$additional_blacklist_pkgs"
fi

# ---

# Replace the while loop with this more portable version:
check_package() {
    local line="$1"
    local dep_tree_file="$2"
    
    # Skip empty lines and lines starting with #
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
        return 0
    fi
    
    # Parse package name and version  
    if [[ "$line" =~ ^(@?[^@[:space:]]+)([@[:space:]]+(.+))?$ ]]; then
        pkg_name="${BASH_REMATCH[1]}"
        pkg_version="${BASH_REMATCH[3]:-}"
    else
        echo "Warning: Invalid format in line: $line" >&2
        return 0
    fi
    
    # Remove any trailing whitespace from version
    pkg_version=$(echo "$pkg_version" | sed 's/[[:space:]]*$//')

    if grep -q "$pkg_name@$pkg_version" "$dep_tree_file"; then
        echo "ALERT:$pkg_name@$pkg_version"
        echo "❌ - Checked dependency tree for '$pkg_name@$pkg_version'" >&2
        return 0
    else
        echo "✅ - Checked dependency tree for '$pkg_name@$pkg_version'" >&2
        return 0
    fi
}

echo "🔍 Checking for blacklisted packages in '$project_path' dependency tree..."
echo ""

# # Run npm ls in the specified directory and get the full dependency tree
dep_tree=$(cd "$project_path" && npm ls --all --silent 2>/dev/null || true)

# Store dependency tree in a temp file
dep_tree_file=$(mktemp)
echo "$dep_tree" > "$dep_tree_file"

# Store blacklist in temp file too
blacklist_file_temp=$(mktemp)
echo "$blacklist" > "$blacklist_file_temp"

export -f check_package
results_file=$(mktemp)

# Run checks in parallel
pids=()  # More explicit array declaration
max_jobs=20 # number of max concurrent jobs
current_jobs=0

while IFS= read -r line; do
    check_package "$line" "$dep_tree_file" >> "$results_file" &
    pids+=("$!")
    ((current_jobs++))
    
    # Wait for batch completion
    if (( current_jobs >= max_jobs )); then
        for pid in "${pids[@]}"; do
            wait "$pid"
        done
        pids=()
        current_jobs=0
    fi
done < "$blacklist_file_temp"

# Wait for remaining processes
for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
done

# # Track if any matches were found
found_matches=false
alerts=()

# Collect alerts
while IFS= read -r result; do
    if [[ "$result" =~ ^ALERT:(.+)$ ]]; then
        pkg="${BASH_REMATCH[1]}"
        alerts+=("🚨 ALERT: Package '$pkg' is present in the dependency tree!")
        found_matches=true
    fi
done < "$results_file"

# Cleanup
rm -f "$dep_tree_file" "$blacklist_file_temp" "$results_file"

echo "Package version check complete for: $project_path"

# Exit with error code if any matches were found
if [ "$found_matches" = true ]; then
    echo "❌ ERROR: One or more vulnerable package versions were found!"
    echo ""
    for msg in "${alerts[@]}"; do
        echo "$msg"
    done
    exit 1
else
    echo "✅ No vulnerable package versions found."
    exit 0
fi
