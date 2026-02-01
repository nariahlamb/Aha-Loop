#!/bin/bash
# fetch-source.sh - Fetch third-party library source code for AI research
# Usage:
#   ./fetch-source.sh <ecosystem> <package> <version>
#   ./fetch-source.sh --from-deps
#   ./fetch-source.sh --cleanup
#
# Examples:
#   ./fetch-source.sh rust tokio 1.35.0
#   ./fetch-source.sh npm zod 3.22.4
#   ./fetch-source.sh --from-deps

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VENDOR_DIR="$PROJECT_ROOT/.vendor"
MANIFEST_FILE="$VENDOR_DIR/manifest.json"
CONFIG_FILE="$SCRIPT_DIR/config.json"

# Default config values
MAX_SIZE_MB=500
SHALLOW_CLONE=true
AUTO_CLEANUP_DAYS=30

# Load config if exists
if [ -f "$CONFIG_FILE" ]; then
  MAX_SIZE_MB=$(jq -r '.vendor.maxSizeMB // 500' "$CONFIG_FILE")
  SHALLOW_CLONE=$(jq -r '.vendor.shallowClone // true' "$CONFIG_FILE")
  AUTO_CLEANUP_DAYS=$(jq -r '.vendor.autoCleanupDays // 30' "$CONFIG_FILE")
fi

# Ensure vendor directory and manifest exist
mkdir -p "$VENDOR_DIR"
if [ ! -f "$MANIFEST_FILE" ]; then
  echo '{"version": 1, "libraries": []}' > "$MANIFEST_FILE"
fi

# Helper: Get current size of vendor directory in MB
get_vendor_size() {
  du -sm "$VENDOR_DIR" 2>/dev/null | cut -f1 || echo "0"
}

# Helper: Add entry to manifest
add_to_manifest() {
  local name="$1"
  local version="$2"
  local ecosystem="$3"
  local source="$4"
  local local_path="$5"
  local key_files="$6"
  
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Remove existing entry if present
  local temp_manifest=$(mktemp)
  jq --arg name "$name" --arg version "$version" --arg ecosystem "$ecosystem" \
    '.libraries = [.libraries[] | select(.name != $name or .version != $version or .ecosystem != $ecosystem)]' \
    "$MANIFEST_FILE" > "$temp_manifest"
  
  # Add new entry
  jq --arg name "$name" \
     --arg version "$version" \
     --arg ecosystem "$ecosystem" \
     --arg source "$source" \
     --arg localPath "$local_path" \
     --arg fetchedAt "$timestamp" \
     --arg lastAccessed "$timestamp" \
     --argjson keyFiles "$key_files" \
     '.libraries += [{
       "name": $name,
       "version": $version,
       "ecosystem": $ecosystem,
       "source": $source,
       "localPath": $localPath,
       "fetchedAt": $fetchedAt,
       "lastAccessed": $lastAccessed,
       "keyFiles": $keyFiles
     }]' "$temp_manifest" > "$MANIFEST_FILE"
  
  rm "$temp_manifest"
}

# Helper: Get repository URL for Rust crate
get_rust_repo() {
  local crate="$1"
  local version="$2"
  
  # Query crates.io API
  local crate_info=$(curl -s "https://crates.io/api/v1/crates/$crate/$version" 2>/dev/null)
  local repo=$(echo "$crate_info" | jq -r '.version.repository // .crate.repository // empty' 2>/dev/null)
  
  if [ -z "$repo" ] || [ "$repo" = "null" ]; then
    # Try without version
    crate_info=$(curl -s "https://crates.io/api/v1/crates/$crate" 2>/dev/null)
    repo=$(echo "$crate_info" | jq -r '.crate.repository // empty' 2>/dev/null)
  fi
  
  echo "$repo"
}

# Helper: Get repository URL for NPM package
get_npm_repo() {
  local package="$1"
  local version="$2"
  
  local pkg_info=$(curl -s "https://registry.npmjs.org/$package/$version" 2>/dev/null)
  local repo=$(echo "$pkg_info" | jq -r '.repository.url // .repository // empty' 2>/dev/null)
  
  # Clean up git+https:// or git:// prefixes
  repo=$(echo "$repo" | sed 's|^git+||' | sed 's|^git://|https://|' | sed 's|\.git$||')
  
  echo "$repo"
}

# Helper: Identify key files for a library
identify_key_files() {
  local local_path="$1"
  local ecosystem="$2"
  local files=()
  
  case "$ecosystem" in
    rust)
      [ -f "$local_path/src/lib.rs" ] && files+=("src/lib.rs")
      [ -f "$local_path/src/main.rs" ] && files+=("src/main.rs")
      [ -d "$local_path/src" ] && {
        for mod in $(find "$local_path/src" -name "mod.rs" -type f 2>/dev/null | head -5); do
          files+=("${mod#$local_path/}")
        done
      }
      [ -f "$local_path/README.md" ] && files+=("README.md")
      ;;
    npm)
      [ -f "$local_path/src/index.ts" ] && files+=("src/index.ts")
      [ -f "$local_path/src/index.js" ] && files+=("src/index.js")
      [ -f "$local_path/index.js" ] && files+=("index.js")
      [ -f "$local_path/lib/index.js" ] && files+=("lib/index.js")
      [ -f "$local_path/README.md" ] && files+=("README.md")
      ;;
    python)
      local pkg_name=$(basename "$local_path" | cut -d'-' -f1)
      [ -d "$local_path/$pkg_name" ] && files+=("$pkg_name/__init__.py")
      [ -d "$local_path/src/$pkg_name" ] && files+=("src/$pkg_name/__init__.py")
      [ -f "$local_path/README.md" ] && files+=("README.md")
      ;;
  esac
  
  # Convert to JSON array
  printf '%s\n' "${files[@]}" | jq -R . | jq -s .
}

# Fetch a library
fetch_library() {
  local ecosystem="$1"
  local name="$2"
  local version="$3"
  
  local target_dir="$VENDOR_DIR/$ecosystem/$name-$version"
  
  # Check if already fetched
  if [ -d "$target_dir" ]; then
    echo "Library $name@$version already exists at $target_dir"
    # Update last accessed time
    local temp=$(mktemp)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg name "$name" --arg version "$version" --arg ecosystem "$ecosystem" --arg ts "$timestamp" \
      '(.libraries[] | select(.name == $name and .version == $version and .ecosystem == $ecosystem)).lastAccessed = $ts' \
      "$MANIFEST_FILE" > "$temp" && mv "$temp" "$MANIFEST_FILE"
    return 0
  fi
  
  # Check size limit
  local current_size=$(get_vendor_size)
  if [ "$current_size" -ge "$MAX_SIZE_MB" ]; then
    echo "Warning: Vendor directory size ($current_size MB) exceeds limit ($MAX_SIZE_MB MB)"
    echo "Run './fetch-source.sh --cleanup' to free space"
    return 1
  fi
  
  # Get repository URL
  local repo_url=""
  case "$ecosystem" in
    rust)
      repo_url=$(get_rust_repo "$name" "$version")
      ;;
    npm)
      repo_url=$(get_npm_repo "$name" "$version")
      ;;
    *)
      echo "Unsupported ecosystem: $ecosystem"
      return 1
      ;;
  esac
  
  if [ -z "$repo_url" ] || [ "$repo_url" = "null" ]; then
    echo "Could not find repository URL for $ecosystem/$name@$version"
    return 1
  fi
  
  echo "Fetching $name@$version from $repo_url"
  
  # Create target directory
  mkdir -p "$(dirname "$target_dir")"
  
  # Clone repository
  local clone_args=""
  if [ "$SHALLOW_CLONE" = "true" ]; then
    clone_args="--depth 1"
  fi
  
  # Try to checkout specific version/tag
  if git clone $clone_args "$repo_url" "$target_dir" 2>/dev/null; then
    # Try to checkout version tag
    cd "$target_dir"
    git fetch --tags --depth 1 2>/dev/null || true
    git checkout "v$version" 2>/dev/null || git checkout "$version" 2>/dev/null || git checkout "$name-$version" 2>/dev/null || true
    cd - > /dev/null
    
    # Remove .git to save space
    rm -rf "$target_dir/.git"
    
    # Identify key files
    local key_files=$(identify_key_files "$target_dir" "$ecosystem")
    
    # Add to manifest
    add_to_manifest "$name" "$version" "$ecosystem" "$repo_url" ".vendor/$ecosystem/$name-$version" "$key_files"
    
    echo "Successfully fetched $name@$version to $target_dir"
    echo "Key files: $key_files"
  else
    echo "Failed to clone $repo_url"
    return 1
  fi
}

# Fetch dependencies from project files
fetch_from_deps() {
  echo "Scanning project dependencies..."
  
  # Rust: Parse Cargo.toml
  if [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
    echo "Found Cargo.toml, parsing Rust dependencies..."
    # Extract dependencies (simplified parsing)
    local deps=$(grep -A 1000 '^\[dependencies\]' "$PROJECT_ROOT/Cargo.toml" 2>/dev/null | \
                 grep -B 1000 '^\[' | head -n -1 | \
                 grep -E '^[a-zA-Z]' | \
                 sed 's/ *=.*//' | head -10)
    
    for dep in $deps; do
      # Get version from Cargo.lock if available
      local version=""
      if [ -f "$PROJECT_ROOT/Cargo.lock" ]; then
        version=$(grep -A 2 "name = \"$dep\"" "$PROJECT_ROOT/Cargo.lock" 2>/dev/null | \
                  grep 'version = ' | head -1 | \
                  sed 's/.*version = "\([^"]*\)".*/\1/')
      fi
      
      if [ -n "$version" ]; then
        echo "  Found: $dep@$version"
        fetch_library "rust" "$dep" "$version" || true
      fi
    done
  fi
  
  # NPM: Parse package.json
  if [ -f "$PROJECT_ROOT/package.json" ]; then
    echo "Found package.json, parsing NPM dependencies..."
    local deps=$(jq -r '.dependencies // {} | keys[]' "$PROJECT_ROOT/package.json" 2>/dev/null)
    
    for dep in $deps; do
      local version=$(jq -r ".dependencies[\"$dep\"]" "$PROJECT_ROOT/package.json" | sed 's/[\^~]//')
      if [ -n "$version" ] && [ "$version" != "null" ]; then
        echo "  Found: $dep@$version"
        fetch_library "npm" "$dep" "$version" || true
      fi
    done
  fi
}

# Cleanup old libraries
cleanup() {
  echo "Cleaning up libraries not accessed in $AUTO_CLEANUP_DAYS days..."
  
  local cutoff_date=$(date -d "-$AUTO_CLEANUP_DAYS days" +%s 2>/dev/null || date -v-${AUTO_CLEANUP_DAYS}d +%s)
  local removed=0
  
  # Read manifest and find old entries
  local old_libs=$(jq -r --argjson cutoff "$cutoff_date" \
    '.libraries[] | select((.lastAccessed | fromdateiso8601) < $cutoff) | "\(.ecosystem)/\(.name)-\(.version)"' \
    "$MANIFEST_FILE" 2>/dev/null)
  
  for lib in $old_libs; do
    local lib_path="$VENDOR_DIR/$lib"
    if [ -d "$lib_path" ]; then
      echo "  Removing: $lib"
      rm -rf "$lib_path"
      removed=$((removed + 1))
    fi
  done
  
  # Update manifest to remove deleted entries
  local temp=$(mktemp)
  local cutoff_iso=$(date -u -d "@$cutoff_date" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -r "$cutoff_date" +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg cutoff "$cutoff_iso" \
    '.libraries = [.libraries[] | select(.lastAccessed >= $cutoff)]' \
    "$MANIFEST_FILE" > "$temp" && mv "$temp" "$MANIFEST_FILE"
  
  echo "Cleaned up $removed libraries"
  echo "Current vendor size: $(get_vendor_size) MB"
}

# List fetched libraries
list_libraries() {
  echo "Fetched libraries:"
  jq -r '.libraries[] | "  \(.ecosystem)/\(.name)@\(.version) - \(.localPath)"' "$MANIFEST_FILE"
  echo ""
  echo "Total size: $(get_vendor_size) MB / $MAX_SIZE_MB MB"
}

# Main
case "${1:-}" in
  --from-deps)
    fetch_from_deps
    ;;
  --cleanup)
    cleanup
    ;;
  --list)
    list_libraries
    ;;
  --help|-h)
    echo "Usage:"
    echo "  $0 <ecosystem> <package> <version>  - Fetch a specific library"
    echo "  $0 --from-deps                      - Fetch all project dependencies"
    echo "  $0 --cleanup                        - Remove old unused libraries"
    echo "  $0 --list                           - List fetched libraries"
    echo ""
    echo "Supported ecosystems: rust, npm"
    echo ""
    echo "Examples:"
    echo "  $0 rust tokio 1.35.0"
    echo "  $0 npm zod 3.22.4"
    ;;
  "")
    echo "Error: Missing arguments. Use --help for usage."
    exit 1
    ;;
  *)
    if [ $# -lt 3 ]; then
      echo "Error: Expected 3 arguments: <ecosystem> <package> <version>"
      exit 1
    fi
    fetch_library "$1" "$2" "$3"
    ;;
esac
