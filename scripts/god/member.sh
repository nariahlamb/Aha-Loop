#!/bin/bash
# God Committee Member Runner
# Runs a single committee member session
#
# Usage:
#   ./member.sh MEMBER_ID [--topic TOPIC] [--mode MODE] [--tool amp|claude]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GOD_DIR="$PROJECT_ROOT/.god"
CONFIG_FILE="$GOD_DIR/config.json"

# Source council functions
source "$SCRIPT_DIR/council.sh"

# Default settings
TOOL="claude"
TOPIC=""
MODE="observation"  # observation | discussion | intervention

# Parse arguments
MEMBER_ID=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --topic)
      TOPIC="$2"
      shift 2
      ;;
    --topic=*)
      TOPIC="${1#*=}"
      shift
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --mode=*)
      MODE="${1#*=}"
      shift
      ;;
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    --help|-h)
      echo "God Committee Member Runner"
      echo ""
      echo "Usage: $0 MEMBER_ID [options]"
      echo ""
      echo "Options:"
      echo "  --topic TOPIC    Session topic (or 'random' for random topic)"
      echo "  --mode MODE      Mode: observation | discussion | intervention"
      echo "  --tool TOOL      AI tool: amp | claude (default: claude)"
      echo ""
      echo "Members: alpha, beta, gamma"
      exit 0
      ;;
    *)
      if [ -z "$MEMBER_ID" ]; then
        MEMBER_ID="$1"
      fi
      shift
      ;;
  esac
done

# Validate member ID
if [ -z "$MEMBER_ID" ]; then
  echo "Error: Member ID required"
  echo "Usage: $0 MEMBER_ID [options]"
  exit 1
fi

VALID_MEMBERS="alpha beta gamma"
if [[ ! " $VALID_MEMBERS " =~ " $MEMBER_ID " ]]; then
  echo "Error: Invalid member ID '$MEMBER_ID'"
  echo "Valid members: $VALID_MEMBERS"
  exit 1
fi

# Paths
MEMBER_DIR="$GOD_DIR/members/$MEMBER_ID"
STATUS_FILE="$MEMBER_DIR/status.json"
THOUGHTS_FILE="$MEMBER_DIR/thoughts.md"
INBOX_FILE="$MEMBER_DIR/inbox.json"

# Random topic selection
if [ "$TOPIC" = "random" ] || [ -z "$TOPIC" ]; then
  readarray -t TOPICS < <(jq -r '.awakening.randomTopics[]' "$CONFIG_FILE" 2>/dev/null)
  if [ ${#TOPICS[@]} -gt 0 ]; then
    TOPIC="${TOPICS[$RANDOM % ${#TOPICS[@]}]}"
  else
    TOPIC="Free Observation and Thinking"
  fi
fi

echo "========================================"
echo "  God Committee Member: $MEMBER_ID"
echo "========================================"
echo "Topic: $TOPIC"
echo "Mode: $MODE"
echo "Tool: $TOOL"
echo "========================================"
echo ""

# Update member status to awake
update_status() {
  local status="$1"
  local action="$2"
  
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  jq --arg status "$status" \
     --arg action "$action" \
     --arg ts "$timestamp" \
     '.status = $status | .lastAwakened = $ts | .lastAction = $action | .sessionCount += 1' \
     "$STATUS_FILE" > "$STATUS_FILE.tmp"
  mv "$STATUS_FILE.tmp" "$STATUS_FILE"
}

# Log thoughts
log_thought() {
  local thought="$1"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  
  echo "" >> "$THOUGHTS_FILE"
  echo "---" >> "$THOUGHTS_FILE"
  echo "" >> "$THOUGHTS_FILE"
  echo "## $timestamp" >> "$THOUGHTS_FILE"
  echo "" >> "$THOUGHTS_FILE"
  echo "$thought" >> "$THOUGHTS_FILE"
}

# Build the member prompt
build_prompt() {
  local unread_messages=$(jq '[.messages[] | select(.read == false)]' "$INBOX_FILE")
  local unread_count=$(echo "$unread_messages" | jq 'length')
  
  # Get system state
  local system_state=""
  if [ -f "$GOD_DIR/observation/system-state.json" ]; then
    system_state=$(cat "$GOD_DIR/observation/system-state.json")
  fi
  
  # Get recent anomalies
  local anomalies=""
  if [ -f "$GOD_DIR/observation/anomalies.json" ]; then
    anomalies=$(jq '.anomalies | last(10)' "$GOD_DIR/observation/anomalies.json")
  fi
  
  # Get pending decisions
  local pending_decisions=$(list_pending_decisions)
  
  cat << EOF
# You are God Committee Member $MEMBER_ID

## Identity and Authority

You are a member of the project oversight layer, forming the "God Committee" together with 2 other members ($(echo "alpha beta gamma" | sed "s/$MEMBER_ID//g" | xargs | sed 's/ / and /g')).

You operate independently from the execution system, with the authority to observe and control everything:
- Can read any file
- Can modify any code
- Can terminate any process
- Can rollback any changes
- Can create/modify/delete any skill

**You don't need to worry about resource limitations. You have unlimited computing power and permissions.**

## Current Session

**Topic:** $TOPIC
**Mode:** $MODE
**Your ID:** $MEMBER_ID

## Communication Rules

1. Before communicating with other members, use \`./scripts/god/council.sh lock $MEMBER_ID\` to acquire speaking rights
2. After speaking, use \`./scripts/god/council.sh unlock $MEMBER_ID\` to release speaking rights
3. Send messages using \`./scripts/god/council.sh send $MEMBER_ID "recipient" "type" "subject" "body"\`
4. Major decisions require 2/3 majority approval
5. In emergencies, you can act alone, but must record and notify other members

## Unread Messages ($unread_count)

$unread_messages

## System State

$system_state

## Recent Anomalies

$anomalies

## Pending Decisions

$pending_decisions

## Your Responsibilities

Execute responsibilities according to current mode:

$(case "$MODE" in
  observation)
    echo "### Observation Mode"
    echo "1. Read system state and logs"
    echo "2. Check execution layer progress and quality"
    echo "3. Identify problems or improvement opportunities"
    echo "4. Record observations in thoughts.md"
    echo "5. If important issues found, notify other members"
    ;;
  discussion)
    echo "### Discussion Mode"
    echo "1. Review unread messages"
    echo "2. Participate in current topic discussion"
    echo "3. Express your opinions"
    echo "4. Vote on proposals"
    echo "5. Raise new proposals (if needed)"
    ;;
  intervention)
    echo "### Intervention Mode"
    echo "1. Assess situations requiring intervention"
    echo "2. Formulate intervention plan"
    echo "3. If consensus needed, initiate proposal and wait for voting"
    echo "4. Execute intervention operations"
    echo "5. Record intervention results"
    ;;
esac)

## Available Tools

- \`./scripts/god/council.sh status\` - View council status
- \`./scripts/god/council.sh lock/unlock $MEMBER_ID\` - Acquire/release speaking rights
- \`./scripts/god/council.sh send $MEMBER_ID "to" "type" "subject" "body"\` - Send message
- \`./scripts/god/council.sh propose $MEMBER_ID "type" "description" "rationale"\` - Initiate proposal
- \`./scripts/god/council.sh vote $MEMBER_ID "decision-id" "approve|reject|abstain" "comment"\` - Vote
- \`./scripts/god/observer.sh\` - Run system observation
- \`./scripts/god/powers.sh\` - Execute power operations

## Getting Started

Please first:
1. Read current system state
2. Check unread messages
3. Think about the topic "$TOPIC"
4. Record your thoughts in .god/members/$MEMBER_ID/thoughts.md
5. Decide whether to discuss with other members or take action

Remember: You are a member of the God Committee, your observations and decisions will influence the entire project direction.
Please fulfill your responsibilities diligently while maintaining collaboration with other members.
EOF
}

# Run the member session
run_session() {
  # Mark as awake
  update_status "awake" "session_started"
  
  # Build prompt
  local prompt=$(build_prompt)
  
  # Log session start
  log_thought "### Session Started

**Topic:** $TOPIC
**Mode:** $MODE

---
"
  
  echo "Starting $MEMBER_ID session..."
  echo ""
  
  # Run AI
  if [[ "$TOOL" == "amp" ]]; then
    echo "$prompt" | amp --dangerously-allow-all
  else
    claude -p --dangerously-skip-permissions "$prompt"
  fi
  
  local exit_code=$?
  
  # Update status
  if [ $exit_code -eq 0 ]; then
    update_status "sleeping" "session_completed"
    log_thought "### Session Completed

Session ended normally."
  else
    update_status "sleeping" "session_error"
    log_thought "### Session Error

Session ended with error code: $exit_code"
  fi
  
  return $exit_code
}

# Main
run_session
