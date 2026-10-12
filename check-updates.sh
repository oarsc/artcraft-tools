#!/bin/bash

# Check if running as root - error if so
if [[ $EUID -eq 0 ]]; then
    echo "❌ Error: This script should not be run as root"
    echo "   Please run as a regular user"
    exit 1
fi

# Script to check for updates to downloaded tar.gz files in downloads directory

LINKS_FILE="github-links.txt"
DOWNLOAD_DIR="downloads"

# Check if downloads directory exists
if [[ ! -d "$DOWNLOAD_DIR" ]]; then
    echo "❌ Error: Downloads directory '$DOWNLOAD_DIR' not found"
    echo "   No downloaded files to check for updates"
    exit 1
fi

# Find all tar.gz files in downloads
echo "=== Checking for updates in $DOWNLOAD_DIR ==="
echo ""

downloaded_files=($(find "$DOWNLOAD_DIR" -maxdepth 1 -name "*.tar.gz"))

if [[ ${#downloaded_files[@]} -eq 0 ]]; then
    echo "No tar.gz files found in $DOWNLOAD_DIR"
    exit 0
fi

# Build a map of repo name to GitHub URL
declare -A REPO_MAP
previous_comment=""

while IFS= read -r line; do
    if [[ "$line" =~ ^# ]]; then
        previous_comment="${line:1}"
        previous_comment=$(echo "$previous_comment" | xargs)
        continue
    fi
    
    if [[ -z "$line" ]]; then
        previous_comment=""
        continue
    fi

    if [[ "$line" =~ github\.com/([^/]+)/([^/]+) ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
        REPO_MAP["$repo"]="$line"
        REPO_MAP["${repo}_comment"]="$previous_comment"
        previous_comment=""
    else
        previous_comment=""
    fi
done < "$LINKS_FILE"

# Arrays to store download information
declare -a DOWNLOAD_URLS
declare -a FILENAMES
declare -a DESCRIPTIONS
declare -a OLD_FILES_TO_REMOVE

# Check each downloaded file
for downloaded_file in "${downloaded_files[@]}"; do
    filename=$(basename "$downloaded_file")
    
    # Extract directory name from filename (without .tar.gz)
    file_dirname="${filename%.tar.gz}"
    
    # Extract base name (remove version and architecture)
    base_name=$(echo "$file_dirname" | sed 's/-[0-9].*//')
    
    # Check if we have a GitHub URL for this app
    if [[ -z "${REPO_MAP[$base_name]}" ]]; then
        echo "📦 $base_name"
        echo "   File: $filename"
        echo "   ⚠️  Warning: No GitHub link found for $base_name in $LINKS_FILE"
        echo "   Skipping..."
        echo "---"
        echo ""
        continue
    fi
    
    github_url="${REPO_MAP[$base_name]}"
    comment="${REPO_MAP[${base_name}_comment]}"
    
    # Extract owner/repo from GitHub URL
    if [[ "$github_url" =~ github\.com/([^/]+)/([^/]+) ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
    else
        echo "📦 $base_name"
        echo "   File: $filename"
        echo "   ⚠️  Warning: Invalid GitHub URL format"
        echo "   Skipping..."
        echo "---"
        echo ""
        continue
    fi
    
    # Show comment if exists
    if [[ -n "$comment" ]]; then
        echo "📦 $comment"
    else
        echo "📦 $base_name"
    fi
    echo "   Downloaded: $filename"
    echo "   Repo: $owner/$repo"
    
    # Get latest release information using GitHub API
    api_url="https://api.github.com/repos/$owner/$repo/releases/latest"
    
    # Try to get release information
    release_info=$(curl -s "$api_url")
    
    # Check if response is valid
    if ! echo "$release_info" | jq -e '.tag_name' > /dev/null 2>&1; then
        echo "   ⚠️  Warning: Could not get release information for $owner/$repo"
        echo "   Possibly no public releases or API failed"
        echo "---"
        echo ""
        continue
    fi
    
    # Get version tag name
    tag_name=$(echo "$release_info" | jq -r '.tag_name')
    echo "   Latest version: $tag_name"
    
    # Get all assets ending with -linux-x86_64.tar.gz
    all_assets=$(echo "$release_info" | jq -r '.assets[] | select(.name | endswith("-linux-x86_64.tar.gz")) | .browser_download_url')
    
    # Filter out CLI versions (prefer non-CLI)
    download_url=""
    cli_url=""
    
    while IFS= read -r url; do
        if [[ -n "$url" && "$url" != "null" ]]; then
            filename=$(basename "$url")
            if [[ "$filename" == *"-cli-"* ]]; then
                cli_url="$url"
            else
                download_url="$url"
            fi
        fi
    done <<< "$all_assets"
    
    # If no non-CLI version found, use CLI version
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        download_url="$cli_url"
    fi
    
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        echo "   ⚠️  Warning: No -linux-x86_64.tar.gz file found in assets"
        echo "---"
        echo ""
        continue
    fi
    
    # Get latest filename
    latest_filename=$(basename "$download_url")
    echo "   Latest file: $latest_filename"
    
    # Extract latest directory name
    latest_dirname="${latest_filename%.tar.gz}"
    
    # Check if there's an update available
    if [[ "$latest_dirname" == "$file_dirname" ]]; then
        echo "   ✅ Up to date"
        echo "---"
        echo ""
        continue
    fi
    
    echo "   🆕 Update available!"
    echo "   Current: $file_dirname"
    echo "   Latest: $latest_dirname"
    
    # Ask if user wants to download
    read -p "   Download update? [y/n]: " answer < /dev/tty
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo "   ✓ Selected for download"
        DOWNLOAD_URLS+=("$download_url")
        FILENAMES+=("$latest_filename")
        DESCRIPTIONS+=("$base_name")
        OLD_FILES_TO_REMOVE+=("$downloaded_file")
    else
        echo "   ⏭️  Skipped"
    fi
    
    echo "---"
    echo ""
done

# Download selected updates
echo ""
echo "=== Downloading selected updates ==="
echo ""

if [[ ${#DOWNLOAD_URLS[@]} -eq 0 ]]; then
    echo "No updates selected for download."
    exit 0
fi

echo "Will download ${#DOWNLOAD_URLS[@]} update(s):"
for i in "${!FILENAMES[@]}"; do
    desc="${DESCRIPTIONS[$i]}"
    filename="${FILENAMES[$i]}"
    echo "  - $filename ($desc)"
done
echo ""

success_count=0
fail_count=0

for i in "${!DOWNLOAD_URLS[@]}"; do
    url="${DOWNLOAD_URLS[$i]}"
    filename="${FILENAMES[$i]}"
    desc="${DESCRIPTIONS[$i]}"
    old_file="${OLD_FILES_TO_REMOVE[$i]}"
    
    echo "📥 Downloading: $filename"
    if [[ -n "$desc" ]]; then
        echo "   ($desc)"
    fi
    
    curl -L -o "$DOWNLOAD_DIR/$filename" "$url"
    
    if [[ $? -eq 0 ]]; then
        echo "   ✅ Completed"
        ((success_count++))
        
        # Remove old file if it exists
        if [[ -f "$old_file" ]]; then
            echo "   🗑️  Removing old file: $(basename "$old_file")"
            rm -f "$old_file"
            if [[ $? -eq 0 ]]; then
                echo "   ✅ Old file removed"
            else
                echo "   ⚠️  Warning: Could not remove old file"
            fi
        fi
    else
        echo "   ❌ Error"
        ((fail_count++))
    fi
    echo ""
done

echo "=== Summary ==="
echo "✅ Successfully downloaded: $success_count"
echo "❌ Failed: $fail_count"
echo "📁 Files in: $DOWNLOAD_DIR"
echo ""
echo "To install the updates, run:"
echo "  1. ./extract.sh"
