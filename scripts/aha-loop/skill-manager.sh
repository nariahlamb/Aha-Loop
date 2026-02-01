#!/bin/bash
# Aha Loop Skill Manager - Skill Lifecycle Management
# Manages skill registration, usage tracking, and maintenance
#
# Usage:
#   ./skill-manager.sh list
#   ./skill-manager.sh stats [skill-name]
#   ./skill-manager.sh update [skill-name]
#   ./skill-manager.sh review
#   ./skill-manager.sh deprecate [skill-name] --reason "..."
#   ./skill-manager.sh validate [skill-name]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"
REGISTRY_FILE="$SKILLS_DIR/.registry.json"

# Initialize registry if not exists
init_registry() {
  if [ ! -f "$REGISTRY_FILE" ]; then
    echo '{
  "version": 1,
  "skills": {},
  "lastScan": null
}' > "$REGISTRY_FILE"
  fi
}

# Print usage
usage() {
  echo "Aha Loop Skill Manager - Skill Lifecycle Management"
  echo ""
  echo "Usage:"
  echo "  $0 list                           List all skills"
  echo "  $0 stats [SKILL]                  Show skill statistics"
  echo "  $0 update SKILL                   Update skill metadata"
  echo "  $0 use SKILL                      Record skill usage"
  echo "  $0 review                         Review all skills for maintenance"
  echo "  $0 deprecate SKILL --reason TEXT  Mark skill as deprecated"
  echo "  $0 validate [SKILL]               Validate skill structure"
  echo "  $0 scan                           Scan and register all skills"
  echo "  $0 create NAME                    Create new skill from template"
  echo ""
  echo "Examples:"
  echo "  $0 list"
  echo "  $0 stats prd"
  echo "  $0 use research"
  echo "  $0 deprecate old-skill --reason 'Replaced by new-skill'"
  echo "  $0 create my-new-skill"
}

# Parse YAML frontmatter from skill file
parse_frontmatter() {
  local file="$1"
  local field="$2"
  
  # Extract content between --- markers and parse
  sed -n '/^---$/,/^---$/p' "$file" | grep "^${field}:" | head -1 | sed "s/^${field}: *//" | tr -d '"'
}

# List all skills
cmd_list() {
  init_registry
  
  echo "Registered Skills:"
  echo ""
  printf "%-20s %-10s %-12s %-8s %s\n" "NAME" "VERSION" "STATUS" "USES" "DESCRIPTION"
  echo "--------------------------------------------------------------------------------"
  
  for skill_dir in "$SKILLS_DIR"/*/; do
    if [ -d "$skill_dir" ]; then
      local skill_file="${skill_dir}SKILL.md"
      
      if [ -f "$skill_file" ]; then
        local name=$(parse_frontmatter "$skill_file" "name")
        local version=$(parse_frontmatter "$skill_file" "version")
        local status=$(parse_frontmatter "$skill_file" "status")
        local uses=$(parse_frontmatter "$skill_file" "usageCount")
        local desc=$(parse_frontmatter "$skill_file" "description" | cut -c1-40)
        
        [ -z "$uses" ] && uses="0"
        [ -z "$status" ] && status="active"
        
        printf "%-20s %-10s %-12s %-8s %s...\n" "$name" "$version" "$status" "$uses" "$desc"
      fi
    fi
  done
  
  echo ""
}

# Show skill statistics
cmd_stats() {
  local skill_name="$1"
  
  if [ -z "$skill_name" ]; then
    # Show overall stats
    echo "Skill Statistics Overview"
    echo ""
    
    local total=0
    local active=0
    local deprecated=0
    local needs_review=0
    
    for skill_dir in "$SKILLS_DIR"/*/; do
      if [ -d "$skill_dir" ] && [ -f "${skill_dir}SKILL.md" ]; then
        total=$((total + 1))
        local status=$(parse_frontmatter "${skill_dir}SKILL.md" "status")
        
        case "$status" in
          active) active=$((active + 1)) ;;
          deprecated) deprecated=$((deprecated + 1)) ;;
          needs-review) needs_review=$((needs_review + 1)) ;;
        esac
      fi
    done
    
    echo "Total Skills: $total"
    echo "  Active: $active"
    echo "  Deprecated: $deprecated"
    echo "  Needs Review: $needs_review"
    
  else
    # Show specific skill stats
    local skill_dir="$SKILLS_DIR/$skill_name"
    local skill_file="$skill_dir/SKILL.md"
    
    if [ ! -f "$skill_file" ]; then
      echo "Skill not found: $skill_name"
      exit 1
    fi
    
    echo "Skill: $skill_name"
    echo ""
    echo "Metadata:"
    echo "  Name: $(parse_frontmatter "$skill_file" "name")"
    echo "  Version: $(parse_frontmatter "$skill_file" "version")"
    echo "  Status: $(parse_frontmatter "$skill_file" "status")"
    echo "  Created: $(parse_frontmatter "$skill_file" "created")"
    echo "  Last Used: $(parse_frontmatter "$skill_file" "lastUsed")"
    echo "  Usage Count: $(parse_frontmatter "$skill_file" "usageCount")"
    echo ""
    echo "Description:"
    echo "  $(parse_frontmatter "$skill_file" "description")"
    echo ""
    echo "File: $skill_file"
    echo "Size: $(wc -l < "$skill_file") lines"
  fi
}

# Record skill usage
cmd_use() {
  local skill_name="$1"
  
  if [ -z "$skill_name" ]; then
    echo "Error: Skill name required"
    usage
    exit 1
  fi
  
  local skill_file="$SKILLS_DIR/$skill_name/SKILL.md"
  
  if [ ! -f "$skill_file" ]; then
    echo "Skill not found: $skill_name"
    exit 1
  fi
  
  # Get current values
  local current_count=$(parse_frontmatter "$skill_file" "usageCount")
  [ -z "$current_count" ] && current_count="0"
  local new_count=$((current_count + 1))
  local today=$(date +%Y-%m-%d)
  
  # Update the file
  sed -i "s/^usageCount:.*/usageCount: $new_count/" "$skill_file"
  sed -i "s/^lastUsed:.*/lastUsed: $today/" "$skill_file"
  
  echo "Recorded usage for '$skill_name' (total: $new_count)"
}

# Update skill metadata
cmd_update() {
  local skill_name="$1"
  
  if [ -z "$skill_name" ]; then
    echo "Error: Skill name required"
    usage
    exit 1
  fi
  
  local skill_file="$SKILLS_DIR/$skill_name/SKILL.md"
  
  if [ ! -f "$skill_file" ]; then
    echo "Skill not found: $skill_name"
    exit 1
  fi
  
  echo "Updating skill: $skill_name"
  
  # Update lastUsed to today
  local today=$(date +%Y-%m-%d)
  sed -i "s/^lastUsed:.*/lastUsed: $today/" "$skill_file"
  
  echo "Updated lastUsed to $today"
}

# Review all skills for maintenance needs
cmd_review() {
  echo "Skill Review Report"
  echo "==================="
  echo ""
  
  local today=$(date +%s)
  local issues_found=0
  
  for skill_dir in "$SKILLS_DIR"/*/; do
    if [ -d "$skill_dir" ] && [ -f "${skill_dir}SKILL.md" ]; then
      local skill_file="${skill_dir}SKILL.md"
      local name=$(parse_frontmatter "$skill_file" "name")
      local status=$(parse_frontmatter "$skill_file" "status")
      local last_used=$(parse_frontmatter "$skill_file" "lastUsed")
      local uses=$(parse_frontmatter "$skill_file" "usageCount")
      
      local issues=""
      
      # Check for stale skills (not used in 30+ days)
      if [ -n "$last_used" ]; then
        local last_used_ts=$(date -d "$last_used" +%s 2>/dev/null || echo "0")
        local days_since=$(( (today - last_used_ts) / 86400 ))
        
        if [ $days_since -gt 30 ]; then
          issues+="  - Not used in $days_since days\n"
        fi
      fi
      
      # Check for low usage
      [ -z "$uses" ] && uses="0"
      if [ "$uses" -eq 0 ]; then
        issues+="  - Never used\n"
      fi
      
      # Check for needs-review status
      if [ "$status" == "needs-review" ]; then
        issues+="  - Marked as needs-review\n"
      fi
      
      # Report issues
      if [ -n "$issues" ]; then
        echo "$name:"
        echo -e "$issues"
        issues_found=$((issues_found + 1))
      fi
    fi
  done
  
  if [ $issues_found -eq 0 ]; then
    echo "All skills are in good standing."
  else
    echo ""
    echo "Found issues with $issues_found skill(s)."
    echo "Consider updating or deprecating stale skills."
  fi
}

# Deprecate a skill
cmd_deprecate() {
  local skill_name="$1"
  shift
  
  local reason=""
  
  while [[ $# -gt 0 ]]; do
    case $1 in
      --reason)
        reason="$2"
        shift 2
        ;;
      --reason=*)
        reason="${1#*=}"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
  
  if [ -z "$skill_name" ]; then
    echo "Error: Skill name required"
    usage
    exit 1
  fi
  
  if [ -z "$reason" ]; then
    echo "Error: Deprecation reason required (--reason)"
    exit 1
  fi
  
  local skill_file="$SKILLS_DIR/$skill_name/SKILL.md"
  
  if [ ! -f "$skill_file" ]; then
    echo "Skill not found: $skill_name"
    exit 1
  fi
  
  # Update status to deprecated
  sed -i "s/^status:.*/status: deprecated/" "$skill_file"
  
  # Add deprecation notice after frontmatter
  local today=$(date +%Y-%m-%d)
  sed -i "/^---$/a\\
\\
> **DEPRECATED** ($today): $reason\\
" "$skill_file"
  
  echo "Deprecated skill: $skill_name"
  echo "Reason: $reason"
}

# Validate skill structure
cmd_validate() {
  local skill_name="$1"
  local skills_to_check=()
  
  if [ -n "$skill_name" ]; then
    skills_to_check=("$skill_name")
  else
    for skill_dir in "$SKILLS_DIR"/*/; do
      if [ -d "$skill_dir" ]; then
        skills_to_check+=("$(basename "$skill_dir")")
      fi
    done
  fi
  
  local errors=0
  
  for skill in "${skills_to_check[@]}"; do
    local skill_file="$SKILLS_DIR/$skill/SKILL.md"
    local skill_errors=""
    
    if [ ! -f "$skill_file" ]; then
      echo "FAIL: $skill - SKILL.md not found"
      errors=$((errors + 1))
      continue
    fi
    
    # Check required frontmatter fields
    for field in name version description status; do
      local value=$(parse_frontmatter "$skill_file" "$field")
      if [ -z "$value" ]; then
        skill_errors+="  - Missing required field: $field\n"
      fi
    done
    
    # Check for required sections
    if ! grep -q "^## The Job" "$skill_file"; then
      skill_errors+="  - Missing section: The Job\n"
    fi
    
    if ! grep -q "^## " "$skill_file" | grep -qi "process\|step\|how"; then
      skill_errors+="  - Missing process/steps section\n"
    fi
    
    if [ -n "$skill_errors" ]; then
      echo "FAIL: $skill"
      echo -e "$skill_errors"
      errors=$((errors + 1))
    else
      echo "OK: $skill"
    fi
  done
  
  echo ""
  if [ $errors -eq 0 ]; then
    echo "All skills valid."
  else
    echo "$errors skill(s) have validation errors."
    exit 1
  fi
}

# Scan and register all skills
cmd_scan() {
  init_registry
  
  echo "Scanning skills directory..."
  
  local count=0
  
  for skill_dir in "$SKILLS_DIR"/*/; do
    if [ -d "$skill_dir" ] && [ -f "${skill_dir}SKILL.md" ]; then
      local name=$(basename "$skill_dir")
      echo "  Found: $name"
      count=$((count + 1))
    fi
  done
  
  # Update registry
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg ts "$timestamp" '.lastScan = $ts' "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp"
  mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
  
  echo ""
  echo "Scanned $count skills."
}

# Create new skill from template
cmd_create() {
  local skill_name="$1"
  
  if [ -z "$skill_name" ]; then
    echo "Error: Skill name required"
    usage
    exit 1
  fi
  
  local skill_dir="$SKILLS_DIR/$skill_name"
  local skill_file="$skill_dir/SKILL.md"
  local template="$SCRIPT_DIR/templates/skill.template.md"
  
  if [ -d "$skill_dir" ]; then
    echo "Error: Skill already exists: $skill_name"
    exit 1
  fi
  
  echo "Creating skill: $skill_name"
  
  mkdir -p "$skill_dir"
  
  if [ -f "$template" ]; then
    # Use template
    local today=$(date +%Y-%m-%d)
    sed -e "s/\[skill-name\]/$skill_name/g" \
        -e "s/\[YYYY-MM-DD\]/$today/g" \
        -e "s/\[Skill Title\]/${skill_name^} Skill/g" \
        "$template" > "$skill_file"
  else
    # Create basic structure
    cat > "$skill_file" << EOF
---
name: $skill_name
version: 1.0.0
created: $(date +%Y-%m-%d)
lastUsed: $(date +%Y-%m-%d)
usageCount: 0
status: active
description: "[Description]. Use when [situation]. Triggers on: [phrases]."
---

# ${skill_name^} Skill

[Description of what this skill does]

---

## The Job

1. [Step 1]
2. [Step 2]
3. [Step 3]

---

## When to Use

[When this skill applies]

---

## Process

### Step 1: [Name]

[Instructions]

---

## Checklist

- [ ] [Verification item]
EOF
  fi
  
  echo "Created: $skill_file"
  echo ""
  echo "Edit the skill file to complete the definition."
}

# Main command dispatch
init_registry

case "${1:-}" in
  list)
    cmd_list
    ;;
  stats)
    shift
    cmd_stats "$@"
    ;;
  update)
    shift
    cmd_update "$@"
    ;;
  use)
    shift
    cmd_use "$@"
    ;;
  review)
    cmd_review
    ;;
  deprecate)
    shift
    cmd_deprecate "$@"
    ;;
  validate)
    shift
    cmd_validate "$@"
    ;;
  scan)
    cmd_scan
    ;;
  create)
    shift
    cmd_create "$@"
    ;;
  --help|-h|"")
    usage
    ;;
  *)
    echo "Unknown command: $1"
    usage
    exit 1
    ;;
esac
