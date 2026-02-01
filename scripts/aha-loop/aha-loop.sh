#!/bin/bash
# Aha Loop Executor - Autonomous AI agent loop with Research, Exploration & Plan Review
# Usage: ./aha-loop.sh [--tool amp|claude] [--phase research|explore|plan-review|implement|all] [--max-iterations N] [max_iterations]

set -e

# Parse arguments
TOOL="amp"
PHASE="all"
MAX_ITERATIONS=10

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    --phase)
      PHASE="$2"
      shift 2
      ;;
    --phase=*)
      PHASE="${1#*=}"
      shift
      ;;
    --max-iterations)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --max-iterations=*)
      MAX_ITERATIONS="${1#*=}"
      shift
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

# Validate arguments
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp' or 'claude'."
  exit 1
fi

if [[ "$PHASE" != "all" && "$PHASE" != "research" && "$PHASE" != "explore" && "$PHASE" != "plan-review" && "$PHASE" != "implement" ]]; then
  echo "Error: Invalid phase '$PHASE'. Must be 'all', 'research', 'explore', 'plan-review', or 'implement'."
  exit 1
fi

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
CONFIG_FILE="$SCRIPT_DIR/config.json"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
RESEARCH_DIR="$SCRIPT_DIR/research"
EXPLORATION_DIR="$SCRIPT_DIR/exploration"
GOD_DIR="$PROJECT_ROOT/.god"
DIRECTIVES_FILE="$GOD_DIR/directives.json"

# Load config
RESEARCH_ENABLED=true
PLAN_REVIEW_ENABLED=true
QUALITY_REVIEW_ENABLED=true
EXPLORATION_ENABLED=true
FETCH_SOURCE_CODE=true
CONFIG_MAX_ITERATIONS=10

if [ -f "$CONFIG_FILE" ]; then
  RESEARCH_ENABLED=$(jq -r '.phases.research.enabled // true' "$CONFIG_FILE")
  PLAN_REVIEW_ENABLED=$(jq -r '.phases.planReview.enabled // true' "$CONFIG_FILE")
  QUALITY_REVIEW_ENABLED=$(jq -r '.phases.qualityReview.enabled // true' "$CONFIG_FILE")
  EXPLORATION_ENABLED=$(jq -r '.phases.exploration.enabled // true' "$CONFIG_FILE")
  FETCH_SOURCE_CODE=$(jq -r '.phases.research.fetchSourceCode // true' "$CONFIG_FILE")
  CONFIG_MAX_ITERATIONS=$(jq -r '.safeguards.maxIterationsPerStory // 10' "$CONFIG_FILE")
fi

# Apply config value for MAX_ITERATIONS only if not overridden by command line (still at default)
if [ "$MAX_ITERATIONS" -eq 10 ] && [ "$CONFIG_MAX_ITERATIONS" != "10" ]; then
  MAX_ITERATIONS="$CONFIG_MAX_ITERATIONS"
fi

# Ensure directories exist
mkdir -p "$RESEARCH_DIR"
mkdir -p "$ARCHIVE_DIR"
mkdir -p "$EXPLORATION_DIR"

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  
  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    DATE=$(date +%Y-%m-%d)
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^aha-loop/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    [ -d "$RESEARCH_DIR" ] && cp -r "$RESEARCH_DIR" "$ARCHIVE_FOLDER/" 2>/dev/null || true
    echo "  Archived to: $ARCHIVE_FOLDER"
    
    # Reset progress file
    echo "# Aha Loop Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
    
    # Clear research reports
    rm -f "$RESEARCH_DIR"/*.md 2>/dev/null || true
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if needed
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Aha Loop Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Helper: Get next story that needs work
get_next_story() {
  if [ ! -f "$PRD_FILE" ]; then
    echo ""
    return
  fi
  
  # Find first story where passes=false
  jq -r '.userStories[] | select(.passes == false) | .id' "$PRD_FILE" | head -1
}

# Helper: Check if story needs research
story_needs_research() {
  local story_id="$1"
  if [ ! -f "$PRD_FILE" ]; then
    echo "false"
    return
  fi
  
  local research_completed=$(jq -r --arg id "$story_id" \
    '.userStories[] | select(.id == $id) | .researchCompleted // false' "$PRD_FILE")
  local has_topics=$(jq -r --arg id "$story_id" \
    '.userStories[] | select(.id == $id) | (.researchTopics | length) > 0' "$PRD_FILE")
  
  if [ "$research_completed" = "false" ] && [ "$has_topics" = "true" ]; then
    echo "true"
  else
    echo "false"
  fi
}

# Helper: Check if story needs parallel exploration
story_needs_exploration() {
  local story_id="$1"
  if [ ! -f "$PRD_FILE" ]; then
    echo "false"
    return
  fi
  
  local exploration_completed=$(jq -r --arg id "$story_id" \
    '.userStories[] | select(.id == $id) | .explorationCompleted // false' "$PRD_FILE")
  local has_topics=$(jq -r --arg id "$story_id" \
    '.userStories[] | select(.id == $id) | (.explorationTopics | length) > 0' "$PRD_FILE")
  
  if [ "$exploration_completed" = "false" ] && [ "$has_topics" = "true" ]; then
    echo "true"
  else
    echo "false"
  fi
}

# Helper: Get exploration topics for a story
get_exploration_topics() {
  local story_id="$1"
  if [ ! -f "$PRD_FILE" ]; then
    echo ""
    return
  fi
  
  jq -r --arg id "$story_id" \
    '.userStories[] | select(.id == $id) | .explorationTopics[]? | "\(.topic):\((.approaches // []) | join(","))"' "$PRD_FILE"
}

# Helper: Run parallel exploration for a topic
run_exploration() {
  local story_id="$1"
  local topic="$2"
  local approaches="$3"
  
  echo "Starting parallel exploration for: $topic"
  
  local explore_args="explore \"$topic\""
  if [ -n "$approaches" ]; then
    explore_args="$explore_args --approaches \"$approaches\""
  fi
  explore_args="$explore_args --tool $TOOL"
  
  # Run parallel explorer
  eval "$SCRIPT_DIR/parallel-explorer.sh $explore_args"
  local task_id=$(ls -t "$PROJECT_ROOT/.worktrees/" 2>/dev/null | grep "^explore-" | head -1)
  
  if [ -n "$task_id" ]; then
    echo "Exploration started: $task_id"
    echo "Waiting for explorations to complete..."
    
    # Wait for all explorations to complete (check every 30 seconds)
    local max_wait=3600  # 1 hour max
    local waited=0
    while [ $waited -lt $max_wait ]; do
      local all_done=true
      for status_file in "$PROJECT_ROOT/.worktrees/$task_id"/*/exploration.status; do
        if [ -f "$status_file" ]; then
          local status=$(cat "$status_file")
          if [ "$status" = "running" ]; then
            all_done=false
            break
          fi
        fi
      done
      
      if [ "$all_done" = true ]; then
        break
      fi
      
      echo "  Still exploring... (${waited}s elapsed)"
      sleep 30
      waited=$((waited + 30))
    done
    
    # Evaluate results
    echo "Evaluating exploration results..."
    "$SCRIPT_DIR/parallel-explorer.sh" evaluate "$task_id"
    
    # Save exploration result
    local result_file="$EXPLORATION_DIR/${story_id}-${topic//[^a-zA-Z0-9]/-}.md"
    if [ -f "$PROJECT_ROOT/.worktrees/$task_id/evaluation/FINAL_RECOMMENDATION.md" ]; then
      cp "$PROJECT_ROOT/.worktrees/$task_id/evaluation/FINAL_RECOMMENDATION.md" "$result_file"
      echo "Exploration result saved: $result_file"
    fi
    
    return 0
  else
    echo "Warning: Exploration did not start properly"
    return 1
  fi
}

# Helper: Mark exploration as complete for a story
mark_exploration_complete() {
  local story_id="$1"
  local result="$2"
  
  # Update prd.json
  local tmp_file=$(mktemp)
  jq --arg id "$story_id" --arg result "$result" '
    (.userStories[] | select(.id == $id)) |= . + {
      explorationCompleted: true,
      explorationResult: $result
    }
  ' "$PRD_FILE" > "$tmp_file" && mv "$tmp_file" "$PRD_FILE"
  
  echo "Marked exploration complete for $story_id"
}

# Helper: Run AI tool with prompt
run_ai_tool() {
  local prompt_file="$1"
  local output=""
  
  if [[ "$TOOL" == "amp" ]]; then
    output=$(cat "$prompt_file" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
  else
    output=$(claude --dangerously-skip-permissions --print < "$prompt_file" 2>&1 | tee /dev/stderr) || true
  fi
  
  echo "$output"
}

# Helper: Build directives context for AI
build_directives_context() {
  local story_id="${1:-}"
  
  if [ ! -f "$DIRECTIVES_FILE" ]; then
    echo ""
    return
  fi
  
  local context=""
  
  # Get active directives
  local directives=$(jq -r '
    [.directives[] | select(.status == "active")] |
    if length > 0 then
      "## God Committee Directives\n\nIMPORTANT: The God Committee has issued the following directives that must be addressed:\n\n" +
      (map("- [\(.priority | ascii_upcase)] \(.content)") | join("\n"))
    else ""
    end
  ' "$DIRECTIVES_FILE" 2>/dev/null)
  
  if [ -n "$directives" ] && [ "$directives" != "" ]; then
    context="$directives\n\n"
  fi
  
  # Get guidance
  local guidance=$(jq -r '
    .guidance |
    if length > 0 then
      "## Committee Guidance\n\nConsider the following guidance from the God Committee:\n\n" +
      (map("- \(.content)") | join("\n"))
    else ""
    end
  ' "$DIRECTIVES_FILE" 2>/dev/null)
  
  if [ -n "$guidance" ] && [ "$guidance" != "" ]; then
    context="${context}${guidance}\n\n"
  fi
  
  # Get recent summaries
  local summaries=$(jq -r '
    .summaries[-3:] |
    if length > 0 then
      "## Recent Committee Discussions\n\n" +
      (map("- \(.content | .[0:200])...") | join("\n"))
    else ""
    end
  ' "$DIRECTIVES_FILE" 2>/dev/null)
  
  if [ -n "$summaries" ] && [ "$summaries" != "" ]; then
    context="${context}${summaries}\n\n"
  fi
  
  echo -e "$context"
}

# Helper: Get directives summary for display
get_directives_summary() {
  if [ ! -f "$DIRECTIVES_FILE" ]; then
    return
  fi
  
  local active=$(jq '[.directives[] | select(.status == "active")] | length' "$DIRECTIVES_FILE" 2>/dev/null || echo "0")
  local critical=$(jq '[.directives[] | select(.status == "active" and .priority == "critical")] | length' "$DIRECTIVES_FILE" 2>/dev/null || echo "0")
  
  if [ "$active" -gt 0 ]; then
    echo "God Committee: $active directives ($critical critical)"
  fi
}

# Print status
echo "========================================"
echo "  Aha Loop v2 - Autonomous Development"
echo "========================================"
echo "Tool: $TOOL"
echo "Phase: $PHASE"
echo "Max Iterations: $MAX_ITERATIONS"
echo "Research Enabled: $RESEARCH_ENABLED"
echo "Exploration Enabled: $EXPLORATION_ENABLED"
echo "Plan Review Enabled: $PLAN_REVIEW_ENABLED"
echo "Quality Review Enabled: $QUALITY_REVIEW_ENABLED"
DIRECTIVES_SUMMARY=$(get_directives_summary)
if [ -n "$DIRECTIVES_SUMMARY" ]; then
  echo "$DIRECTIVES_SUMMARY"
fi
echo "========================================"
echo ""

# Check if PRD exists
if [ ! -f "$PRD_FILE" ]; then
  echo "Error: No prd.json found at $PRD_FILE"
  echo ""
  echo "To get started, use the orchestrator (recommended):"
  echo "  ./scripts/aha-loop/orchestrator.sh"
  echo ""
  echo "Or manually prepare prd.json:"
  echo "  1. Create a PRD: Load the 'prd' skill and describe your feature"
  echo "  2. Convert to JSON: Load the prd-converter skill to convert PRD to prd.json"
  echo "  3. Then run: ./scripts/aha-loop/aha-loop.sh"
  exit 1
fi

# Main loop
for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Aha Loop Iteration $i of $MAX_ITERATIONS"
  echo "==============================================================="
  
  # Get next story
  NEXT_STORY=$(get_next_story)
  
  if [ -z "$NEXT_STORY" ]; then
    echo ""
    echo "All stories complete!"
    echo "<promise>COMPLETE</promise>"
    exit 0
  fi
  
  echo "Next Story: $NEXT_STORY"
  
  # Phase 1: Research (if enabled and needed)
  if [ "$RESEARCH_ENABLED" = "true" ] && [ "$PHASE" = "all" -o "$PHASE" = "research" ]; then
    NEEDS_RESEARCH=$(story_needs_research "$NEXT_STORY")
    
    if [ "$NEEDS_RESEARCH" = "true" ]; then
      echo ""
      echo "--- Phase 1: Research ---"
      
      # Fetch source code if enabled
      if [ "$FETCH_SOURCE_CODE" = "true" ]; then
        echo "Checking for dependencies to fetch..."
        "$SCRIPT_DIR/fetch-source.sh" --from-deps 2>/dev/null || true
      fi
      
      # Run research phase
      if [[ "$TOOL" == "amp" ]]; then
        OUTPUT=$(cat "$SCRIPT_DIR/prompt.md" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
      else
        OUTPUT=$(claude --dangerously-skip-permissions --print < "$SCRIPT_DIR/CLAUDE.md" 2>&1 | tee /dev/stderr) || true
      fi
      
      # Check for completion
      if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
        echo ""
        echo "Aha Loop completed all tasks!"
        exit 0
      fi
      
      echo "Research phase complete."
      sleep 1
    else
      echo "No research needed for $NEXT_STORY (no topics or already completed)"
    fi
  fi
  
  # Phase 2: Parallel Exploration (if enabled and needed)
  if [ "$EXPLORATION_ENABLED" = "true" ] && [ "$PHASE" = "all" -o "$PHASE" = "explore" ]; then
    NEEDS_EXPLORATION=$(story_needs_exploration "$NEXT_STORY")
    
    if [ "$NEEDS_EXPLORATION" = "true" ]; then
      echo ""
      echo "--- Phase 2: Parallel Exploration ---"
      
      # Get all exploration topics
      while IFS= read -r topic_line; do
        if [ -n "$topic_line" ]; then
          topic="${topic_line%%:*}"
          approaches="${topic_line#*:}"
          
          echo ""
          echo "Exploring decision point: $topic"
          if [ -n "$approaches" ]; then
            echo "Approaches to try: $approaches"
          fi
          
          # Run exploration
          run_exploration "$NEXT_STORY" "$topic" "$approaches"
        fi
      done < <(get_exploration_topics "$NEXT_STORY")
      
      # Mark exploration complete
      mark_exploration_complete "$NEXT_STORY" "See exploration reports in $EXPLORATION_DIR"
      
      echo ""
      echo "Parallel exploration complete."
      sleep 1
    else
      echo "No exploration needed for $NEXT_STORY"
    fi
  fi
  
  # Phase 3: Plan Review (if enabled)
  if [ "$PLAN_REVIEW_ENABLED" = "true" ] && [ "$PHASE" = "all" -o "$PHASE" = "plan-review" ]; then
    # Only run if research or exploration was completed
    RESEARCH_FILE="$RESEARCH_DIR/${NEXT_STORY}-research.md"
    EXPLORATION_FILES=$(ls "$EXPLORATION_DIR/${NEXT_STORY}-"*.md 2>/dev/null | head -1)
    
    if [ -f "$RESEARCH_FILE" ] || [ -n "$EXPLORATION_FILES" ]; then
      echo ""
      echo "--- Phase 3: Plan Review ---"
      
      if [[ "$TOOL" == "amp" ]]; then
        OUTPUT=$(cat "$SCRIPT_DIR/prompt.md" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
      else
        OUTPUT=$(claude --dangerously-skip-permissions --print < "$SCRIPT_DIR/CLAUDE.md" 2>&1 | tee /dev/stderr) || true
      fi
      
      if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
        echo ""
        echo "Aha Loop completed all tasks!"
        exit 0
      fi
      
      echo "Plan review complete."
      sleep 1
    fi
  fi
  
  # Phase 4: Implementation
  if [ "$PHASE" = "all" -o "$PHASE" = "implement" ]; then
    echo ""
    echo "--- Phase 4: Implementation ---"
    
    if [[ "$TOOL" == "amp" ]]; then
      OUTPUT=$(cat "$SCRIPT_DIR/prompt.md" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
    else
      OUTPUT=$(claude --dangerously-skip-permissions --print < "$SCRIPT_DIR/CLAUDE.md" 2>&1 | tee /dev/stderr) || true
    fi
    
    if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
      echo ""
      echo "Aha Loop completed all tasks!"
      exit 0
    fi
  fi
  
  echo ""
  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Aha Loop reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
