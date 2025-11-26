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

# Track if any matches were found
found_matches=false
alerts=() # Array to store alert messages

echo "🔍 Checking for blacklisted packages in '$project_path' dependency tree..."
echo ""

# Run npm ls in the specified directory and get the full dependency tree
dep_tree=$(cd "$project_path" && npm ls --all --silent 2>/dev/null || true)

# Read the embedded data line by line
while IFS= read -r line; do
    # Skip empty lines and lines starting with #
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # Parse package name and version
    if [[ "$line" =~ ^(@?[^@[:space:]]+)([@[:space:]]+(.+))?$ ]]; then
        pkg_name="${BASH_REMATCH[1]}"
        pkg_version="${BASH_REMATCH[2]:-''}"
    else
        echo "Warning: Invalid format in line: $line"
        continue
    fi
    
    # Remove any trailing whitespace from version
    pkg_version=$(echo "$pkg_version" | sed 's/[[:space:]]*$//')

    if grep -q "$pkg_name@$pkg_version" <<< "$dep_tree"; then
        alerts+=("🚨 ALERT: Package '$pkg_name' version '$pkg_version' is present in the dependency tree!")
        found_matches=true
        echo "❌ - Checked dependency tree for '$pkg_name@$pkg_version'"
    else
        echo "✅ - Checked dependency tree for '$pkg_name@$pkg_version'"
    fi
    
done <<< "$blacklist"

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
