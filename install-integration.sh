#!/bin/bash

# Check if running as root - error if so
if [[ $EUID -eq 0 ]]; then
    echo "❌ Error: This script should not be run as root"
    echo "   Please run as a regular user"
    exit 1
fi

# Script to create symlinks and desktop entries for all ~craft apps in /opt

SOURCE_DIR="/opt"
SYMLINK_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"

# Check if source directory exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "❌ Error: Source directory '$SOURCE_DIR' not found"
    exit 1
fi

# Create target directories if they don't exist
mkdir -p "$SYMLINK_DIR"
mkdir -p "$DESKTOP_DIR"

# Ask if user wants to use firejail
USE_FIREJAIL=false
read -p "Use firejail for sandboxing internet connection? [y/n]: " firejail_answer < /dev/tty
if [[ "$firejail_answer" =~ ^[Yy]$ ]]; then
    USE_FIREJAIL=true
    echo "✓ Firejail will be used for sandboxing"
else
    echo "✓ Direct symlinks will be created"
fi
echo ""

# Find all directories ending with 'craft' in /opt
echo "=== Searching for *craft directories in $SOURCE_DIR ==="
craft_dirs=($(find "$SOURCE_DIR" -maxdepth 1 -type d -name "*craft"))

if [[ ${#craft_dirs[@]} -eq 0 ]]; then
    echo "No *craft directories found in $SOURCE_DIR"
    exit 0
fi

echo "Found ${#craft_dirs[@]} *craft director(y/ies):"
for dir in "${craft_dirs[@]}"; do
    echo "  - $(basename "$dir")"
done
echo ""

# Process each craft directory
symlink_success=0
symlink_fail=0
symlink_skip=0
desktop_success=0
desktop_fail=0
desktop_skip=0

for craft_dir in "${craft_dirs[@]}"; do
    app_name=$(basename "$craft_dir")
    
    echo "🔗 Processing: $app_name"
    echo ""
    
    # === Create Symlink ===
    binary_path="$craft_dir/bin/$app_name"
    symlink_path="$SYMLINK_DIR/$app_name"
    
    echo "   [Symlink] Checking binary at $binary_path"
    
    if [[ ! -f "$binary_path" ]]; then
        echo "   ⚠️  Warning: Binary not found at $binary_path"
        ((symlink_skip++))
    else
        # Check if symlink already exists
        if [[ -e "$symlink_path" || -L "$symlink_path" ]]; then
            echo "   ⚠️  Warning: Symlink already exists at $symlink_path"
            read -p "   Overwrite? [y/n]: " answer < /dev/tty
            if [[ ! "$answer" =~ ^[Yy]$ ]]; then
                echo "   ⏭️  Skipped"
                ((symlink_skip++))
            else
                echo "   Removing existing symlink..."
                rm -f "$symlink_path"
                if [[ "$USE_FIREJAIL" == true ]]; then
                    echo "   Creating firejail wrapper script: $symlink_path"
                    cat > "$symlink_path" <<EOF
#!/bin/bash
exec firejail --noprofile \
  --net=none \
  --caps.drop=all \
  --nonewprivs \
  --seccomp \
  --restrict-namespaces \
  --private-tmp \
  "$binary_path" "\$@"
EOF
                    chmod +x "$symlink_path"
                    if [[ $? -eq 0 ]]; then
                        echo "   ✅ Firejail wrapper created successfully"
                        ((symlink_success++))
                    else
                        echo "   ❌ Error creating firejail wrapper"
                        ((symlink_fail++))
                    fi
                else
                    echo "   Creating symlink: $symlink_path -> $binary_path"
                    ln -s "$binary_path" "$symlink_path"
                    if [[ $? -eq 0 ]]; then
                        echo "   ✅ Symlink created successfully"
                        ((symlink_success++))
                    else
                        echo "   ❌ Error creating symlink"
                        ((symlink_fail++))
                    fi
                fi
            fi
        else
            if [[ "$USE_FIREJAIL" == true ]]; then
                echo "   Creating firejail wrapper script: $symlink_path"
                cat > "$symlink_path" <<EOF
#!/bin/bash
exec firejail --noprofile \
  --net=none \
  --caps.drop=all \
  --nonewprivs \
  --seccomp \
  --restrict-namespaces \
  --private-tmp \
  "$binary_path" "\$@"
EOF
                chmod +x "$symlink_path"
                if [[ $? -eq 0 ]]; then
                    echo "   ✅ Firejail wrapper created successfully"
                    ((symlink_success++))
                else
                    echo "   ❌ Error creating firejail wrapper"
                    ((symlink_fail++))
                fi
            else
                echo "   Creating symlink: $symlink_path -> $binary_path"
                ln -s "$binary_path" "$symlink_path"
                if [[ $? -eq 0 ]]; then
                    echo "   ✅ Symlink created successfully"
                    ((symlink_success++))
                else
                    echo "   ❌ Error creating symlink"
                    ((symlink_fail++))
                fi
            fi
        fi
    fi
    echo ""
    
    # === Create Desktop Entry ===
    desktop_dir="$craft_dir/share/applications"
    icon_dir="$craft_dir/share/icons/hicolor"
    
    echo "   [Desktop] Checking desktop files in $desktop_dir"
    
    # Check if desktop directory exists
    if [[ ! -d "$desktop_dir" ]]; then
        echo "   ⚠️  Warning: Desktop directory not found at $desktop_dir"
        ((desktop_skip++))
    else
        # Find all .desktop files
        desktop_files=("$desktop_dir"/*.desktop)
        
        if [[ ! -e "${desktop_files[0]}" ]]; then
            echo "   ⚠️  Warning: No .desktop files found in $desktop_dir"
            ((desktop_skip++))
        else
            for desktop_file in "${desktop_files[@]}"; do
                original_filename=$(basename "$desktop_file")
                desktop_filename="${app_name}.desktop"
                target_path="$DESKTOP_DIR/$desktop_filename"
                
                echo "   Processing: $original_filename -> $desktop_filename"
                
                # Check if target already exists
                if [[ -e "$target_path" ]]; then
                    echo "   ⚠️  Warning: File already exists at $target_path"
                    read -p "   Overwrite? [y/n]: " answer < /dev/tty
                    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
                        echo "   ⏭️  Skipped"
                        ((desktop_skip++))
                        continue
                    fi
                fi
                
                # Read the .desktop file and modify icon path
                echo "   Modifying icon paths..."
                
                # Create a temporary file
                temp_file=$(mktemp)
                
                # Process the file line by line
                while IFS= read -r line || [[ -n "$line" ]]; do
                    # Check if line starts with Icon=
                    if [[ "$line" =~ ^Icon= ]]; then
                        icon_name=$(echo "$line" | cut -d'=' -f2)
                        
                        # Check if icon_dir exists
                        if [[ -d "$icon_dir" ]]; then
                            # Find the icon file (search in common sizes)
                            icon_path=$(find "$icon_dir" -name "$icon_name.png" -o -name "$icon_name.svg" 2>/dev/null | head -n 1)
                            
                            if [[ -n "$icon_path" ]]; then
                                echo "   Found icon at: $icon_path"
                                line="Icon=$icon_path"
                            else
                                echo "   ⚠️  Icon file not found: $icon_name (keeping original)"
                            fi
                        else
                            echo "   ⚠️  Icon directory not found: $icon_dir"
                        fi
                    fi
                    echo "$line" >> "$temp_file"
                done < "$desktop_file"
                
                # Copy modified file to target
                cp "$temp_file" "$target_path"
                rm -f "$temp_file"
                
                if [[ $? -eq 0 ]]; then
                    echo "   ✅ Desktop entry created: $target_path"
                    ((desktop_success++))
                else
                    echo "   ❌ Error creating desktop entry"
                    ((desktop_fail++))
                fi
            done
        fi
    fi
    echo ""
    echo "---"
    echo ""
done

echo "=== Summary ==="
echo ""
echo "Symlinks:"
echo "  ✅ Successfully created: $symlink_success"
echo "  ⏭️  Skipped: $symlink_skip"
echo "  ❌ Failed: $symlink_fail"
echo ""
echo "Desktop Entries:"
echo "  ✅ Successfully created: $desktop_success"
echo "  ⏭️  Skipped: $desktop_skip"
echo "  ❌ Failed: $desktop_fail"
echo ""
echo "📁 Symlink directory: $SYMLINK_DIR"
echo "📁 Desktop entries directory: $DESKTOP_DIR"
echo ""

# Check if SYMLINK_DIR is in PATH
if [[ ! ":$PATH:" == *":$SYMLINK_DIR:"* ]]; then
    echo "⚠️  Warning: $SYMLINK_DIR is not in your PATH"
    echo "   Add the following to your shell config (~/.bashrc or ~/.zshrc):"
    echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
fi

echo "Note: You may need to update your desktop menu cache:"
echo "  update-desktop-database $HOME/.local/share/applications"
