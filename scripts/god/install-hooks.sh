#!/bin/bash
# Install Git Hooks for God Committee
# Installs post-commit hook to awaken the committee for code review
#
# Usage: ./install-hooks.sh [--uninstall]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GIT_HOOKS_DIR="$PROJECT_ROOT/.git/hooks"

# Check if this is a git repo
if [ ! -d "$PROJECT_ROOT/.git" ]; then
  echo "Error: Not a git repository"
  exit 1
fi

# Uninstall mode
if [ "$1" = "--uninstall" ]; then
  echo "Uninstalling God Committee git hooks..."
  
  if [ -f "$GIT_HOOKS_DIR/post-commit" ]; then
    # Only remove if it's our hook
    if grep -q "God Committee" "$GIT_HOOKS_DIR/post-commit" 2>/dev/null; then
      rm -f "$GIT_HOOKS_DIR/post-commit"
      echo "Removed post-commit hook"
    else
      echo "post-commit hook exists but was not installed by God Committee"
    fi
  fi
  
  echo "Done."
  exit 0
fi

echo "Installing God Committee git hooks..."
echo ""

# Ensure hooks directory exists
mkdir -p "$GIT_HOOKS_DIR"

# Install post-commit hook
POST_COMMIT_HOOK="$GIT_HOOKS_DIR/post-commit"

if [ -f "$POST_COMMIT_HOOK" ]; then
  if grep -q "God Committee" "$POST_COMMIT_HOOK" 2>/dev/null; then
    echo "post-commit hook already installed, updating..."
  else
    echo "Warning: post-commit hook exists. Backing up to post-commit.backup"
    cp "$POST_COMMIT_HOOK" "$POST_COMMIT_HOOK.backup"
  fi
fi

cat > "$POST_COMMIT_HOOK" << 'EOF'
#!/bin/bash
# God Committee - Post-Commit Hook
# Awakens the committee to review committed code

# Find project root (where .god directory is)
find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.god" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

PROJECT_ROOT=$(find_project_root)

if [ -z "$PROJECT_ROOT" ]; then
  # Not in an Aha Loop project, skip
  exit 0
fi

AWAKENER="$PROJECT_ROOT/scripts/god/awakener.sh"

if [ ! -f "$AWAKENER" ]; then
  exit 0
fi

# Get commit info
COMMIT_HASH=$(git rev-parse --short HEAD)
COMMIT_MSG=$(git log -1 --pretty=%s)

# Run awakening in background to not block commit
(
  sleep 2  # Brief delay to let commit fully complete
  
  # Awaken committee with alert mode
  "$AWAKENER" alert "New commit: $COMMIT_HASH - $COMMIT_MSG" &>/dev/null
) &

exit 0
EOF

chmod +x "$POST_COMMIT_HOOK"
echo "Installed post-commit hook"

echo ""
echo "God Committee git hooks installed successfully!"
echo ""
echo "The committee will be awakened after each commit to review code."
echo ""
echo "To uninstall: $0 --uninstall"
