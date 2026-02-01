#!/bin/bash
# God Committee Council - Communication and Consensus Management
# Handles file locking, message queuing, and decision-making
#
# Usage:
#   source scripts/god/council.sh
#   acquire_lock "alpha"
#   send_message "alpha" "beta,gamma" "proposal" "Let's discuss X"
#   release_lock "alpha"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GOD_DIR="$PROJECT_ROOT/.god"
COUNCIL_DIR="$GOD_DIR/council"
CONFIG_FILE="$GOD_DIR/config.json"

# Load configuration
load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    LOCK_TIMEOUT=$(jq -r '.communication.lockTimeoutSeconds // 60' "$CONFIG_FILE")
    QUORUM=$(jq -r '.council.quorum // 2' "$CONFIG_FILE")
    EMERGENCY_QUORUM=$(jq -r '.council.emergencyQuorum // 1' "$CONFIG_FILE")
  else
    LOCK_TIMEOUT=60
    QUORUM=2
    EMERGENCY_QUORUM=1
  fi
}

load_config

#######################################
# FILE LOCKING MECHANISM
#######################################

# Lock file path
CHAMBER_LOCK="$COUNCIL_DIR/chamber.lock"
LOCK_FD=200

# Acquire the chamber lock (speaking rights)
# Usage: acquire_lock MEMBER_ID [timeout_seconds]
acquire_lock() {
  local member="$1"
  local timeout="${2:-$LOCK_TIMEOUT}"
  local start_time=$(date +%s)
  
  # Create lock file if not exists
  touch "$CHAMBER_LOCK"
  
  # Try to acquire lock with timeout
  while true; do
    # Check timeout
    local elapsed=$(( $(date +%s) - start_time ))
    if [ $elapsed -ge $timeout ]; then
      echo "ERROR: Failed to acquire lock within ${timeout}s"
      return 1
    fi
    
    # Try to acquire lock
    if ( set -o noclobber; echo "$member $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$CHAMBER_LOCK.tmp" ) 2>/dev/null; then
      mv "$CHAMBER_LOCK.tmp" "$CHAMBER_LOCK"
      echo "Lock acquired by $member"
      return 0
    fi
    
    # Check if current lock is stale
    if [ -f "$CHAMBER_LOCK" ]; then
      local lock_holder=$(cut -d' ' -f1 "$CHAMBER_LOCK" 2>/dev/null)
      local lock_time=$(cut -d' ' -f2 "$CHAMBER_LOCK" 2>/dev/null)
      
      if [ -n "$lock_time" ]; then
        local lock_epoch=$(date -d "$lock_time" +%s 2>/dev/null || echo "0")
        local now_epoch=$(date +%s)
        local lock_age=$(( now_epoch - lock_epoch ))
        
        if [ $lock_age -gt $LOCK_TIMEOUT ]; then
          echo "Stale lock detected (held by $lock_holder for ${lock_age}s), forcibly acquiring"
          rm -f "$CHAMBER_LOCK"
          continue
        fi
      fi
    fi
    
    # Wait and retry
    sleep 1
  done
}

# Release the chamber lock
# Usage: release_lock MEMBER_ID
release_lock() {
  local member="$1"
  
  if [ -f "$CHAMBER_LOCK" ]; then
    local lock_holder=$(cut -d' ' -f1 "$CHAMBER_LOCK" 2>/dev/null)
    
    if [ "$lock_holder" = "$member" ]; then
      rm -f "$CHAMBER_LOCK"
      echo "Lock released by $member"
      return 0
    else
      echo "WARNING: $member tried to release lock held by $lock_holder"
      return 1
    fi
  fi
  
  return 0
}

# Check who holds the lock
# Usage: check_lock
check_lock() {
  if [ -f "$CHAMBER_LOCK" ] && [ -s "$CHAMBER_LOCK" ]; then
    cat "$CHAMBER_LOCK"
    return 0
  else
    echo "No lock held"
    return 1
  fi
}

# Force release lock (emergency)
# Usage: force_release_lock
force_release_lock() {
  rm -f "$CHAMBER_LOCK" "$CHAMBER_LOCK.tmp"
  echo "Lock forcibly released"
}

#######################################
# MESSAGE QUEUE
#######################################

# Generate unique message ID
generate_msg_id() {
  echo "msg-$(date +%s)-$RANDOM"
}

# Send message to other members
# Usage: send_message FROM TO_LIST TYPE SUBJECT [BODY]
send_message() {
  local from="$1"
  local to_list="$2"
  local msg_type="$3"
  local subject="$4"
  local body="${5:-}"
  local priority="${6:-normal}"
  local requires_response="${7:-false}"
  
  local msg_id=$(generate_msg_id)
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  # Create message JSON
  local message=$(jq -n \
    --arg id "$msg_id" \
    --arg from "$from" \
    --arg type "$msg_type" \
    --arg priority "$priority" \
    --arg timestamp "$timestamp" \
    --arg subject "$subject" \
    --arg body "$body" \
    --argjson requires "$requires_response" \
    '{
      id: $id,
      from: $from,
      type: $type,
      priority: $priority,
      timestamp: $timestamp,
      content: {
        subject: $subject,
        body: $body
      },
      requiresResponse: $requires,
      read: false
    }')
  
  # Deliver to each recipient's inbox
  local old_ifs="$IFS"
  IFS=',' read -ra recipients <<< "$to_list"
  IFS="$old_ifs"
  for recipient in "${recipients[@]}"; do
    recipient=$(echo "$recipient" | xargs)  # Trim whitespace
    local inbox="$GOD_DIR/members/$recipient/inbox.json"
    
    if [ -f "$inbox" ]; then
      # Add message to inbox
      jq --argjson msg "$message" '.messages += [$msg]' "$inbox" > "$inbox.tmp"
      mv "$inbox.tmp" "$inbox"
      echo "Message $msg_id delivered to $recipient"
    fi
  done
  
  # Also add to sender's outbox
  local outbox="$GOD_DIR/members/$from/outbox.json"
  if [ -f "$outbox" ]; then
    local outbound=$(echo "$message" | jq --arg to "$to_list" '. + {to: ($to | split(","))}')
    jq --argjson msg "$outbound" '.messages += [$msg]' "$outbox" > "$outbox.tmp"
    mv "$outbox.tmp" "$outbox"
  fi
  
  echo "$msg_id"
}

# Read messages from inbox
# Usage: read_messages MEMBER_ID [unread_only]
read_messages() {
  local member="$1"
  local unread_only="${2:-false}"
  
  local inbox="$GOD_DIR/members/$member/inbox.json"
  
  if [ -f "$inbox" ]; then
    if [ "$unread_only" = "true" ]; then
      jq '.messages | map(select(.read == false))' "$inbox"
    else
      jq '.messages' "$inbox"
    fi
  else
    echo "[]"
  fi
}

# Mark message as read
# Usage: mark_read MEMBER_ID MESSAGE_ID
mark_read() {
  local member="$1"
  local msg_id="$2"
  
  local inbox="$GOD_DIR/members/$member/inbox.json"
  
  if [ -f "$inbox" ]; then
    jq --arg id "$msg_id" '
      .messages |= map(if .id == $id then .read = true else . end)
    ' "$inbox" > "$inbox.tmp"
    mv "$inbox.tmp" "$inbox"
  fi
}

# Clear old messages
# Usage: clear_old_messages MEMBER_ID [days]
clear_old_messages() {
  local member="$1"
  local days="${2:-7}"
  
  local inbox="$GOD_DIR/members/$member/inbox.json"
  local cutoff=$(date -u -d "$days days ago" +%Y-%m-%dT%H:%M:%SZ)
  
  if [ -f "$inbox" ]; then
    jq --arg cutoff "$cutoff" '
      .messages |= map(select(.timestamp > $cutoff))
    ' "$inbox" > "$inbox.tmp"
    mv "$inbox.tmp" "$inbox"
  fi
}

#######################################
# CONSENSUS MECHANISM
#######################################

# Start a new proposal
# Usage: create_proposal AUTHOR TYPE DESCRIPTION RATIONALE
create_proposal() {
  local author="$1"
  local type="$2"
  local description="$3"
  local rationale="$4"
  
  local decision_id="decision-$(date +%Y%m%d%H%M%S)"
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  local proposal=$(jq -n \
    --arg id "$decision_id" \
    --arg type "$type" \
    --arg author "$author" \
    --arg desc "$description" \
    --arg rationale "$rationale" \
    --arg timestamp "$timestamp" \
    '{
      decisionId: $id,
      type: $type,
      status: "voting",
      createdAt: $timestamp,
      proposal: {
        author: $author,
        description: $desc,
        rationale: $rationale
      },
      votes: {},
      quorum: 2,
      result: null,
      executedAt: null
    }')
  
  # Save proposal
  echo "$proposal" > "$COUNCIL_DIR/decisions/$decision_id.json"
  
  # Update agenda
  jq --arg id "$decision_id" '.pendingTopics += [$id]' "$COUNCIL_DIR/agenda.json" > "$COUNCIL_DIR/agenda.json.tmp"
  mv "$COUNCIL_DIR/agenda.json.tmp" "$COUNCIL_DIR/agenda.json"
  
  # Notify all members
  local members=$(jq -r '.council.members[]' "$CONFIG_FILE" | tr '\n' ',')
  members=${members%,}  # Remove trailing comma
  
  send_message "$author" "$members" "proposal" "New proposal: $description" "$rationale" "urgent" "true"
  
  echo "$decision_id"
}

# Cast a vote
# Usage: cast_vote MEMBER_ID DECISION_ID VOTE [COMMENT]
cast_vote() {
  local member="$1"
  local decision_id="$2"
  local vote="$3"  # approve | reject | abstain
  local comment="${4:-}"
  
  local decision_file="$COUNCIL_DIR/decisions/$decision_id.json"
  
  if [ ! -f "$decision_file" ]; then
    echo "ERROR: Decision $decision_id not found"
    return 1
  fi
  
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  # Add vote
  jq --arg member "$member" \
     --arg vote "$vote" \
     --arg comment "$comment" \
     --arg ts "$timestamp" \
     '.votes[$member] = {vote: $vote, comment: $comment, timestamp: $ts}' \
     "$decision_file" > "$decision_file.tmp"
  mv "$decision_file.tmp" "$decision_file"
  
  # Check if quorum reached
  check_consensus "$decision_id"
}

# Check if consensus is reached
# Usage: check_consensus DECISION_ID
check_consensus() {
  local decision_id="$1"
  local decision_file="$COUNCIL_DIR/decisions/$decision_id.json"
  
  if [ ! -f "$decision_file" ]; then
    return 1
  fi
  
  local status=$(jq -r '.status' "$decision_file")
  if [ "$status" != "voting" ]; then
    return 0
  fi
  
  local approve_count=$(jq '[.votes[] | select(.vote == "approve")] | length' "$decision_file")
  local reject_count=$(jq '[.votes[] | select(.vote == "reject")] | length' "$decision_file")
  local total_votes=$(jq '.votes | length' "$decision_file")
  local quorum=$(jq -r '.quorum' "$decision_file")
  
  local result=""
  
  if [ $approve_count -ge $quorum ]; then
    result="approved"
  elif [ $reject_count -ge $quorum ]; then
    result="rejected"
  elif [ $total_votes -ge 3 ]; then
    # All members voted, determine by majority
    if [ $approve_count -gt $reject_count ]; then
      result="approved"
    else
      result="rejected"
    fi
  fi
  
  if [ -n "$result" ]; then
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg result "$result" --arg ts "$timestamp" \
       '.status = "decided" | .result = $result | .decidedAt = $ts' \
       "$decision_file" > "$decision_file.tmp"
    mv "$decision_file.tmp" "$decision_file"
    
    # Remove from pending
    jq --arg id "$decision_id" '.pendingTopics -= [$id]' "$COUNCIL_DIR/agenda.json" > "$COUNCIL_DIR/agenda.json.tmp"
    mv "$COUNCIL_DIR/agenda.json.tmp" "$COUNCIL_DIR/agenda.json"
    
    echo "Decision $decision_id: $result"
    return 0
  fi
  
  echo "Decision $decision_id: still voting ($approve_count approve, $reject_count reject)"
  return 1
}

# Get decision status
# Usage: get_decision DECISION_ID
get_decision() {
  local decision_id="$1"
  local decision_file="$COUNCIL_DIR/decisions/$decision_id.json"
  
  if [ -f "$decision_file" ]; then
    cat "$decision_file"
  else
    echo "null"
  fi
}

# List pending decisions
# Usage: list_pending_decisions
list_pending_decisions() {
  jq -r '.pendingTopics[]' "$COUNCIL_DIR/agenda.json" 2>/dev/null || echo ""
}

#######################################
# SESSION MANAGEMENT
#######################################

# Start a council session
# Usage: start_session TOPIC [MODE]
start_session() {
  local topic="$1"
  local mode="${2:-discussion}"
  
  local session_id="session-$(date +%Y%m%d%H%M%S)"
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  # Update agenda with current session
  jq --arg id "$session_id" \
     --arg topic "$topic" \
     --arg mode "$mode" \
     --arg ts "$timestamp" \
     '.currentSession = {id: $id, topic: $topic, mode: $mode, startedAt: $ts, participants: []}' \
     "$COUNCIL_DIR/agenda.json" > "$COUNCIL_DIR/agenda.json.tmp"
  mv "$COUNCIL_DIR/agenda.json.tmp" "$COUNCIL_DIR/agenda.json"
  
  # Create session minutes file
  mkdir -p "$COUNCIL_DIR/minutes"
  cat > "$COUNCIL_DIR/minutes/$session_id.md" << EOF
# Council Session: $session_id

**Topic:** $topic
**Mode:** $mode
**Started:** $timestamp

---

## Participants

## Discussion

## Decisions Made

## Action Items

---

*Session in progress...*
EOF

  echo "$session_id"
}

# Join a session
# Usage: join_session MEMBER_ID
join_session() {
  local member="$1"
  
  jq --arg member "$member" \
     '.currentSession.participants += [$member] | .currentSession.participants |= unique' \
     "$COUNCIL_DIR/agenda.json" > "$COUNCIL_DIR/agenda.json.tmp"
  mv "$COUNCIL_DIR/agenda.json.tmp" "$COUNCIL_DIR/agenda.json"
}

# End current session
# Usage: end_session [SUMMARY]
end_session() {
  local summary="${1:-Session ended without summary}"
  
  local session=$(jq -r '.currentSession' "$COUNCIL_DIR/agenda.json")
  
  if [ "$session" = "null" ]; then
    echo "No active session"
    return 1
  fi
  
  local session_id=$(echo "$session" | jq -r '.id')
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  # Update minutes
  echo "" >> "$COUNCIL_DIR/minutes/$session_id.md"
  echo "---" >> "$COUNCIL_DIR/minutes/$session_id.md"
  echo "" >> "$COUNCIL_DIR/minutes/$session_id.md"
  echo "**Ended:** $timestamp" >> "$COUNCIL_DIR/minutes/$session_id.md"
  echo "" >> "$COUNCIL_DIR/minutes/$session_id.md"
  echo "## Summary" >> "$COUNCIL_DIR/minutes/$session_id.md"
  echo "" >> "$COUNCIL_DIR/minutes/$session_id.md"
  echo "$summary" >> "$COUNCIL_DIR/minutes/$session_id.md"
  
  # Archive session
  jq --argjson session "$session" \
     --arg ts "$timestamp" \
     '.recentSessions = [($session + {endedAt: $ts})] + .recentSessions[:9] | .currentSession = null' \
     "$COUNCIL_DIR/agenda.json" > "$COUNCIL_DIR/agenda.json.tmp"
  mv "$COUNCIL_DIR/agenda.json.tmp" "$COUNCIL_DIR/agenda.json"
  
  echo "Session $session_id ended"
}

#######################################
# DIRECTIVES SYSTEM
#######################################

DIRECTIVES_FILE="$GOD_DIR/directives.json"

# Initialize directives file if needed
init_directives() {
  if [ ! -f "$DIRECTIVES_FILE" ]; then
    cat > "$DIRECTIVES_FILE" << 'EOF'
{
  "directives": [],
  "guidance": [],
  "summaries": [],
  "stats": {
    "totalDirectives": 0,
    "completedDirectives": 0,
    "totalGuidance": 0,
    "totalSummaries": 0
  }
}
EOF
  fi
}

# Publish a directive, guidance, or summary
# Usage: publish_directive AUTHOR TYPE PRIORITY CONTENT [TARGET_PRD]
# TYPE: directive | guidance | summary
# PRIORITY: critical | high | normal | low
publish_directive() {
  local author="$1"
  local type="$2"
  local priority="$3"
  local content="$4"
  local target_prd="${5:-}"
  
  init_directives
  
  local item_id="${type:0:3}-$(date +%Y%m%d%H%M%S)-$RANDOM"
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  case "$type" in
    directive)
      local item=$(jq -n \
        --arg id "$item_id" \
        --arg author "$author" \
        --arg priority "$priority" \
        --arg content "$content" \
        --arg target "$target_prd" \
        --arg ts "$timestamp" \
        '{
          id: $id,
          author: $author,
          priority: $priority,
          content: $content,
          targetPrd: (if $target == "" then null else $target end),
          status: "active",
          createdAt: $ts,
          completedAt: null
        }')
      
      jq --argjson item "$item" '
        .directives += [$item] |
        .stats.totalDirectives += 1
      ' "$DIRECTIVES_FILE" > "$DIRECTIVES_FILE.tmp"
      mv "$DIRECTIVES_FILE.tmp" "$DIRECTIVES_FILE"
      ;;
      
    guidance)
      local item=$(jq -n \
        --arg id "$item_id" \
        --arg author "$author" \
        --arg priority "$priority" \
        --arg content "$content" \
        --arg target "$target_prd" \
        --arg ts "$timestamp" \
        '{
          id: $id,
          author: $author,
          priority: $priority,
          content: $content,
          targetPrd: (if $target == "" then null else $target end),
          createdAt: $ts,
          expiresAt: null
        }')
      
      jq --argjson item "$item" '
        .guidance += [$item] |
        .stats.totalGuidance += 1
      ' "$DIRECTIVES_FILE" > "$DIRECTIVES_FILE.tmp"
      mv "$DIRECTIVES_FILE.tmp" "$DIRECTIVES_FILE"
      ;;
      
    summary)
      local item=$(jq -n \
        --arg id "$item_id" \
        --arg author "$author" \
        --arg content "$content" \
        --arg ts "$timestamp" \
        '{
          id: $id,
          author: $author,
          content: $content,
          createdAt: $ts
        }')
      
      jq --argjson item "$item" '
        .summaries += [$item] |
        .stats.totalSummaries += 1
      ' "$DIRECTIVES_FILE" > "$DIRECTIVES_FILE.tmp"
      mv "$DIRECTIVES_FILE.tmp" "$DIRECTIVES_FILE"
      ;;
      
    *)
      echo "ERROR: Unknown type '$type'. Use: directive, guidance, summary"
      return 1
      ;;
  esac
  
  echo "Published $type: $item_id"
  
  # Send notification to execution layer
  local log_file="$PROJECT_ROOT/logs/ai-thoughts.md"
  if [ -f "$log_file" ] || [ -d "$(dirname "$log_file")" ]; then
    mkdir -p "$(dirname "$log_file")"
    echo "" >> "$log_file"
    echo "## $timestamp | God Committee | $type" >> "$log_file"
    echo "" >> "$log_file"
    echo "**Author:** $author" >> "$log_file"
    echo "**Priority:** $priority" >> "$log_file"
    echo "" >> "$log_file"
    echo "$content" >> "$log_file"
    echo "" >> "$log_file"
    echo "---" >> "$log_file"
  fi
  
  echo "$item_id"
}

# Mark directive as complete
# Usage: complete_directive DIRECTIVE_ID
complete_directive() {
  local directive_id="$1"
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  init_directives
  
  local exists=$(jq --arg id "$directive_id" '.directives[] | select(.id == $id) | .id' "$DIRECTIVES_FILE")
  
  if [ -z "$exists" ]; then
    echo "ERROR: Directive $directive_id not found"
    return 1
  fi
  
  jq --arg id "$directive_id" --arg ts "$timestamp" '
    (.directives[] | select(.id == $id)) |= . + {status: "completed", completedAt: $ts} |
    .stats.completedDirectives += 1
  ' "$DIRECTIVES_FILE" > "$DIRECTIVES_FILE.tmp"
  mv "$DIRECTIVES_FILE.tmp" "$DIRECTIVES_FILE"
  
  echo "Directive $directive_id marked as completed"
}

# Cancel a directive
# Usage: cancel_directive DIRECTIVE_ID [REASON]
cancel_directive() {
  local directive_id="$1"
  local reason="${2:-No reason provided}"
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  init_directives
  
  local exists=$(jq --arg id "$directive_id" '.directives[] | select(.id == $id) | .id' "$DIRECTIVES_FILE")
  
  if [ -z "$exists" ]; then
    echo "ERROR: Directive $directive_id not found"
    return 1
  fi
  
  jq --arg id "$directive_id" --arg reason "$reason" --arg ts "$timestamp" '
    (.directives[] | select(.id == $id)) |= . + {status: "cancelled", cancelReason: $reason, cancelledAt: $ts}
  ' "$DIRECTIVES_FILE" > "$DIRECTIVES_FILE.tmp"
  mv "$DIRECTIVES_FILE.tmp" "$DIRECTIVES_FILE"
  
  echo "Directive $directive_id cancelled: $reason"
}

# List active directives
# Usage: list_directives [TYPE] [STATUS]
list_directives() {
  local type="${1:-all}"
  local status="${2:-active}"
  
  init_directives
  
  echo "=== God Committee Directives ==="
  echo ""
  
  if [ "$type" = "all" ] || [ "$type" = "directive" ]; then
    echo "Directives ($status):"
    if [ "$status" = "all" ]; then
      jq -r '.directives[] | "  [\(.priority)] \(.id): \(.content | .[0:60])... (\(.status))"' "$DIRECTIVES_FILE"
    else
      jq -r --arg status "$status" '.directives[] | select(.status == $status) | "  [\(.priority)] \(.id): \(.content | .[0:60])..."' "$DIRECTIVES_FILE"
    fi
    echo ""
  fi
  
  if [ "$type" = "all" ] || [ "$type" = "guidance" ]; then
    echo "Guidance:"
    jq -r '.guidance[] | "  [\(.priority)] \(.id): \(.content | .[0:60])..."' "$DIRECTIVES_FILE"
    echo ""
  fi
  
  if [ "$type" = "all" ] || [ "$type" = "summary" ]; then
    echo "Discussion Summaries (recent 5):"
    jq -r '.summaries[-5:][] | "  \(.id): \(.content | .[0:80])..."' "$DIRECTIVES_FILE"
    echo ""
  fi
  
  echo "Stats:"
  jq -r '.stats | "  Total directives: \(.totalDirectives), Completed: \(.completedDirectives)"' "$DIRECTIVES_FILE"
  jq -r '.stats | "  Total guidance: \(.totalGuidance), Total summaries: \(.totalSummaries)"' "$DIRECTIVES_FILE"
}

# Get directives for execution layer (JSON output)
# Usage: get_active_directives [TARGET_PRD]
get_active_directives() {
  local target_prd="${1:-}"
  
  init_directives
  
  if [ -n "$target_prd" ]; then
    jq --arg prd "$target_prd" '{
      directives: [.directives[] | select(.status == "active" and (.targetPrd == null or .targetPrd == $prd))],
      guidance: [.guidance[] | select(.targetPrd == null or .targetPrd == $prd)],
      summaries: .summaries[-5:]
    }' "$DIRECTIVES_FILE"
  else
    jq '{
      directives: [.directives[] | select(.status == "active")],
      guidance: .guidance,
      summaries: .summaries[-5:]
    }' "$DIRECTIVES_FILE"
  fi
}

# Check if there are critical directives
# Usage: has_critical_directives
has_critical_directives() {
  init_directives
  
  local count=$(jq '[.directives[] | select(.status == "active" and .priority == "critical")] | length' "$DIRECTIVES_FILE")
  
  if [ "$count" -gt 0 ]; then
    echo "true"
    return 0
  else
    echo "false"
    return 1
  fi
}

# Clean up old guidance and summaries
# Usage: cleanup_directives [DAYS]
cleanup_directives() {
  local days="${1:-30}"
  local cutoff=$(date -u -d "$days days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-${days}d +%Y-%m-%dT%H:%M:%SZ)
  
  init_directives
  
  jq --arg cutoff "$cutoff" '
    .directives |= [.[] | select(.status == "active" or .createdAt > $cutoff)] |
    .guidance |= [.[] | select(.createdAt > $cutoff)] |
    .summaries |= [.[] | select(.createdAt > $cutoff)]
  ' "$DIRECTIVES_FILE" > "$DIRECTIVES_FILE.tmp"
  mv "$DIRECTIVES_FILE.tmp" "$DIRECTIVES_FILE"
  
  echo "Cleaned up directives older than $days days"
}

#######################################
# UTILITY FUNCTIONS
#######################################

# Get current council status
council_status() {
  echo "=== God Committee Council Status ==="
  echo ""
  
  echo "Lock Status:"
  check_lock || echo "  (no lock held)"
  echo ""
  
  echo "Current Session:"
  local session=$(jq -r '.currentSession' "$COUNCIL_DIR/agenda.json")
  if [ "$session" = "null" ]; then
    echo "  No active session"
  else
    echo "$session" | jq '.'
  fi
  echo ""
  
  echo "Pending Decisions:"
  local pending=$(list_pending_decisions)
  if [ -z "$pending" ]; then
    echo "  None"
  else
    echo "$pending" | while read -r id; do
      echo "  - $id"
    done
  fi
  echo ""
  
  echo "Member Status:"
  local members
  readarray -t members < <(jq -r '.council.members[]' "$CONFIG_FILE" 2>/dev/null)
  [ ${#members[@]} -eq 0 ] && members=("alpha" "beta" "gamma")
  for member in "${members[@]}"; do
    local status=$(jq -r '.status' "$GOD_DIR/members/$member/status.json" 2>/dev/null || echo "unknown")
    local unread=$(jq '[.messages[] | select(.read == false)] | length' "$GOD_DIR/members/$member/inbox.json" 2>/dev/null || echo "0")
    echo "  $member: $status (unread: $unread)"
  done
}

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-status}" in
    status)
      council_status
      ;;
    lock)
      acquire_lock "${2:-test}"
      ;;
    unlock)
      release_lock "${2:-test}"
      ;;
    force-unlock)
      force_release_lock
      ;;
    send)
      send_message "$2" "$3" "$4" "$5" "$6"
      ;;
    read)
      read_messages "$2" "${3:-false}"
      ;;
    propose)
      create_proposal "$2" "$3" "$4" "$5"
      ;;
    vote)
      cast_vote "$2" "$3" "$4" "$5"
      ;;
    session-start)
      start_session "$2" "$3"
      ;;
    session-end)
      end_session "$2"
      ;;
    publish)
      # publish AUTHOR TYPE PRIORITY CONTENT [TARGET_PRD]
      publish_directive "$2" "$3" "$4" "$5" "$6"
      ;;
    complete)
      complete_directive "$2"
      ;;
    cancel)
      cancel_directive "$2" "$3"
      ;;
    directives)
      list_directives "$2" "$3"
      ;;
    get-directives)
      get_active_directives "$2"
      ;;
    has-critical)
      has_critical_directives
      ;;
    cleanup-directives)
      cleanup_directives "$2"
      ;;
    *)
      echo "Usage: $0 COMMAND [args...]"
      echo ""
      echo "Communication:"
      echo "  status                           Show council status"
      echo "  lock MEMBER                      Acquire speaking rights"
      echo "  unlock MEMBER                    Release speaking rights"
      echo "  force-unlock                     Force release lock"
      echo "  send FROM TO TYPE SUBJECT BODY   Send message"
      echo "  read MEMBER [unread_only]        Read messages"
      echo ""
      echo "Consensus:"
      echo "  propose AUTHOR TYPE DESC REASON  Create proposal"
      echo "  vote MEMBER ID VOTE [COMMENT]    Cast vote"
      echo ""
      echo "Sessions:"
      echo "  session-start TOPIC [MODE]       Start council session"
      echo "  session-end [SUMMARY]            End current session"
      echo ""
      echo "Directives:"
      echo "  publish AUTHOR TYPE PRIORITY CONTENT [PRD]  Publish directive/guidance/summary"
      echo "  complete ID                      Mark directive complete"
      echo "  cancel ID [REASON]               Cancel directive"
      echo "  directives [TYPE] [STATUS]       List directives"
      echo "  get-directives [PRD]             Get active directives (JSON)"
      echo "  has-critical                     Check for critical directives"
      echo "  cleanup-directives [DAYS]        Clean old directives"
      exit 1
      ;;
  esac
fi
