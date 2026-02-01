#!/bin/bash
# God Committee Powers
# Provides intervention and repair capabilities
#
# Usage:
#   ./powers.sh [command] [options]
#
# Commands:
#   terminate   - Terminate running processes
#   rollback    - Rollback to previous state
#   modify      - Modify code/config
#   repair      - Auto-repair common issues
#   pause       - Pause execution
#   resume      - Resume execution

set -e

# Enable globstar for ** pattern
shopt -s globstar nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GOD_DIR="$PROJECT_ROOT/.god"
CONFIG_FILE="$GOD_DIR/config.json"
POWERS_DIR="$GOD_DIR/powers"

# Source council for logging
if ! source "$SCRIPT_DIR/council.sh" 2>/dev/null; then
  echo "WARNING: Failed to source council.sh, some features may be unavailable" >&2
fi

# Load power configuration
load_power_config() {
  if [ -f "$CONFIG_FILE" ]; then
    ALLOW_TERMINATION=$(jq -r '.powers.allowTermination // true' "$CONFIG_FILE")
    ALLOW_ROLLBACK=$(jq -r '.powers.allowRollback // true' "$CONFIG_FILE")
    ALLOW_CODE_MOD=$(jq -r '.powers.allowCodeModification // true' "$CONFIG_FILE")
    ALLOW_SKILL_MOD=$(jq -r '.powers.allowSkillModification // true' "$CONFIG_FILE")
    ALLOW_PROCESS_KILL=$(jq -r '.powers.allowProcessKill // true' "$CONFIG_FILE")
    readarray -t REQUIRE_CONSENSUS < <(jq -r '.powers.requireConsensusFor[]' "$CONFIG_FILE" 2>/dev/null)
  else
    ALLOW_TERMINATION=true
    ALLOW_ROLLBACK=true
    ALLOW_CODE_MOD=true
    ALLOW_SKILL_MOD=true
    ALLOW_PROCESS_KILL=true
    REQUIRE_CONSENSUS=()
  fi
}

load_power_config

# Log intervention
log_intervention() {
  local type="$1"
  local description="$2"
  local member="${3:-system}"
  local result="${4:-success}"
  
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local intervention_id="int-$(date +%s)-$RANDOM"
  
  local intervention=$(jq -n \
    --arg id "$intervention_id" \
    --arg type "$type" \
    --arg desc "$description" \
    --arg member "$member" \
    --arg result "$result" \
    --arg ts "$timestamp" \
    '{
      id: $id,
      type: $type,
      description: $desc,
      member: $member,
      result: $result,
      timestamp: $ts
    }')
  
  jq --argjson int "$intervention" \
     '.interventions += [$int]' \
     "$POWERS_DIR/interventions.json" > "$POWERS_DIR/interventions.json.tmp"
  mv "$POWERS_DIR/interventions.json.tmp" "$POWERS_DIR/interventions.json"
  
  echo "Intervention logged: $intervention_id"
}

# Log repair
log_repair() {
  local type="$1"
  local description="$2"
  local details="${3:-}"
  local result="${4:-success}"
  
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local repair_id="rep-$(date +%s)-$RANDOM"
  
  local repair=$(jq -n \
    --arg id "$repair_id" \
    --arg type "$type" \
    --arg desc "$description" \
    --arg details "$details" \
    --arg result "$result" \
    --arg ts "$timestamp" \
    '{
      id: $id,
      type: $type,
      description: $desc,
      details: $details,
      result: $result,
      timestamp: $ts
    }')
  
  jq --argjson rep "$repair" \
     '.repairs += [$rep]' \
     "$POWERS_DIR/repairs.json" > "$POWERS_DIR/repairs.json.tmp"
  mv "$POWERS_DIR/repairs.json.tmp" "$POWERS_DIR/repairs.json"
  
  echo "Repair logged: $repair_id"
}

#######################################
# TERMINATION POWERS
#######################################

# Terminate a specific process
cmd_terminate() {
  local target="$1"
  local member="${2:-god-committee}"
  
  if [ "$ALLOW_TERMINATION" != "true" ]; then
    echo "ERROR: Termination power is disabled"
    return 1
  fi
  
  case "$target" in
    orchestrator)
      echo "Terminating orchestrator..."
      pkill -f "orchestrator.sh" 2>/dev/null && echo "Orchestrator terminated" || echo "No orchestrator running"
      log_intervention "terminate" "Terminated orchestrator.sh" "$member"
      ;;
    aha-loop)
      echo "Terminating Aha Loop execution..."
      pkill -f "aha-loop.sh" 2>/dev/null && echo "Aha Loop execution terminated" || echo "No Aha Loop execution running"
      log_intervention "terminate" "Terminated Aha Loop execution" "$member"
      ;;
    explorer)
      echo "Terminating parallel explorer..."
      pkill -f "parallel-explorer.sh" 2>/dev/null && echo "Explorer terminated" || echo "No explorer running"
      log_intervention "terminate" "Terminated parallel-explorer.sh" "$member"
      ;;
    all)
      echo "Terminating all execution layer processes..."
      pkill -f "orchestrator.sh" 2>/dev/null || true
      pkill -f "aha-loop.sh" 2>/dev/null || true
      pkill -f "parallel-explorer.sh" 2>/dev/null || true
      pkill -f "amp " 2>/dev/null || true
      pkill -f "claude " 2>/dev/null || true
      echo "All processes terminated"
      log_intervention "terminate" "Terminated all execution layer processes" "$member"
      ;;
    pid:*)
      local pid="${target#pid:}"
      echo "Terminating PID $pid..."
      if kill -15 "$pid" 2>/dev/null; then
        echo "Process $pid terminated (SIGTERM)"
        log_intervention "terminate" "Terminated process PID $pid" "$member"
      else
        echo "Failed to terminate PID $pid"
        return 1
      fi
      ;;
    *)
      echo "Unknown target: $target"
      echo "Valid targets: orchestrator, aha-loop, explorer, all, pid:NUMBER"
      return 1
      ;;
  esac
}

# Force kill (SIGKILL)
cmd_kill() {
  local target="$1"
  local member="${2:-god-committee}"
  
  if [ "$ALLOW_PROCESS_KILL" != "true" ]; then
    echo "ERROR: Process kill power is disabled"
    return 1
  fi
  
  case "$target" in
    pid:*)
      local pid="${target#pid:}"
      echo "Force killing PID $pid..."
      if kill -9 "$pid" 2>/dev/null; then
        echo "Process $pid killed (SIGKILL)"
        log_intervention "kill" "Force killed process PID $pid" "$member"
      else
        echo "Failed to kill PID $pid"
        return 1
      fi
      ;;
    *)
      # Try to terminate first
      cmd_terminate "$target" "$member"
      sleep 2
      # Then force kill
      case "$target" in
        orchestrator)
          pkill -9 -f "orchestrator.sh" 2>/dev/null || true
          ;;
        aha-loop)
          pkill -9 -f "aha-loop.sh" 2>/dev/null || true
          ;;
        explorer)
          pkill -9 -f "parallel-explorer.sh" 2>/dev/null || true
          ;;
        all)
          pkill -9 -f "orchestrator.sh" 2>/dev/null || true
          pkill -9 -f "aha-loop.sh" 2>/dev/null || true
          pkill -9 -f "parallel-explorer.sh" 2>/dev/null || true
          pkill -9 -f "amp " 2>/dev/null || true
          pkill -9 -f "claude " 2>/dev/null || true
          ;;
      esac
      log_intervention "kill" "Force killed $target" "$member"
      ;;
  esac
}

#######################################
# ROLLBACK POWERS
#######################################

# Git rollback
cmd_rollback() {
  local target="${1:-HEAD~1}"
  local mode="${2:-soft}"
  local member="${3:-god-committee}"
  
  if [ "$ALLOW_ROLLBACK" != "true" ]; then
    echo "ERROR: Rollback power is disabled"
    return 1
  fi
  
  echo "Rolling back to $target (mode: $mode)..."
  
  cd "$PROJECT_ROOT"
  
  # Save current state
  local current_hash=$(git rev-parse HEAD)
  local stash_needed=false
  
  if ! git diff --quiet 2>/dev/null; then
    echo "Stashing uncommitted changes..."
    git stash push -m "God Committee rollback backup $(date +%Y%m%d%H%M%S)"
    stash_needed=true
  fi
  
  case "$mode" in
    soft)
      git reset --soft "$target"
      echo "Soft reset to $target (changes preserved in staging)"
      ;;
    mixed)
      git reset --mixed "$target"
      echo "Mixed reset to $target (changes preserved in working directory)"
      ;;
    hard)
      git reset --hard "$target"
      echo "Hard reset to $target (all changes discarded)"
      ;;
    *)
      echo "Unknown mode: $mode (use: soft, mixed, hard)"
      return 1
      ;;
  esac
  
  log_intervention "rollback" "Rolled back from $current_hash to $target ($mode)" "$member"
  
  if [ "$stash_needed" = "true" ]; then
    echo ""
    echo "NOTE: Uncommitted changes were stashed. Use 'git stash pop' to restore."
  fi
}

# Restore from stash
cmd_restore_stash() {
  local member="${1:-god-committee}"
  
  cd "$PROJECT_ROOT"
  
  if git stash list | grep -q "God Committee"; then
    local stash_ref=$(git stash list | grep "God Committee" | head -1 | cut -d: -f1)
    git stash pop "$stash_ref"
    echo "Restored stashed changes"
    log_intervention "restore" "Restored stashed changes from $stash_ref" "$member"
  else
    echo "No God Committee stash found"
  fi
}

#######################################
# PAUSE/RESUME POWERS
#######################################

# Create pause flag
cmd_pause() {
  local reason="${1:-God Committee intervention}"
  local member="${2:-god-committee}"
  
  echo "Creating pause flag..."
  
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  jq -n \
    --arg reason "$reason" \
    --arg member "$member" \
    --arg ts "$timestamp" \
    '{paused: true, reason: $reason, by: $member, at: $ts}' \
    > "$GOD_DIR/.pause"
  
  echo "Execution paused: $reason"
  log_intervention "pause" "Paused execution: $reason" "$member"
  
  # Signal running processes
  pkill -USR1 -f "orchestrator.sh" 2>/dev/null || true
  pkill -USR1 -f "aha-loop.sh" 2>/dev/null || true
}

# Remove pause flag
cmd_resume() {
  local member="${1:-god-committee}"
  
  if [ -f "$GOD_DIR/.pause" ]; then
    rm -f "$GOD_DIR/.pause"
    echo "Execution resumed"
    log_intervention "resume" "Resumed execution" "$member"
    
    # Signal running processes
    pkill -USR2 -f "orchestrator.sh" 2>/dev/null || true
    pkill -USR2 -f "aha-loop.sh" 2>/dev/null || true
  else
    echo "Execution is not paused"
  fi
}

# Check pause status
cmd_pause_status() {
  if [ -f "$GOD_DIR/.pause" ]; then
    echo "Execution is PAUSED"
    cat "$GOD_DIR/.pause" | jq '.'
    return 0
  else
    echo "Execution is RUNNING"
    return 1
  fi
}

#######################################
# REPAIR POWERS
#######################################

# Auto-repair common issues
cmd_repair() {
  local issue="$1"
  local member="${2:-god-committee}"
  
  echo "Attempting repair: $issue"
  
  case "$issue" in
    lock)
      # Clear stale locks
      echo "Clearing stale locks..."
      rm -f "$GOD_DIR/council/chamber.lock"
      rm -f "$GOD_DIR/council/chamber.lock.tmp"
      echo "Locks cleared"
      log_repair "lock" "Cleared stale council locks" "" "success"
      ;;
      
    worktrees)
      # Clean up orphaned worktrees
      echo "Cleaning up worktrees..."
      if [ -d "$PROJECT_ROOT/.worktrees" ]; then
        cd "$PROJECT_ROOT"
        git worktree prune
        # Remove directories that aren't valid worktrees
        for dir in "$PROJECT_ROOT/.worktrees"/*; do
          if [ -d "$dir" ]; then
            if ! git worktree list | grep -q "$dir"; then
              echo "Removing orphaned directory: $dir"
              rm -rf "$dir"
            fi
          fi
        done
      fi
      echo "Worktrees cleaned"
      log_repair "worktrees" "Cleaned up orphaned worktrees" "" "success"
      ;;
      
    json)
      # Repair corrupted JSON files
      echo "Checking JSON files..."
      local repaired=0
      
      for json_file in "$GOD_DIR"/**/*.json; do
        if [ -f "$json_file" ]; then
          if ! jq '.' "$json_file" > /dev/null 2>&1; then
            echo "Repairing: $json_file"
            # Try to backup and recreate
            mv "$json_file" "$json_file.corrupted"
            echo '{}' > "$json_file"
            repaired=$((repaired + 1))
          fi
        fi
      done
      
      echo "Repaired $repaired JSON files"
      log_repair "json" "Repaired $repaired corrupted JSON files" "" "success"
      ;;
      
    logs)
      # Clean up large log files
      echo "Cleaning up logs..."
      if [ -d "$PROJECT_ROOT/logs" ]; then
        for log_file in "$PROJECT_ROOT/logs"/*.md; do
          if [ -f "$log_file" ]; then
            local size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo "0")
            if [ "$size" -gt 10485760 ]; then  # 10MB
              echo "Truncating large log: $log_file"
              tail -n 1000 "$log_file" > "$log_file.tmp"
              mv "$log_file.tmp" "$log_file"
            fi
          fi
        done
      fi
      echo "Logs cleaned"
      log_repair "logs" "Truncated large log files" "" "success"
      ;;
      
    permissions)
      # Fix script permissions
      echo "Fixing script permissions..."
      find "$PROJECT_ROOT/scripts" -name "*.sh" -exec chmod +x {} \;
      echo "Permissions fixed"
      log_repair "permissions" "Fixed script permissions" "" "success"
      ;;
      
    git)
      # Clean up git state
      echo "Cleaning git state..."
      cd "$PROJECT_ROOT"
      git gc --auto
      git prune
      echo "Git state cleaned"
      log_repair "git" "Cleaned git state" "" "success"
      ;;
      
    all)
      # Run all repairs
      cmd_repair "lock" "$member"
      cmd_repair "worktrees" "$member"
      cmd_repair "json" "$member"
      cmd_repair "logs" "$member"
      cmd_repair "permissions" "$member"
      cmd_repair "git" "$member"
      ;;
      
    *)
      echo "Unknown issue type: $issue"
      echo "Valid types: lock, worktrees, json, logs, permissions, git, all"
      return 1
      ;;
  esac
}

#######################################
# MODIFICATION POWERS
#######################################

# Modify a file (for simple edits)
cmd_modify() {
  local file="$1"
  local action="$2"
  local value="$3"
  local member="${4:-god-committee}"
  
  if [ "$ALLOW_CODE_MOD" != "true" ]; then
    echo "ERROR: Code modification power is disabled"
    return 1
  fi
  
  case "$action" in
    append)
      echo "$value" >> "$file"
      echo "Appended to $file"
      log_intervention "modify" "Appended content to $file" "$member"
      ;;
    prepend)
      local tmp=$(mktemp)
      trap "rm -f '$tmp'" EXIT
      echo "$value" > "$tmp"
      cat "$file" >> "$tmp"
      mv "$tmp" "$file"
      trap - EXIT
      echo "Prepended to $file"
      log_intervention "modify" "Prepended content to $file" "$member"
      ;;
    replace)
      echo "$value" > "$file"
      echo "Replaced $file"
      log_intervention "modify" "Replaced content of $file" "$member"
      ;;
    *)
      echo "Unknown action: $action (use: append, prepend, replace)"
      return 1
      ;;
  esac
}

# Modify skill
cmd_modify_skill() {
  local skill="$1"
  local action="$2"
  local member="${3:-god-committee}"
  
  if [ "$ALLOW_SKILL_MOD" != "true" ]; then
    echo "ERROR: Skill modification power is disabled"
    return 1
  fi
  
  local skill_dir="$PROJECT_ROOT/.claude/skills/$skill"
  
  case "$action" in
    disable)
      if [ -d "$skill_dir" ]; then
        mv "$skill_dir" "${skill_dir}.disabled"
        echo "Skill $skill disabled"
        log_intervention "skill_modify" "Disabled skill: $skill" "$member"
      else
        echo "Skill not found: $skill"
        return 1
      fi
      ;;
    enable)
      if [ -d "${skill_dir}.disabled" ]; then
        mv "${skill_dir}.disabled" "$skill_dir"
        echo "Skill $skill enabled"
        log_intervention "skill_modify" "Enabled skill: $skill" "$member"
      else
        echo "Disabled skill not found: $skill"
        return 1
      fi
      ;;
    *)
      echo "Unknown action: $action (use: disable, enable)"
      return 1
      ;;
  esac
}

#######################################
# STATUS AND HISTORY
#######################################

# Show power usage history
cmd_history() {
  local type="${1:-all}"
  local count="${2:-20}"
  
  echo "=== Power Usage History ==="
  echo ""
  
  if [ "$type" = "all" ] || [ "$type" = "interventions" ]; then
    echo "## Recent Interventions"
    jq -r ".interventions[-$count:][] | \"\(.timestamp) [\(.type)] \(.description) (by \(.member))\"" \
       "$POWERS_DIR/interventions.json" 2>/dev/null || echo "No interventions"
    echo ""
  fi
  
  if [ "$type" = "all" ] || [ "$type" = "repairs" ]; then
    echo "## Recent Repairs"
    jq -r ".repairs[-$count:][] | \"\(.timestamp) [\(.type)] \(.description)\"" \
       "$POWERS_DIR/repairs.json" 2>/dev/null || echo "No repairs"
  fi
}

# Show current status
cmd_status() {
  echo "=== God Committee Powers Status ==="
  echo ""
  echo "Permissions:"
  echo "  Termination: $ALLOW_TERMINATION"
  echo "  Rollback: $ALLOW_ROLLBACK"
  echo "  Code Modification: $ALLOW_CODE_MOD"
  echo "  Skill Modification: $ALLOW_SKILL_MOD"
  echo "  Process Kill: $ALLOW_PROCESS_KILL"
  echo ""
  
  cmd_pause_status
  echo ""
  
  echo "Running Processes:"
  pgrep -a -f "orchestrator.sh" 2>/dev/null || echo "  orchestrator: not running"
  pgrep -a -f "aha-loop.sh" 2>/dev/null || echo "  aha-loop: not running"
  pgrep -a -f "parallel-explorer.sh" 2>/dev/null || echo "  explorer: not running"
}

#######################################
# MAIN
#######################################

case "${1:-status}" in
  terminate)
    cmd_terminate "$2" "$3"
    ;;
  kill)
    cmd_kill "$2" "$3"
    ;;
  rollback)
    cmd_rollback "$2" "$3" "$4"
    ;;
  restore-stash)
    cmd_restore_stash "$2"
    ;;
  pause)
    cmd_pause "$2" "$3"
    ;;
  resume)
    cmd_resume "$2"
    ;;
  pause-status)
    cmd_pause_status
    ;;
  repair)
    cmd_repair "$2" "$3"
    ;;
  modify)
    cmd_modify "$2" "$3" "$4" "$5"
    ;;
  modify-skill)
    cmd_modify_skill "$2" "$3" "$4"
    ;;
  history)
    cmd_history "$2" "$3"
    ;;
  status)
    cmd_status
    ;;
  *)
    echo "God Committee Powers"
    echo ""
    echo "Usage: $0 COMMAND [options]"
    echo ""
    echo "Termination:"
    echo "  terminate TARGET [MEMBER]  - Graceful termination (SIGTERM)"
    echo "  kill TARGET [MEMBER]       - Force kill (SIGKILL)"
    echo ""
    echo "Rollback:"
    echo "  rollback [TARGET] [MODE]   - Git rollback (soft/mixed/hard)"
    echo "  restore-stash [MEMBER]     - Restore stashed changes"
    echo ""
    echo "Pause/Resume:"
    echo "  pause [REASON] [MEMBER]    - Pause execution"
    echo "  resume [MEMBER]            - Resume execution"
    echo "  pause-status               - Check pause status"
    echo ""
    echo "Repair:"
    echo "  repair ISSUE [MEMBER]      - Auto-repair (lock/worktrees/json/logs/permissions/git/all)"
    echo ""
    echo "Modification:"
    echo "  modify FILE ACTION VALUE   - Modify file (append/prepend/replace)"
    echo "  modify-skill SKILL ACTION  - Modify skill (disable/enable)"
    echo ""
    echo "Status:"
    echo "  history [TYPE] [COUNT]     - Show usage history"
    echo "  status                     - Show current status"
    exit 1
    ;;
esac
