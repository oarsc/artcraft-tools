#!/bin/bash

# Check if running as root - error if so
if [[ $EUID -eq 0 ]]; then
    echo "❌ Error: This script should not be run as root"
    echo "   Please run as a regular user, it will use sudo when needed"
    exit 1
fi

# Script to extract tar.gz files from downloads directory and install to $TARGET_DIR

DOWNLOAD_DIR="downloads"
TARGET_DIR="/opt"

# Check if downloads directory exists
if [[ ! -d "$DOWNLOAD_DIR" ]]; then
    echo "❌ Error: Downloads directory '$DOWNLOAD_DIR' not found"
    exit 1
fi

# Find all tar.gz files
echo "=== Searching for tar.gz files in $DOWNLOAD_DIR ==="
tar_files=($(find "$DOWNLOAD_DIR" -maxdepth 1 -name "*.tar.gz"))

if [[ ${#tar_files[@]} -eq 0 ]]; then
    echo "No tar.gz files found in $DOWNLOAD_DIR"
    exit 0
fi

echo "Found ${#tar_files[@]} tar.gz file(s):"
for file in "${tar_files[@]}"; do
    echo "  - $(basename "$file")"
done
echo ""

# Extract and install each file
success_count=0
fail_count=0

for tar_file in "${tar_files[@]}"; do
    filename=$(basename "$tar_file")
    echo "📦 Processing: $filename"
    
    # Extract version from filename (e.g., gridcraft-0.5.0-linux-x86_64.tar.gz -> 0.5.0)
    version=$(echo "$filename" | sed 's/.*-\([0-9].*\)-linux.*/\1/')
    
    # Extract base name from filename (remove version and architecture suffix)
    # Example: gridcraft-0.5.0-linux-x86_64.tar.gz -> gridcraft
    base_name=$(echo "$filename" | sed 's/-[0-9].*//')
    
    # Target path in $TARGET_DIR (using simplified name)
    target_path="$TARGET_DIR/$base_name"
    
    # Check if target already exists and has the same version
    if [[ -d "$target_path" && -f "$target_path/VERSION" ]]; then
        installed_version=$(cat "$target_path/VERSION")
        if [[ "$installed_version" == "$version" ]]; then
            echo "   ℹ️ Version $version already installed at $target_path"
            echo "   ⏭️ Skipped"
            echo "---"
            echo ""
            continue
        fi
    fi
    
    # Check if target already exists
    if [[ -e "$target_path" ]]; then
        echo "   ⚠️  Warning: $target_path already exists"
        read -p "   Overwrite? [y/n]: " answer < /dev/tty
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            echo "   ⏭️ Skipped"
            echo "---"
            echo ""
            continue
        fi
        echo "   Removing existing $target_path..."
        sudo rm -rf "$target_path"
    fi
    
    # Extract directory name from filename (without .tar.gz)
    extract_dirname="${filename%.tar.gz}"
    
    # Extract directly to /opt with full name
    extract_path="$TARGET_DIR/$extract_dirname"
    echo "   Extracting to $extract_path..."
    sudo tar -xzf "$tar_file" -C "$TARGET_DIR"
    
    if [[ $? -ne 0 ]]; then
        echo "   ❌ Error extracting $filename"
        sudo rm -rf "$extract_path"
        ((fail_count++))
        echo "---"
        echo ""
        continue
    fi
    
    # Rename to simplified name
    echo "   Renaming to $base_name..."
    sudo mv "$extract_path" "$target_path"
    
    if [[ $? -ne 0 ]]; then
        echo "   ❌ Error renaming directory"
        sudo rm -rf "$extract_path"
        ((fail_count++))
        echo "---"
        echo ""
        continue
    fi
    
    echo "   ✅ Successfully installed to $target_path"
    
    # Create VERSION file in the target directory
    echo "   Creating VERSION file..."
    echo "$version" | sudo tee "$target_path/VERSION" > /dev/null
    
    if [[ $? -eq 0 ]]; then
        echo "   ✅ VERSION file created: $version"
    else
        echo "   ⚠️ Warning: Could not create VERSION file"
    fi
    
    ((success_count++))
    echo "---"
    echo ""
done

echo "=== Summary ==="
echo "✅ Successfully installed: $success_count"
echo "❌ Failed: $fail_count"
echo "📁 Installation directory: $TARGET_DIR"
