#!/bin/bash

# Script to download the latest -linux-x86_64.tar.gz version from GitHub releases

# Check if running as root - error if so
if [[ $EUID -eq 0 ]]; then
    echo "❌ Error: This script should not be run as root"
    echo "   Please run as a regular user"
    exit 1
fi

LINKS_FILE="github-links.txt"
DOWNLOAD_DIR="downloads"
AUTO_MODE=false

# Check if --auto flag was passed
if [[ "$1" == "--auto" ]]; then
    AUTO_MODE=true
    echo "Auto mode: downloading everything without prompting"
fi

# Create download directory if it doesn't exist
mkdir -p "$DOWNLOAD_DIR"

# Arrays to store download information
declare -a DOWNLOAD_URLS
declare -a FILENAMES
declare -a DESCRIPTIONS

# Phase 1: Collect information and prompt
previous_comment=""

while IFS= read -r line; do
    # Save comments to show with the next link
    if [[ "$line" =~ ^# ]]; then
        previous_comment="${line:1}"  # Remove the #
        previous_comment=$(echo "$previous_comment" | xargs)  # Trim spaces
        continue
    fi
    
    # Ignore empty lines - if there's a saved comment and we find an empty line,
    # it means the comment is not associated with any link, so we ignore it
    if [[ -z "$line" ]]; then
        previous_comment=""
        continue
    fi

    # Extract owner/repo from GitHub link
    # Expected format: https://github.com/owner/repo
    if [[ "$line" =~ github\.com/([^/]+)/([^/]+) ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
        
        # Show previous comment if it exists
        if [[ -n "$previous_comment" ]]; then
            echo "📦 $previous_comment"
        else
            echo "📦 No description"
        fi
        echo "   Link: $owner/$repo"
        
        # Get latest release information using GitHub API
        api_url="https://api.github.com/repos/$owner/$repo/releases/latest"
        
        # Try to get release information
        release_info=$(curl -s "$api_url")
        
        # Check if response is valid
        if ! echo "$release_info" | jq -e '.tag_name' > /dev/null 2>&1; then
            echo "   ❌ Error: Could not get release information for $owner/$repo"
            echo "   Possibly no public releases or API failed"
            echo "---"
            previous_comment=""
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
            echo "   ❌ No -linux-x86_64.tar.gz file found in assets"
            echo "---"
            previous_comment=""
            continue
        fi
        
        # Get filename
        filename=$(basename "$download_url")
        echo "   File: $filename"
        
        # Check if file already exists in downloads directory
        if [[ -f "$DOWNLOAD_DIR/$filename" ]]; then
            echo "   ℹ️  File already exists in downloads directory"
            echo "   ⏭️  Skipped"
            echo ""
            previous_comment=""
            continue
        fi
        
        # Ask if user wants to download (in auto mode, download everything)
        if [[ "$AUTO_MODE" == true ]]; then
            echo "   ✓ Selected (auto mode)"
            DOWNLOAD_URLS+=("$download_url")
            FILENAMES+=("$filename")
            DESCRIPTIONS+=("$previous_comment")
        else
            read -p "   Download? [y/n]: " answer < /dev/tty
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                echo "   ✓ Selected"
                DOWNLOAD_URLS+=("$download_url")
                FILENAMES+=("$filename")
                DESCRIPTIONS+=("$previous_comment")
            else
                echo "   ⏭️  Skipped"
            fi
        fi
        
        echo ""
        previous_comment=""
    else
        # If line is not a valid GitHub link, ignore previous comment
        previous_comment=""
    fi
done < "$LINKS_FILE"

# Phase 2: Download all selected files
echo "### Downloading selected files ###"
echo ""

if [[ ${#DOWNLOAD_URLS[@]} -eq 0 ]]; then
    echo "No files selected for download."
    exit 0
fi

echo "Will download ${#DOWNLOAD_URLS[@]} files:"
for i in "${!FILENAMES[@]}"; do
    echo "  - ${FILENAMES[$i]}"
done
echo ""

success_count=0
fail_count=0

for i in "${!DOWNLOAD_URLS[@]}"; do
    url="${DOWNLOAD_URLS[$i]}"
    filename="${FILENAMES[$i]}"
    desc="${DESCRIPTIONS[$i]}"
    
    echo "📥 Downloading: $filename"
    if [[ -n "$desc" ]]; then
        echo "   ($desc)"
    fi
    
    curl -L -o "$DOWNLOAD_DIR/$filename" "$url"
    
    if [[ $? -eq 0 ]]; then
        echo "   ✅ Completed"
        ((success_count++))
    else
        echo "   ❌ Error"
        ((fail_count++))
    fi
    echo ""
done

echo "### Summary ###"
echo "✅ Successful: $success_count"
echo "❌ Failed: $fail_count"
echo "📁 Files in: $DOWNLOAD_DIR"
