#!/bin/bash
# Test jq query for exploration topics

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json.example"

echo "Testing exploration topics query..."

jq -r --arg id "US-002" \
  '.userStories[] | select(.id == $id) | .explorationTopics[]? | "\(.topic):\((.approaches // []) | join(","))"' "$PRD_FILE"

echo ""
echo "Testing story needs exploration..."
jq -r --arg id "US-002" \
  '.userStories[] | select(.id == $id) | (.explorationTopics | length) > 0' "$PRD_FILE"
