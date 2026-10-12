# Artcraft Installation Scripts

Collection of bash scripts to download, install, and configure ~craft applications from GitHub releases.

## Prerequisites

- `curl` - for downloading files
- `jq` - for processing JSON responses from GitHub API
- `tar` - for extracting archives
- `sudo` - for installing to `/opt`

## Scripts

### 1. download.sh

Downloads the latest `-linux-x86_64.tar.gz` releases from GitHub repositories listed in `github-links.txt`.

**Features:**
- Reads GitHub repository links from `github-links.txt`
- Uses GitHub API to find the latest release
- Interactive mode: prompts for each download
- Auto mode: downloads everything without prompting (`--auto` flag)
- Two-phase process: selection first, then download

**Usage:**
```bash
# Interactive mode (prompts for each download)
./download.sh

# Auto mode (downloads everything)
./download.sh --auto
```

---

### 2. check-updates.sh

Checks for available updates by comparing downloaded tar.gz files in `downloads/` with the latest GitHub releases.

**Features:**
- Reads GitHub repository links from `github-links.txt`
- Finds all tar.gz files in `downloads/` directory
- Matches downloaded files with their GitHub repositories
- Compares downloaded version with latest release from GitHub API
- Shows which applications have updates available
- Interactive mode: prompts for each update download
- Two-phase process: selection first, then download
- Skips files that don't have a matching GitHub link

**Usage:**
```bash
./check-updates.sh
```

**Note:** After downloading updates, you need to run `extract.sh` to install them.

---

### 3. extract.sh

Extracts tar.gz files from the `downloads/` directory and installs them to `/opt` with simplified names.

**Features:**
- Extracts all `*.tar.gz` files from `downloads/`
- Renames directories to remove version/architecture suffixes
  - Example: `gridcraft-0.5.0-linux-x86_64` → `gridcraft`
- Prompts before overwriting existing installations
- Uses `sudo` only when needed
- Must NOT be run as root

**Note:** This script should be run as a regular user, not as root. It will use `sudo` internally when necessary.

---

### 4. install-integration.sh

Creates both symlinks and desktop entries for all `*craft` applications installed in `/opt` in a single script.

**Features:**
- Finds all directories ending with `craft` in `/opt`
- Creates symlinks or firejail wrapper scripts from `/opt/appname/bin/appname` to `$HOME/.local/bin/appname`
- Processes `.desktop` files from `/opt/appname/share/applications/`
- Modifies icon paths to point to `/opt/appname/share/icons/hicolor/`
- Copies modified `.desktop` files to `$HOME/.local/share/applications` as `${app_name}.desktop`
- Prompts before overwriting existing symlinks or desktop entries
- Optional firejail sandboxing support (runs applications with `--net=none`)
- Checks if `$HOME/.local/bin` is in PATH
- Shows separate summaries for symlinks and desktop entries

**Usage:**
```bash
./install-integration.sh
```

**Firejail:**
The script will ask if you want to use firejail for sandboxing. If you choose yes, it will create wrapper scripts that run the applications with `firejail --net=none` instead of direct symlinks. This provides network isolation for enhanced security.

**PATH Configuration:**
If `$HOME/.local/bin` is not in your PATH, add this to your shell config (`~/.bashrc` or `~/.zshrc`):
```bash
export PATH="$HOME/.local/bin:$PATH"
```

**Update desktop cache:**
After running this script, you may need to update your desktop menu cache:
```bash
update-desktop-database $HOME/.local/share/applications
```

---

### 5. uninstall.sh

Uninstalls `*craft` applications from `/opt`, removing the application directory, symlinks, and desktop entries.

**Features:**
- Lists all `*craft` directories in `/opt`
- Interactive selection: choose which applications to uninstall by number
- Option to uninstall all applications with `all` command
- Removes:
  - Application directory from `/opt`
  - Symlink from `$HOME/.local/bin`
  - `.desktop` files from `$HOME/.local/share/applications`
- Uses `sudo` for removing files from `/opt`
- Must NOT be run as root

**Usage:**
```bash
./uninstall.sh
```

**Example:**
```
=== Searching for *craft directories in /opt ===
Found 3 *craft director(y/ies):
  [1] gridcraft
  [2] wordcraft
  [3] photocraft

Enter the numbers of the applications you want to uninstall (space-separated)
Example: 1 3 4
Enter 'all' to uninstall everything
Selection: 1 3
```

**Update desktop cache:**
After uninstalling, you may need to update your desktop menu cache:
```bash
update-desktop-database $HOME/.local/share/applications
```

---

## Installation Order

Run the scripts in the following order:

1. **download.sh** - Download the applications
2. **extract.sh** - Extract and install to `/opt`
3. **install-integration.sh** - Create symlinks and desktop entries

### Complete Installation Example

```bash
# Step 1: Download applications
./download.sh

# Step 2: Extract and install to /opt
./extract.sh

# Step 3: Create symlinks and desktop entries
./install-integration.sh

# Optional: Update desktop cache
update-desktop-database $HOME/.local/share/applications
```

---

## Checking for Updates

To check for and install updates to installed applications:

1. **check-updates.sh** - Check for available updates and download them
2. **extract.sh** - Extract and install the new versions
3. **install-integration.sh** - Update symlinks and desktop entries

### Update Example

```bash
# Step 1: Check for updates and download
./check-updates.sh

# Step 2: Extract and install the new versions
./extract.sh

# Step 3: Update symlinks and desktop entries
./install-integration.sh

# Optional: Update desktop cache
update-desktop-database $HOME/.local/share/applications
```

## License

These scripts are provided as-is for managing your ~craft applications.
