#!/bin/bash
# God Committee Awakener
# Schedules and triggers committee member awakenings
#
# Usage:
#   ./awakener.sh [command] [options]
#
# Commands:
#   random      - Awaken all members with random topic
#   scheduled   - Awaken for scheduled check
#   alert       - Awaken due to alert/anomaly
#   critical    - Critical awakening (all members, urgent)
#   freeform    - Awaken for freeform discussion
#   daemon      - Run as background daemon

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GOD_DIR="$PROJECT_ROOT/.god"
CONFIG_FILE="$GOD_DIR/config.json"

# Load configuration
load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    MIN_HOURS=$(jq -r '.awakening.randomInterval.minHours // 2' "$CONFIG_FILE")
    MAX_HOURS=$(jq -r '.awakening.randomInterval.maxHours // 8' "$CONFIG_FILE")
    readarray -t MEMBERS < <(jq -r '.council.members[]' "$CONFIG_FILE")
    readarray -t RANDOM_TOPICS < <(jq -r '.awakening.randomTopics[]' "$CONFIG_FILE")
    readarray -t SCHEDULED_CHECKS < <(jq -r '.awakening.scheduledChecks[]' "$CONFIG_FILE")
  else
    MIN_HOURS=2
    MAX_HOURS=8
    MEMBERS=("alpha" "beta" "gamma")
    RANDOM_TOPICS=(
      "Overall Code Quality Assessment"
      "Architecture Decision Review"
      "Knowledge Base Integrity Check"
      "Skill Effectiveness Review"
      "Long-term Technical Debt Assessment"
      "Open Discussion: Project Direction"
      "No Topic: Free Observation and Thinking"
    )
    SCHEDULED_CHECKS=("prd_complete" "milestone_complete" "daily")
  fi
}

load_config

# State file for daemon
STATE_FILE="$GOD_DIR/.awakener-state"
PID_FILE="$GOD_DIR/.awakener.pid"
LOG_FILE="$PROJECT_ROOT/logs/awakener.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging
log() {
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Get random topic
get_random_topic() {
  if [ ${#RANDOM_TOPICS[@]} -gt 0 ]; then
    echo "${RANDOM_TOPICS[$RANDOM % ${#RANDOM_TOPICS[@]}]}"
  else
    echo "Free Observation and Thinking"
  fi
}

# Calculate next random awakening time
calculate_next_awakening() {
  local min_seconds=$((MIN_HOURS * 3600))
  local max_seconds=$((MAX_HOURS * 3600))
  local range=$((max_seconds - min_seconds))
  local delay=$((min_seconds + RANDOM % range))
  
  echo $delay
}

# Record awakening
record_awakening() {
  local mode="$1"
  local topic="$2"
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  # Add to timeline via observer
  "$SCRIPT_DIR/observer.sh" event "awakening" "Committee awakened: $mode - $topic" 2>/dev/null || true
  
  # Update state
  jq -n \
    --arg mode "$mode" \
    --arg topic "$topic" \
    --arg ts "$timestamp" \
    '{lastAwakening: {mode: $mode, topic: $topic, timestamp: $ts}}' \
    > "$STATE_FILE"
}

#######################################
# AWAKENING MODES
#######################################

# Awaken all members
awaken_all() {
  local topic="$1"
  local mode="$2"
  local parallel="${3:-false}"
  
  log "Awakening all members: $topic (mode: $mode)"
  record_awakening "$mode" "$topic"

  # Start a council session
  if ! source "$SCRIPT_DIR/council.sh"; then
    log "ERROR: Failed to source council.sh"
    return 1
  fi
  local session_id=$(start_session "$topic" "$mode")
  log "Started session: $session_id"
  
  if [ "$parallel" = "true" ]; then
    # Run members in parallel
    for member in "${MEMBERS[@]}"; do
      log "Awakening $member..."
      "$SCRIPT_DIR/member.sh" "$member" --topic "$topic" --mode "observation" &
    done
    
    # Wait for all to complete
    wait
  else
    # Run members sequentially (for discussion)
    for member in "${MEMBERS[@]}"; do
      log "Awakening $member..."
      "$SCRIPT_DIR/member.sh" "$member" --topic "$topic" --mode "observation"
    done
  fi
  
  # End session
  end_session "Session completed for topic: $topic"
  log "Session ended"
}

# Random awakening
cmd_random() {
  local topic=$(get_random_topic)
  log "Random awakening triggered"
  awaken_all "$topic" "random" "true"
}

# Scheduled awakening
cmd_scheduled() {
  local check_type="${1:-daily}"
  local topic="Scheduled Check: $check_type"
  log "Scheduled awakening: $check_type"
  awaken_all "$topic" "scheduled" "true"
}

# Alert awakening
cmd_alert() {
  local alert_reason="${1:-Unknown anomaly detected}"
  local topic="Alert Response: $alert_reason"
  log "Alert awakening: $alert_reason"
  
  # Take snapshot first
  "$SCRIPT_DIR/observer.sh" snapshot 2>/dev/null || true
  
  # Awaken sequentially for coordinated response
  awaken_all "$topic" "alert" "false"
}

# Critical awakening
cmd_critical() {
  local reason="${1:-Critical situation}"
  local topic="Critical Situation: $reason"
  log "CRITICAL awakening: $reason"
  
  # Terminate ongoing processes
  "$SCRIPT_DIR/powers.sh" pause "Critical awakening: $reason" "awakener" 2>/dev/null || true
  
  # Take snapshot
  "$SCRIPT_DIR/observer.sh" snapshot 2>/dev/null || true
  
  # Awaken all immediately
  awaken_all "$topic" "critical" "false"
}

# Milestone awakening
cmd_milestone() {
  local milestone="${1:-Unknown milestone}"
  local topic="Milestone Complete: $milestone"
  log "Milestone awakening: $milestone"
  awaken_all "$topic" "milestone" "true"
}

# Freeform awakening
cmd_freeform() {
  local topic="${1:-Open Discussion}"
  log "Freeform awakening: $topic"
  awaken_all "$topic" "freeform" "false"
}

# Single member awakening
cmd_single() {
  local member="$1"
  local topic="${2:-$(get_random_topic)}"
  local mode="${3:-observation}"
  
  if [ -z "$member" ]; then
    echo "Error: Member ID required"
    exit 1
  fi
  
  log "Single awakening: $member for $topic"
  record_awakening "single" "$topic"
  
  "$SCRIPT_DIR/member.sh" "$member" --topic "$topic" --mode "$mode"
}

#######################################
# DAEMON MODE
#######################################

# Check for events that should trigger awakening
check_triggers() {
  # Check for anomalies
  local anomaly_count
  anomaly_count=$(jq '.anomalies | length // 0' "$GOD_DIR/observation/anomalies.json" 2>/dev/null) || anomaly_count=0
  [ -z "$anomaly_count" ] && anomaly_count=0

  local critical_anomalies
  critical_anomalies=$(jq '[.anomalies[] | select(.severity == "error")] | length // 0' "$GOD_DIR/observation/anomalies.json" 2>/dev/null) || critical_anomalies=0
  [ -z "$critical_anomalies" ] && critical_anomalies=0
  
  if [ "$critical_anomalies" -gt 0 ]; then
    log "Critical anomalies detected: $critical_anomalies"
    cmd_alert "Detected $critical_anomalies critical anomalies"
    return 0
  fi
  
  # Check for milestone completion
  if [ -f "$PROJECT_ROOT/.milestone-completed" ]; then
    local milestone=$(cat "$PROJECT_ROOT/.milestone-completed")
    rm -f "$PROJECT_ROOT/.milestone-completed"
    cmd_milestone "$milestone"
    return 0
  fi
  
  # Check for PRD completion
  if [ -f "$PROJECT_ROOT/.prd-completed" ]; then
    local prd=$(cat "$PROJECT_ROOT/.prd-completed")
    rm -f "$PROJECT_ROOT/.prd-completed"
    cmd_scheduled "prd_complete"
    return 0
  fi
  
  return 1
}

# Run as daemon
cmd_daemon() {
  local interval="${1:-300}"  # Default 5 minutes between checks
  
  # Check if already running
  if [ -f "$PID_FILE" ]; then
    local old_pid=$(cat "$PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
      echo "Awakener daemon already running (PID: $old_pid)"
      return 1
    fi
  fi
  
  echo "Starting awakener daemon (interval: ${interval}s)"
  echo "Logs: $LOG_FILE"
  
  # Save PID
  echo $$ > "$PID_FILE"
  
  # Calculate initial next awakening time
  local next_random=$(($(date +%s) + $(calculate_next_awakening)))
  
  log "Daemon started (PID: $$)"
  log "Next random awakening: $(date -d @$next_random)"
  
  # Main loop
  while true; do
    local now=$(date +%s)
    
    # Check for event triggers
    check_triggers || true
    
    # Check if random awakening is due
    if [ $now -ge $next_random ]; then
      cmd_random
      next_random=$(($(date +%s) + $(calculate_next_awakening)))
      log "Next random awakening: $(date -d @$next_random)"
    fi
    
    # Sleep
    sleep "$interval"
  done
}

# Stop daemon
cmd_stop() {
  if [ -f "$PID_FILE" ]; then
    local pid=$(cat "$PID_FILE")
    if kill -15 "$pid" 2>/dev/null; then
      rm -f "$PID_FILE"
      log "Daemon stopped (PID: $pid)"
      echo "Daemon stopped"
    else
      rm -f "$PID_FILE"
      echo "Daemon not running (stale PID file removed)"
    fi
  else
    echo "Daemon not running"
  fi
}

# Daemon status
cmd_daemon_status() {
  if [ -f "$PID_FILE" ]; then
    local pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "Awakener daemon is RUNNING (PID: $pid)"
      
      if [ -f "$STATE_FILE" ]; then
        echo ""
        echo "Last awakening:"
        cat "$STATE_FILE" | jq '.lastAwakening'
      fi
      
      return 0
    else
      echo "Awakener daemon is STOPPED (stale PID file)"
      rm -f "$PID_FILE"
      return 1
    fi
  else
    echo "Awakener daemon is STOPPED"
    return 1
  fi
}

#######################################
# SCHEDULE MANAGEMENT
#######################################

# Show schedule
cmd_schedule() {
  echo "=== Awakening Schedule ==="
  echo ""
  echo "Random Interval: ${MIN_HOURS}h - ${MAX_HOURS}h"
  echo ""
  echo "Scheduled Checks:"
  for check in "${SCHEDULED_CHECKS[@]}"; do
    echo "  - $check"
  done
  echo ""
  echo "Random Topics:"
  for topic in "${RANDOM_TOPICS[@]}"; do
    echo "  - $topic"
  done
  echo ""
  
  if [ -f "$STATE_FILE" ]; then
    echo "Last Awakening:"
    cat "$STATE_FILE" | jq '.lastAwakening'
  fi
}

# Trigger next scheduled check
cmd_next() {
  local check_type="${SCHEDULED_CHECKS[0]:-daily}"
  cmd_scheduled "$check_type"
}

#######################################
# MAIN
#######################################

case "${1:-status}" in
  random)
    cmd_random
    ;;
  scheduled)
    cmd_scheduled "$2"
    ;;
  alert)
    cmd_alert "$2"
    ;;
  critical)
    cmd_critical "$2"
    ;;
  milestone)
    cmd_milestone "$2"
    ;;
  freeform)
    cmd_freeform "$2"
    ;;
  single)
    cmd_single "$2" "$3" "$4"
    ;;
  daemon)
    cmd_daemon "$2"
    ;;
  stop)
    cmd_stop
    ;;
  status)
    cmd_daemon_status
    ;;
  schedule)
    cmd_schedule
    ;;
  next)
    cmd_next
    ;;
  *)
    echo "God Committee Awakener"
    echo ""
    echo "Usage: $0 COMMAND [options]"
    echo ""
    echo "Awakening Commands:"
    echo "  random                    - Random topic awakening"
    echo "  scheduled [CHECK]         - Scheduled check (daily/prd_complete/milestone_complete)"
    echo "  alert [REASON]            - Alert-triggered awakening"
    echo "  critical [REASON]         - Critical situation awakening"
    echo "  milestone [NAME]          - Milestone completion awakening"
    echo "  freeform [TOPIC]          - Freeform discussion"
    echo "  single MEMBER [TOPIC]     - Awaken single member"
    echo ""
    echo "Daemon Commands:"
    echo "  daemon [INTERVAL]         - Run as background daemon (default: 300s)"
    echo "  stop                      - Stop daemon"
    echo "  status                    - Daemon status"
    echo ""
    echo "Schedule:"
    echo "  schedule                  - Show awakening schedule"
    echo "  next                      - Trigger next scheduled check"
    exit 1
    ;;
esac
