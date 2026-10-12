#!/bin/bash

# Check if running as root - error if so
if [[ $EUID -eq 0 ]]; then
    echo "❌ Error: This script should not be run as root"
    echo "   Please run as a regular user"
    exit 1
fi

# Script to uninstall *craft applications from /opt

SOURCE_DIR="/opt"
SYMLINK_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"

# Check if source directory exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "❌ Error: Source directory '$SOURCE_DIR' not found"
    exit 1
fi

# Find all directories ending with 'craft' in /opt
echo "=== Searching for *craft directories in $SOURCE_DIR ==="
craft_dirs=($(find "$SOURCE_DIR" -maxdepth 1 -type d -name "*craft"))

if [[ ${#craft_dirs[@]} -eq 0 ]]; then
    echo "No *craft directories found in $SOURCE_DIR"
    echo "Nothing to uninstall."
    exit 0
fi

echo "Found ${#craft_dirs[@]} *craft director(y/ies):"
for i in "${!craft_dirs[@]}"; do
    dir="${craft_dirs[$i]}"
    echo "  [$((i+1))] $(basename "$dir")"
done
echo ""

# Ask which applications to uninstall
echo "Enter the numbers of the applications you want to uninstall (space-separated)"
echo "Example: 1 3 4"
echo "Enter 'all' to uninstall everything"
read -p "Selection: " selection < /dev/tty

if [[ -z "$selection" ]]; then
    echo "No selection made. Exiting."
    exit 0
fi

# Determine which directories to remove
if [[ "$selection" == "all" ]]; then
    selected_indices=("${!craft_dirs[@]}")
else
    # Parse selection
    selected_indices=()
    for num in $selection; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 1 ]] && [[ $num -le ${#craft_dirs[@]} ]]; then
            selected_indices+=($((num-1)))
        else
            echo "⚠️  Warning: Invalid selection '$num', skipping"
        fi
    done
fi

if [[ ${#selected_indices[@]} -eq 0 ]]; then
    echo "No valid selections. Exiting."
    exit 0
fi

# Uninstall selected applications
success_count=0
fail_count=0

for idx in "${selected_indices[@]}"; do
    craft_dir="${craft_dirs[$idx]}"
    app_name=$(basename "$craft_dir")
    
    echo "🗑️  Uninstalling: $app_name"
    
    # Remove directory from /opt
    if [[ -d "$craft_dir" ]]; then
        echo "   Removing $craft_dir..."
        sudo rm -rf "$craft_dir"
        if [[ $? -eq 0 ]]; then
            echo "   ✅ Removed from /opt"
        else
            echo "   ❌ Error removing from /opt"
            ((fail_count++))
            continue
        fi
    fi
    
    # Remove binary from $HOME/.local/bin (symlink or firejail wrapper)
    binary_path="$SYMLINK_DIR/$app_name"
    if [[ -L "$binary_path" ]]; then
        echo "   Removing symlink $binary_path..."
        rm -f "$binary_path"
        if [[ $? -eq 0 ]]; then
            echo "   ✅ Removed symlink"
        else
            echo "   ⚠️  Warning: Could not remove symlink"
        fi
    elif [[ -f "$binary_path" ]]; then
        echo "   Removing binary $binary_path..."
        rm -f "$binary_path"
        if [[ $? -eq 0 ]]; then
            echo "   ✅ Removed binary"
        else
            echo "   ⚠️  Warning: Could not remove binary"
        fi
    else
        echo "   ℹ️  Binary not found (already removed or never created)"
    fi
    
    # Remove .desktop file from $HOME/.local/share/applications
    desktop_file="$DESKTOP_DIR/$app_name.desktop"
    if [[ -f "$desktop_file" ]]; then
        echo "   Removing desktop entry $desktop_file..."
        rm -f "$desktop_file"
        if [[ $? -eq 0 ]]; then
            echo "   ✅ Removed desktop entry"
        else
            echo "   ⚠️  Warning: Could not remove desktop entry"
        fi
    else
        echo "   ℹ️  Desktop entry not found (already removed or never created)"
    fi
    
    ((success_count++))
    echo ""
done

echo "=== Summary ==="
echo "✅ Successfully uninstalled: $success_count"
echo "❌ Failed: $fail_count"
echo ""
echo "Note: You may need to update your desktop menu cache:"
echo "  update-desktop-database $HOME/.local/share/applications"
