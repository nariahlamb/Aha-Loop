#!/bin/bash
# Aha Loop Doc Cleaner - Documentation Maintenance Tool
# Scans, reviews, and cleans up documentation
#
# Usage:
#   ./doc-cleaner.sh --report              Generate review report
#   ./doc-cleaner.sh --fix                 Apply safe auto-fixes
#   ./doc-cleaner.sh --interactive         Interactive cleanup
#   ./doc-cleaner.sh --check-links         Check external links only
#   ./doc-cleaner.sh --check-refs          Check code references only

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"
REPORT_FILE="$PROJECT_ROOT/docs-review-report.md"

# Default settings
MAX_STALE_DAYS=30
CHECK_LINKS=true
CHECK_REFS=true
FIX_MODE=false
INTERACTIVE=false

# Load config
if [ -f "$CONFIG_FILE" ]; then
  MAX_STALE_DAYS=$(jq -r '.docMaintenance.maxStaleDays // 30' "$CONFIG_FILE")
fi

# Print usage
usage() {
  echo "Aha Loop Doc Cleaner - Documentation Maintenance Tool"
  echo ""
  echo "Usage:"
  echo "  $0 --report              Generate documentation review report"
  echo "  $0 --fix                 Apply safe auto-fixes"
  echo "  $0 --interactive         Interactive cleanup mode"
  echo "  $0 --check-links         Check external links only"
  echo "  $0 --check-refs          Check code references only"
  echo "  $0 --stale-days N        Set staleness threshold (default: 30)"
  echo ""
  echo "Examples:"
  echo "  $0 --report"
  echo "  $0 --fix --stale-days 60"
  echo "  $0 --check-links"
}

# Find all documentation files
find_docs() {
  find "$PROJECT_ROOT" -name "*.md" \
    -not -path "*/.git/*" \
    -not -path "*/.vendor/*" \
    -not -path "*/.worktrees/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/target/*" \
    2>/dev/null | sort
}

# Get file age in days
file_age_days() {
  local file="$1"
  local last_modified
  
  # Try git first
  last_modified=$(git log -1 --format="%at" -- "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null)
  
  if [ -n "$last_modified" ]; then
    local now=$(date +%s)
    echo $(( (now - last_modified) / 86400 ))
  else
    echo "unknown"
  fi
}

# Check if file reference exists
check_file_reference() {
  local ref="$1"
  local doc_dir="$2"
  
  # Handle relative and absolute paths
  if [[ "$ref" == /* ]]; then
    [ -e "$PROJECT_ROOT$ref" ]
  else
    [ -e "$doc_dir/$ref" ] || [ -e "$PROJECT_ROOT/$ref" ]
  fi
}

# Extract file references from markdown
extract_file_refs() {
  local file="$1"
  
  # Match patterns like `src/main.rs`, `./config.json`, etc.
  grep -oP '`[a-zA-Z0-9_./-]+\.(rs|ts|js|json|toml|yaml|yml|sh|py|md)`' "$file" 2>/dev/null | \
    tr -d '`' | sort -u
}

# Extract external URLs
extract_urls() {
  local file="$1"
  grep -oP 'https?://[^\s\)\]]+' "$file" 2>/dev/null | sort -u
}

# Check if URL is reachable
check_url() {
  local url="$1"
  local status
  
  status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null)
  
  if [ "$status" -ge 200 ] && [ "$status" -lt 400 ]; then
    return 0
  else
    return 1
  fi
}

# Generate report
generate_report() {
  local total_files=0
  local stale_files=0
  local missing_refs=0
  local broken_links=0
  local issues=""
  
  echo "Scanning documentation files..."
  
  while IFS= read -r file; do
    total_files=$((total_files + 1))
    local rel_path="${file#$PROJECT_ROOT/}"
    local doc_dir=$(dirname "$file")
    local file_issues=""
    
    # Check staleness
    local age=$(file_age_days "$file")
    if [ "$age" != "unknown" ] && [ "$age" -gt "$MAX_STALE_DAYS" ]; then
      stale_files=$((stale_files + 1))
      file_issues+="- Stale: ${age} days since last update\n"
    fi
    
    # Check file references
    if [ "$CHECK_REFS" = true ]; then
      while IFS= read -r ref; do
        if [ -n "$ref" ]; then
          if ! check_file_reference "$ref" "$doc_dir"; then
            missing_refs=$((missing_refs + 1))
            file_issues+="- Missing reference: \`$ref\`\n"
          fi
        fi
      done < <(extract_file_refs "$file")
    fi
    
    # Check URLs (only in report mode, not interactive due to time)
    if [ "$CHECK_LINKS" = true ] && [ "$INTERACTIVE" != true ]; then
      while IFS= read -r url; do
        if [ -n "$url" ]; then
          # Skip localhost and example URLs
          if [[ "$url" != *"localhost"* ]] && [[ "$url" != *"example.com"* ]]; then
            if ! check_url "$url"; then
              broken_links=$((broken_links + 1))
              file_issues+="- Broken link: $url\n"
            fi
          fi
        fi
      done < <(extract_urls "$file")
    fi
    
    # Add to issues if any found
    if [ -n "$file_issues" ]; then
      issues+="\n### $rel_path\n\n$file_issues"
    fi
    
    # Progress indicator
    printf "."
  done < <(find_docs)
  
  echo ""
  echo "Scan complete."
  
  # Generate report
  cat > "$REPORT_FILE" << EOF
# Documentation Review Report

**Date:** $(date +%Y-%m-%d)
**Reviewed:** $total_files files
**Staleness Threshold:** $MAX_STALE_DAYS days

## Summary

| Category | Count |
|----------|-------|
| Stale Files | $stale_files |
| Missing References | $missing_refs |
| Broken Links | $broken_links |
| **Total Issues** | **$((stale_files + missing_refs + broken_links))** |

## Issues by File
$(echo -e "$issues")

---

## Recommendations

### Immediate Actions

$(if [ $missing_refs -gt 0 ]; then echo "- Fix missing file references"; fi)
$(if [ $broken_links -gt 0 ]; then echo "- Update or remove broken links"; fi)
$(if [ $stale_files -gt 0 ]; then echo "- Review stale documentation for accuracy"; fi)

### Prevention

- Update docs when changing code
- Run \`./scripts/aha-loop/doc-cleaner.sh --report\` after each milestone
- Add doc checks to CI pipeline

---

*Generated by Aha Loop Doc Cleaner*
EOF

  echo ""
  echo "Report generated: $REPORT_FILE"
  echo ""
  echo "Summary:"
  echo "  Files scanned: $total_files"
  echo "  Stale files: $stale_files"
  echo "  Missing references: $missing_refs"
  echo "  Broken links: $broken_links"
}

# Apply safe fixes
apply_fixes() {
  echo "Applying safe auto-fixes..."
  echo ""
  
  local fixes_applied=0
  
  while IFS= read -r file; do
    local rel_path="${file#$PROJECT_ROOT/}"
    local doc_dir=$(dirname "$file")
    local fixed=false
    
    # Check for fixable issues
    while IFS= read -r ref; do
      if [ -n "$ref" ]; then
        if ! check_file_reference "$ref" "$doc_dir"; then
          # Try to find the file elsewhere
          local found=$(find "$PROJECT_ROOT" -name "$(basename "$ref")" -not -path "*/.git/*" 2>/dev/null | head -1)
          
          if [ -n "$found" ]; then
            local new_ref="${found#$PROJECT_ROOT/}"
            echo "  $rel_path: Updating reference $ref -> $new_ref"
            sed -i "s|$ref|$new_ref|g" "$file"
            fixed=true
            fixes_applied=$((fixes_applied + 1))
          fi
        fi
      fi
    done < <(extract_file_refs "$file")
    
  done < <(find_docs)
  
  echo ""
  echo "Applied $fixes_applied fixes."
}

# Interactive mode
interactive_mode() {
  echo "Interactive Documentation Review"
  echo "================================="
  echo ""
  
  while IFS= read -r file; do
    local rel_path="${file#$PROJECT_ROOT/}"
    local age=$(file_age_days "$file")
    local has_issues=false
    
    # Check if file has issues
    if [ "$age" != "unknown" ] && [ "$age" -gt "$MAX_STALE_DAYS" ]; then
      has_issues=true
    fi
    
    local missing_count=$(extract_file_refs "$file" | while read ref; do
      if [ -n "$ref" ] && ! check_file_reference "$ref" "$(dirname "$file")"; then
        echo "x"
      fi
    done | wc -l)
    
    if [ "$missing_count" -gt 0 ]; then
      has_issues=true
    fi
    
    if [ "$has_issues" = true ]; then
      echo ""
      echo "File: $rel_path"
      echo "Age: $age days"
      echo "Missing refs: $missing_count"
      echo ""
      echo "Actions:"
      echo "  [s] Skip"
      echo "  [v] View file"
      echo "  [e] Edit file"
      echo "  [d] Delete file"
      echo "  [f] Try auto-fix"
      echo "  [q] Quit"
      echo ""
      read -p "Choice: " choice
      
      case "$choice" in
        v)
          less "$file"
          ;;
        e)
          ${EDITOR:-vi} "$file"
          ;;
        d)
          read -p "Really delete $rel_path? [y/N] " confirm
          if [ "$confirm" = "y" ]; then
            rm "$file"
            echo "Deleted."
          fi
          ;;
        f)
          echo "Attempting auto-fix..."
          # Similar to apply_fixes but for single file
          ;;
        q)
          echo "Exiting."
          exit 0
          ;;
        *)
          echo "Skipping."
          ;;
      esac
    fi
  done < <(find_docs)
  
  echo ""
  echo "Review complete."
}

# Check links only
check_links_only() {
  echo "Checking external links..."
  echo ""
  
  local total=0
  local broken=0
  
  while IFS= read -r file; do
    local rel_path="${file#$PROJECT_ROOT/}"
    
    while IFS= read -r url; do
      if [ -n "$url" ]; then
        if [[ "$url" != *"localhost"* ]] && [[ "$url" != *"example.com"* ]]; then
          total=$((total + 1))
          printf "Checking: %s ... " "$url"
          
          if check_url "$url"; then
            echo "OK"
          else
            echo "BROKEN"
            echo "  Found in: $rel_path"
            broken=$((broken + 1))
          fi
        fi
      fi
    done < <(extract_urls "$file")
  done < <(find_docs)
  
  echo ""
  echo "Checked $total links, $broken broken."
}

# Check references only
check_refs_only() {
  echo "Checking code references..."
  echo ""
  
  local total=0
  local missing=0
  
  while IFS= read -r file; do
    local rel_path="${file#$PROJECT_ROOT/}"
    local doc_dir=$(dirname "$file")
    
    while IFS= read -r ref; do
      if [ -n "$ref" ]; then
        total=$((total + 1))
        
        if check_file_reference "$ref" "$doc_dir"; then
          echo "OK: $ref (in $rel_path)"
        else
          echo "MISSING: $ref (in $rel_path)"
          missing=$((missing + 1))
        fi
      fi
    done < <(extract_file_refs "$file")
  done < <(find_docs)
  
  echo ""
  echo "Checked $total references, $missing missing."
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --report)
      generate_report
      exit 0
      ;;
    --fix)
      FIX_MODE=true
      apply_fixes
      exit 0
      ;;
    --interactive)
      INTERACTIVE=true
      interactive_mode
      exit 0
      ;;
    --check-links)
      check_links_only
      exit 0
      ;;
    --check-refs)
      check_refs_only
      exit 0
      ;;
    --stale-days)
      MAX_STALE_DAYS="$2"
      shift 2
      ;;
    --stale-days=*)
      MAX_STALE_DAYS="${1#*=}"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Default action: show usage
usage
