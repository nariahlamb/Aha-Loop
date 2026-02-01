#!/bin/bash
# God Committee Observer
# Monitors the execution layer and collects system state
#
# Usage:
#   ./observer.sh [command] [options]
#
# Commands:
#   snapshot    - Take a full system state snapshot
#   watch       - Continuous monitoring mode
#   check       - Run health checks
#   anomaly     - Check for anomalies
#   timeline    - Show recent events
#   report      - Generate observation report

set -e

# Enable globstar for ** pattern
shopt -s globstar nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GOD_DIR="$PROJECT_ROOT/.god"
CONFIG_FILE="$GOD_DIR/config.json"
OBS_DIR="$GOD_DIR/observation"

# Load configuration
readarray -t WATCH_PATHS < <(jq -r '.observation.watchPaths[]' "$CONFIG_FILE" 2>/dev/null)
readarray -t ALERT_PATTERNS < <(jq -r '.observation.alertPatterns[]' "$CONFIG_FILE" 2>/dev/null)
[ ${#ALERT_PATTERNS[@]} -eq 0 ] && ALERT_PATTERNS=("error" "failed")

#######################################
# SYSTEM STATE SNAPSHOT
#######################################

# Collect execution layer state
collect_execution_state() {
  local orchestrator_running="false"
  local current_phase=""
  local current_prd=""
  local current_story=""
  
  # Check if orchestrator is running
  if pgrep -f "orchestrator.sh" > /dev/null 2>&1; then
    orchestrator_running="true"
  fi
  
  # Check for running Aha Loop execution processes
  if pgrep -f "aha-loop.sh" > /dev/null 2>&1; then
    current_phase="aha_loop_execution"
  fi
  
  # Try to read current PRD
  if [ -f "$PROJECT_ROOT/project.roadmap.json" ]; then
    current_prd=$(jq -r '.prds[] | select(.status == "in_progress") | .id' "$PROJECT_ROOT/project.roadmap.json" 2>/dev/null | head -1)
  fi
  
  # Try to read current story from any prd.json
  if [ -n "$current_prd" ] && [ -f "$PROJECT_ROOT/docs/prd/$current_prd/prd.json" ]; then
    current_story=$(jq -r '.stories[] | select(.status == "in_progress") | .id' "$PROJECT_ROOT/docs/prd/$current_prd/prd.json" 2>/dev/null | head -1)
  fi
  
  jq -n \
    --argjson running "$orchestrator_running" \
    --arg phase "$current_phase" \
    --arg prd "$current_prd" \
    --arg story "$current_story" \
    '{
      orchestratorRunning: $running,
      currentPhase: (if $phase == "" then null else $phase end),
      currentPRD: (if $prd == "" then null else $prd end),
      currentStory: (if $story == "" then null else $story end)
    }'
}

# Collect health metrics
collect_health_metrics() {
  local last_test_run=""
  local tests_passing="null"
  local lint_errors="0"
  local type_errors=""
  
  # Check for test results
  if [ -f "$PROJECT_ROOT/test-results.json" ]; then
    tests_passing=$(jq '.success // null' "$PROJECT_ROOT/test-results.json")
  fi
  
  # Count lint errors in logs
  if [ -f "$PROJECT_ROOT/logs/ai-thoughts.md" ]; then
    local le_val
    le_val=$(grep -c "lint error\|linter error" "$PROJECT_ROOT/logs/ai-thoughts.md" 2>/dev/null) || le_val="0"
    lint_errors="$le_val"
  fi
  
  jq -n \
    --arg test_run "$last_test_run" \
    --argjson passing "$tests_passing" \
    --arg lint "$lint_errors" \
    --arg type "$type_errors" \
    '{
      lastTestRun: (if $test_run == "" then null else $test_run end),
      testsPassing: $passing,
      lintErrors: (if $lint == "" then null else ($lint | tonumber) end),
      typeErrors: (if $type == "" then null else ($type | tonumber) end)
    }'
}

# Collect progress metrics
collect_progress_metrics() {
  local completed_prds=0
  local completed_milestones=0
  local total_stories=0
  local completed_stories=0
  
  # Read from roadmap
  if [ -f "$PROJECT_ROOT/project.roadmap.json" ]; then
    local cp_val=$(jq '[.prds[]? | select(.status == "completed")] | length' "$PROJECT_ROOT/project.roadmap.json" 2>/dev/null)
    local cm_val=$(jq '[.milestones[]? | select(.status == "completed")] | length' "$PROJECT_ROOT/project.roadmap.json" 2>/dev/null)
    [ -n "$cp_val" ] && [ "$cp_val" != "null" ] && completed_prds="$cp_val"
    [ -n "$cm_val" ] && [ "$cm_val" != "null" ] && completed_milestones="$cm_val"
  fi
  
  # Read from PRD files
  for prd_file in "$PROJECT_ROOT"/docs/prd/*/prd.json; do
    if [ -f "$prd_file" ]; then
      local ts_val=$(jq '.stories | length' "$prd_file" 2>/dev/null)
      local cs_val=$(jq '[.stories[]? | select(.status == "completed")] | length' "$prd_file" 2>/dev/null)
      [ -n "$ts_val" ] && [ "$ts_val" != "null" ] && total_stories=$((total_stories + ts_val))
      [ -n "$cs_val" ] && [ "$cs_val" != "null" ] && completed_stories=$((completed_stories + cs_val))
    fi
  done
  
  # Ensure values are valid integers
  [ -z "$completed_prds" ] && completed_prds=0
  [ -z "$completed_milestones" ] && completed_milestones=0
  [ -z "$total_stories" ] && total_stories=0
  [ -z "$completed_stories" ] && completed_stories=0
  
  jq -n \
    --argjson cp "$completed_prds" \
    --argjson cm "$completed_milestones" \
    --argjson ts "$total_stories" \
    --argjson cs "$completed_stories" \
    '{
      completedPRDs: $cp,
      completedMilestones: $cm,
      totalStories: $ts,
      completedStories: $cs
    }'
}

# Collect resource usage
collect_resource_usage() {
  local active_worktrees=0
  local vendor_size=""
  local log_size=""
  
  # Count worktrees
  if [ -d "$PROJECT_ROOT/.worktrees" ]; then
    local wt_count=$(ls -1 "$PROJECT_ROOT/.worktrees" 2>/dev/null | wc -l | tr -d ' ')
    [ -n "$wt_count" ] && active_worktrees="$wt_count"
  fi
  
  # Get vendor size
  if [ -d "$PROJECT_ROOT/.vendor" ]; then
    vendor_size=$(du -sh "$PROJECT_ROOT/.vendor" 2>/dev/null | cut -f1)
  fi
  
  # Get log size
  if [ -d "$PROJECT_ROOT/logs" ]; then
    log_size=$(du -sh "$PROJECT_ROOT/logs" 2>/dev/null | cut -f1)
  fi
  
  # Ensure active_worktrees is numeric
  active_worktrees=$(echo "$active_worktrees" | tr -d '[:space:]')
  [ -z "$active_worktrees" ] && active_worktrees=0
  
  jq -n \
    --argjson wt "$active_worktrees" \
    --arg vs "$vendor_size" \
    --arg ls "$log_size" \
    '{
      activeWorktrees: $wt,
      vendorSize: (if $vs == "" then null else $vs end),
      logSize: (if $ls == "" then null else $ls end)
    }'
}

# Take full snapshot
take_snapshot() {
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  local execution=$(collect_execution_state)
  local health=$(collect_health_metrics)
  local progress=$(collect_progress_metrics)
  local resources=$(collect_resource_usage)
  
  local snapshot=$(jq -n \
    --arg version "1" \
    --arg ts "$timestamp" \
    --argjson exec "$execution" \
    --argjson health "$health" \
    --argjson progress "$progress" \
    --argjson resources "$resources" \
    '{
      version: ($version | tonumber),
      lastUpdated: $ts,
      execution: $exec,
      health: $health,
      progress: $progress,
      resources: $resources
    }')
  
  echo "$snapshot" > "$OBS_DIR/system-state.json"
  
  # Add to timeline
  add_timeline_event "snapshot" "System state snapshot taken" "$snapshot"
  
  echo "Snapshot taken at $timestamp"
  echo "$snapshot" | jq '.'
}

#######################################
# ANOMALY DETECTION
#######################################

# Check for anomalies
check_anomalies() {
  local anomalies=()
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  echo "Checking for anomalies..."
  
  # Check for error patterns in logs
  if [ -f "$PROJECT_ROOT/logs/ai-thoughts.md" ]; then
    for pattern in "${ALERT_PATTERNS[@]}"; do
      local count=$(grep -ci "$pattern" "$PROJECT_ROOT/logs/ai-thoughts.md" 2>/dev/null || echo "0")
      if [ "$count" -gt 5 ]; then
        anomalies+=("$(jq -n \
          --arg type "log_pattern" \
          --arg desc "Found $count occurrences of '$pattern' in logs" \
          --arg severity "warning" \
          --arg ts "$timestamp" \
          '{type: $type, description: $desc, severity: $severity, timestamp: $ts}')")
      fi
    done
  fi
  
  # Check for stale processes
  local aha_loop_pids=$(pgrep -f "aha-loop.sh" 2>/dev/null || echo "")
  if [ -n "$aha_loop_pids" ]; then
    for pid in $aha_loop_pids; do
      local elapsed=$(ps -o etimes= -p $pid 2>/dev/null || echo "0")
      if [ "$elapsed" -gt 7200 ]; then
        anomalies+=("$(jq -n \
          --arg type "stale_process" \
          --arg desc "Aha Loop execution process $pid running for ${elapsed}s" \
          --arg severity "warning" \
          --arg ts "$timestamp" \
          --argjson pid "$pid" \
          '{type: $type, description: $desc, severity: $severity, timestamp: $ts, pid: $pid}')")
      fi
    done
  fi
  
  # Check for large log files
  if [ -d "$PROJECT_ROOT/logs" ]; then
    for log_file in "$PROJECT_ROOT/logs"/*.md; do
      if [ -f "$log_file" ]; then
        local size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo "0")
        if [ "$size" -gt 10485760 ]; then  # 10MB
          anomalies+=("$(jq -n \
            --arg type "large_file" \
            --arg desc "Log file $(basename "$log_file") is $(($size / 1048576))MB" \
            --arg severity "info" \
            --arg ts "$timestamp" \
            '{type: $type, description: $desc, severity: $severity, timestamp: $ts}')")
        fi
      fi
    done
  fi
  
  # Check for failed tests
  if [ -f "$PROJECT_ROOT/test-results.json" ]; then
    local failed=$(jq '.failed // 0' "$PROJECT_ROOT/test-results.json" 2>/dev/null || echo "0")
    if [ "$failed" -gt 0 ]; then
      anomalies+=("$(jq -n \
        --arg type "test_failure" \
        --arg desc "$failed tests are failing" \
        --arg severity "error" \
        --arg ts "$timestamp" \
        '{type: $type, description: $desc, severity: $severity, timestamp: $ts}')")
    fi
  fi
  
  # Check for too many worktrees
  if [ -d "$PROJECT_ROOT/.worktrees" ]; then
    local wt_count=$(ls -1 "$PROJECT_ROOT/.worktrees" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$wt_count" -gt 10 ]; then
      anomalies+=("$(jq -n \
        --arg type "resource_usage" \
        --arg desc "Too many active worktrees ($wt_count)" \
        --arg severity "warning" \
        --arg ts "$timestamp" \
        '{type: $type, description: $desc, severity: $severity, timestamp: $ts}')")
    fi
  fi
  
  # Update anomalies file
  local anomaly_count=${#anomalies[@]}
  if [ $anomaly_count -gt 0 ]; then
    local anomaly_array="["
    for i in "${!anomalies[@]}"; do
      anomaly_array+="${anomalies[$i]}"
      if [ $i -lt $((anomaly_count - 1)) ]; then
        anomaly_array+=","
      fi
    done
    anomaly_array+="]"
    
    # Append to existing anomalies
    jq --argjson new "$anomaly_array" \
       '.anomalies = (.anomalies + $new) | .anomalies = .anomalies[-100:]' \
       "$OBS_DIR/anomalies.json" > "$OBS_DIR/anomalies.json.tmp"
    mv "$OBS_DIR/anomalies.json.tmp" "$OBS_DIR/anomalies.json"
    
    echo "Found $anomaly_count anomalies:"
    echo "$anomaly_array" | jq '.'
  else
    echo "No anomalies detected."
  fi
}

#######################################
# TIMELINE
#######################################

# Add event to timeline
add_timeline_event() {
  local event_type="$1"
  local description="$2"
  local data="${3:-null}"
  
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local event_id="evt-$(date +%s)-$RANDOM"
  
  local event=$(jq -n \
    --arg id "$event_id" \
    --arg type "$event_type" \
    --arg desc "$description" \
    --arg ts "$timestamp" \
    --argjson data "$data" \
    '{
      id: $id,
      type: $type,
      description: $desc,
      timestamp: $ts,
      data: $data
    }')
  
  # Keep only last 500 events
  jq --argjson evt "$event" \
     '.events = ([$evt] + .events) | .events = .events[:500]' \
     "$OBS_DIR/timeline.json" > "$OBS_DIR/timeline.json.tmp"
  mv "$OBS_DIR/timeline.json.tmp" "$OBS_DIR/timeline.json"
}

# Show timeline
show_timeline() {
  local count="${1:-20}"
  
  echo "=== Recent Events (last $count) ==="
  echo ""
  
  jq -r ".events[:$count][] | \"\(.timestamp) [\(.type)] \(.description)\"" "$OBS_DIR/timeline.json"
}

#######################################
# CONTINUOUS WATCH
#######################################

# Watch for file changes
watch_files() {
  local interval="${1:-60}"
  
  echo "Starting continuous observation (interval: ${interval}s)"
  echo "Press Ctrl+C to stop"
  echo ""
  
  while true; do
    take_snapshot > /dev/null
    check_anomalies > /dev/null
    
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] Observation cycle complete"
    
    sleep "$interval"
  done
}

#######################################
# REPORTS
#######################################

# Generate observation report
generate_report() {
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local report_file="$OBS_DIR/report-$(date +%Y%m%d%H%M%S).md"
  
  # Take fresh snapshot
  take_snapshot > /dev/null
  
  cat > "$report_file" << EOF
# God Committee Observation Report

**Generated:** $timestamp

---

## Executive Summary

$(jq -r '
  "- **Orchestrator Running:** \(.execution.orchestratorRunning)\n" +
  "- **Current Phase:** \(.execution.currentPhase // "None")\n" +
  "- **Current PRD:** \(.execution.currentPRD // "None")\n" +
  "- **Progress:** \(.progress.completedStories)/\(.progress.totalStories) stories completed"
' "$OBS_DIR/system-state.json")

---

## System Health

$(jq -r '
  "| Metric | Value |\n" +
  "|--------|-------|\n" +
  "| Tests Passing | \(.health.testsPassing // "Unknown") |\n" +
  "| Lint Errors | \(.health.lintErrors // "Unknown") |\n" +
  "| Type Errors | \(.health.typeErrors // "Unknown") |"
' "$OBS_DIR/system-state.json")

---

## Resource Usage

$(jq -r '
  "| Resource | Value |\n" +
  "|----------|-------|\n" +
  "| Active Worktrees | \(.resources.activeWorktrees) |\n" +
  "| Vendor Size | \(.resources.vendorSize // "N/A") |\n" +
  "| Log Size | \(.resources.logSize // "N/A") |"
' "$OBS_DIR/system-state.json")

---

## Recent Anomalies

$(jq -r '
  if .anomalies | length == 0 then
    "No anomalies detected."
  else
    .anomalies[-10:][] | "- **[\(.severity)]** \(.description) (\(.timestamp))"
  end
' "$OBS_DIR/anomalies.json")

---

## Recent Events

$(jq -r '.events[:10][] | "- \(.timestamp): [\(.type)] \(.description)"' "$OBS_DIR/timeline.json")

---

*Report generated by God Committee Observer*
EOF

  echo "Report generated: $report_file"
  cat "$report_file"
}

#######################################
# MAIN
#######################################

case "${1:-snapshot}" in
  snapshot)
    take_snapshot
    ;;
  watch)
    watch_files "${2:-60}"
    ;;
  check|health)
    take_snapshot
    check_anomalies
    ;;
  anomaly|anomalies)
    check_anomalies
    ;;
  timeline)
    show_timeline "${2:-20}"
    ;;
  report)
    generate_report
    ;;
  event)
    add_timeline_event "$2" "$3" "${4:-null}"
    ;;
  *)
    echo "God Committee Observer"
    echo ""
    echo "Usage: $0 {snapshot|watch|check|anomaly|timeline|report|event}"
    echo ""
    echo "Commands:"
    echo "  snapshot          - Take a full system state snapshot"
    echo "  watch [interval]  - Continuous monitoring (default: 60s)"
    echo "  check             - Run health checks"
    echo "  anomaly           - Check for anomalies"
    echo "  timeline [count]  - Show recent events (default: 20)"
    echo "  report            - Generate full observation report"
    echo "  event TYPE DESC   - Add timeline event"
    exit 1
    ;;
esac
