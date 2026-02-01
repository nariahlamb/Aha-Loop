#!/bin/bash
# Aha Loop Orchestrator - Autonomous Project Management
# Manages the full project lifecycle from vision to completion
#
# Usage:
#   ./orchestrator.sh [--tool amp|claude] [--phase vision|architect|roadmap|execute|all]
#   ./orchestrator.sh --build-vision      Interactive vision building
#   ./orchestrator.sh --explore "task"    Start parallel exploration
#   ./orchestrator.sh --maintenance       Run maintenance tasks
#
# Phases:
#   vision    - Parse project.vision.md and create vision analysis
#   architect - Research and decide on technology stack
#   roadmap   - Create project roadmap with milestones and PRDs
#   execute   - Execute PRDs using aha-loop.sh
#   all       - Run all phases (default)

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"
LOG_FILE="$PROJECT_ROOT/logs/ai-thoughts.md"
GOD_DIR="$PROJECT_ROOT/.god"
DIRECTIVES_FILE="$GOD_DIR/directives.json"
COUNCIL_SCRIPT="$PROJECT_ROOT/scripts/god/council.sh"

# Project files
VISION_FILE="$PROJECT_ROOT/project.vision.md"
VISION_ANALYSIS="$PROJECT_ROOT/project.vision-analysis.md"
ARCHITECTURE_FILE="$PROJECT_ROOT/project.architecture.md"
ROADMAP_FILE="$PROJECT_ROOT/project.roadmap.json"

# Default settings
TOOL="claude"
PHASE="all"
MAX_PRDS=10
MAX_ITERATIONS=10
BUILD_VISION=false
EXPLORE_TASK=""
MAINTENANCE=false

# Ensure logs directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Parse arguments
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
    --max-prds)
      MAX_PRDS="$2"
      shift 2
      ;;
    --max-iterations)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --max-iterations=*)
      MAX_ITERATIONS="${1#*=}"
      shift
      ;;
    --build-vision)
      BUILD_VISION=true
      shift
      ;;
    --explore)
      EXPLORE_TASK="$2"
      shift 2
      ;;
    --explore=*)
      EXPLORE_TASK="${1#*=}"
      shift
      ;;
    --maintenance)
      MAINTENANCE=true
      shift
      ;;
    --help|-h)
      echo "Aha Loop Orchestrator - Autonomous Project Management"
      echo ""
      echo "Usage: ./orchestrator.sh [options]"
      echo ""
      echo "Options:"
      echo "  --tool amp|claude    AI tool to use (default: claude)"
      echo "  --phase PHASE        Phase to run (vision|architect|roadmap|execute|all)"
      echo "  --max-prds N         Maximum PRDs to execute per run (default: 10)"
      echo "  --max-iterations N   Maximum iterations per PRD (default: 10)"
      echo "  --build-vision       Interactive vision building"
      echo "  --explore TASK       Start parallel exploration for a task"
      echo "  --maintenance        Run maintenance tasks (doc cleanup, skill review)"
      echo "  --help               Show this help message"
      echo ""
      echo "Phases:"
      echo "  vision     Parse project.vision.md"
      echo "  architect  Design architecture and select tech stack"
      echo "  roadmap    Create project roadmap"
      echo "  execute    Execute PRDs with aha-loop.sh"
      echo "  all        Run all phases in sequence"
      echo ""
      echo "Examples:"
      echo "  ./orchestrator.sh                          # Run all phases"
      echo "  ./orchestrator.sh --build-vision           # Interactive vision building"
      echo "  ./orchestrator.sh --explore 'auth system'  # Parallel exploration"
      echo "  ./orchestrator.sh --maintenance            # Run maintenance"
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

# Validate tool
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp' or 'claude'."
  exit 1
fi

# Validate phase
VALID_PHASES="vision architect roadmap execute all"
if [[ ! " $VALID_PHASES " =~ " $PHASE " ]]; then
  echo "Error: Invalid phase '$PHASE'."
  echo "Valid phases: $VALID_PHASES"
  exit 1
fi

# Load config if exists (only use config values if not overridden by command line)
CONFIG_MAX_PRDS=10
CONFIG_MAX_ITERATIONS=10
if [ -f "$CONFIG_FILE" ]; then
  CONFIG_MAX_PRDS=$(jq -r '.orchestrator.maxPRDsPerRun // 10' "$CONFIG_FILE")
  CONFIG_MAX_ITERATIONS=$(jq -r '.safeguards.maxIterationsPerStory // 10' "$CONFIG_FILE")
  OBSERVABILITY_ENABLED=$(jq -r '.observability.enabled // true' "$CONFIG_FILE")
  PARALLEL_ENABLED=$(jq -r '.parallelExploration.enabled // true' "$CONFIG_FILE")
  DOC_MAINTENANCE_ENABLED=$(jq -r '.docMaintenance.enabled // true' "$CONFIG_FILE")
else
  OBSERVABILITY_ENABLED=true
  PARALLEL_ENABLED=true
  DOC_MAINTENANCE_ENABLED=true
fi

# Apply config values only if not overridden by command line (still at default)
if [ "$MAX_PRDS" -eq 10 ] && [ "$CONFIG_MAX_PRDS" != "10" ]; then
  MAX_PRDS="$CONFIG_MAX_PRDS"
fi
if [ "$MAX_ITERATIONS" -eq 10 ] && [ "$CONFIG_MAX_ITERATIONS" != "10" ]; then
  MAX_ITERATIONS="$CONFIG_MAX_ITERATIONS"
fi

# Helper: Check for critical directives from God Committee
check_critical_directives() {
  if [ ! -f "$DIRECTIVES_FILE" ]; then
    return 1
  fi
  
  local critical_count=$(jq '[.directives[] | select(.status == "active" and .priority == "critical")] | length' "$DIRECTIVES_FILE" 2>/dev/null || echo "0")
  
  if [ "$critical_count" -gt 0 ]; then
    return 0
  fi
  return 1
}

# Helper: Get active directives for display
get_directives_summary() {
  if [ ! -f "$DIRECTIVES_FILE" ]; then
    echo "No directives"
    return
  fi
  
  local active=$(jq '[.directives[] | select(.status == "active")] | length' "$DIRECTIVES_FILE" 2>/dev/null || echo "0")
  local critical=$(jq '[.directives[] | select(.status == "active" and .priority == "critical")] | length' "$DIRECTIVES_FILE" 2>/dev/null || echo "0")
  local guidance=$(jq '.guidance | length' "$DIRECTIVES_FILE" 2>/dev/null || echo "0")
  
  echo "Directives: $active active ($critical critical), Guidance: $guidance"
}

# Helper: Build directives context for AI
build_directives_context() {
  local target_prd="${1:-}"
  
  if [ ! -f "$DIRECTIVES_FILE" ]; then
    echo ""
    return
  fi
  
  local context=""
  
  # Get active directives
  local directives
  if [ -n "$target_prd" ]; then
    directives=$(jq -r --arg prd "$target_prd" '
      [.directives[] | select(.status == "active" and (.targetPrd == null or .targetPrd == $prd))] |
      if length > 0 then
        "## God Committee Directives\n\n" +
        (map("- [\(.priority | ascii_upcase)] \(.content)") | join("\n"))
      else ""
      end
    ' "$DIRECTIVES_FILE" 2>/dev/null)
  else
    directives=$(jq -r '
      [.directives[] | select(.status == "active")] |
      if length > 0 then
        "## God Committee Directives\n\n" +
        (map("- [\(.priority | ascii_upcase)] \(.content)") | join("\n"))
      else ""
      end
    ' "$DIRECTIVES_FILE" 2>/dev/null)
  fi
  
  if [ -n "$directives" ] && [ "$directives" != "" ]; then
    context="$directives\n\n"
  fi
  
  # Get guidance
  local guidance
  if [ -n "$target_prd" ]; then
    guidance=$(jq -r --arg prd "$target_prd" '
      [.guidance[] | select(.targetPrd == null or .targetPrd == $prd)] |
      if length > 0 then
        "## Committee Guidance\n\n" +
        (map("- \(.content)") | join("\n"))
      else ""
      end
    ' "$DIRECTIVES_FILE" 2>/dev/null)
  else
    guidance=$(jq -r '
      .guidance |
      if length > 0 then
        "## Committee Guidance\n\n" +
        (map("- \(.content)") | join("\n"))
      else ""
      end
    ' "$DIRECTIVES_FILE" 2>/dev/null)
  fi
  
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

# Print header
echo "========================================"
echo "  Aha Loop Orchestrator"
echo "  Autonomous Project Management"
echo "========================================"
echo "Tool: $TOOL"
echo "Phase: $PHASE"
echo "Project: $PROJECT_ROOT"
echo "$(get_directives_summary)"
echo "========================================"
echo ""

# Check for critical directives before proceeding
if check_critical_directives; then
  echo "!!! CRITICAL DIRECTIVES FROM GOD COMMITTEE !!!"
  echo ""
  jq -r '.directives[] | select(.status == "active" and .priority == "critical") | "[\(.author)] \(.content)"' "$DIRECTIVES_FILE" 2>/dev/null
  echo ""
  echo "Execution is paused due to critical directives."
  echo "Please address these issues before continuing."
  echo ""
  echo "To view all directives: ./scripts/god/council.sh directives"
  echo "To mark resolved: ./scripts/god/council.sh complete DIRECTIVE_ID"
  echo ""
  exit 1
fi

# Helper: Log to observability file
log_thought() {
  if [ "$OBSERVABILITY_ENABLED" != "true" ]; then
    return
  fi
  
  local task="$1"
  local phase="$2"
  local content="$3"
  
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  
  cat >> "$LOG_FILE" << EOF

## $timestamp | Task: $task | Phase: $phase

$content

---
EOF
}

# Helper: Run AI with a prompt
run_ai() {
  local prompt="$1"
  local output=""
  
  if [[ "$TOOL" == "amp" ]]; then
    output=$(echo "$prompt" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
  else
    output=$(echo "$prompt" | claude --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true
  fi
  
  echo "$output"
}

# Helper: Check if file exists and is recent
file_exists_and_recent() {
  local file="$1"
  local max_age_hours="${2:-24}"
  
  if [ ! -f "$file" ]; then
    return 1
  fi
  
  # Check if file was modified within max_age_hours
  local file_age=$(( ($(date +%s) - $(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file")) / 3600 ))
  if [ "$file_age" -gt "$max_age_hours" ]; then
    return 1
  fi
  
  return 0
}

# Interactive Vision Building
run_vision_builder() {
  echo "=== Interactive Vision Builder ==="
  echo ""
  
  log_thought "Vision" "Building" "Starting interactive vision building session."
  
  local prompt="Load the vision-builder skill from .claude/skills/vision-builder/SKILL.md. 

Help the user build a complete project vision through guided conversation.
Use the AskQuestion tool to ask structured questions.
After gathering all information, generate a complete project.vision.md file.

Start by introducing yourself and asking about the project type."
  
  run_ai "$prompt"
  
  if [ -f "$VISION_FILE" ]; then
    echo ""
    echo "Vision document created: $VISION_FILE"
    log_thought "Vision" "Complete" "Vision document created successfully."
  fi
}

# Parallel Exploration
run_parallel_exploration() {
  local task="$1"
  
  echo "=== Parallel Exploration ==="
  echo "Task: $task"
  echo ""
  
  if [ "$PARALLEL_ENABLED" != "true" ]; then
    echo "Parallel exploration is disabled in config."
    exit 1
  fi
  
  log_thought "Exploration" "Starting" "### Parallel Exploration
  
**Task:** $task

Starting parallel exploration to find the best approach."
  
  # Delegate to parallel-explorer.sh
  "$SCRIPT_DIR/parallel-explorer.sh" explore "$task" --tool "$TOOL"
}

# Maintenance Tasks
run_maintenance() {
  echo "=== Maintenance Tasks ==="
  echo ""
  
  log_thought "Maintenance" "Starting" "Running scheduled maintenance tasks."
  
  # Document cleanup
  if [ "$DOC_MAINTENANCE_ENABLED" = "true" ]; then
    echo "Running documentation review..."
    "$SCRIPT_DIR/doc-cleaner.sh" --report
    echo ""
  fi
  
  # Skill review
  echo "Running skill review..."
  "$SCRIPT_DIR/skill-manager.sh" review
  echo ""
  
  # Worktree cleanup
  if [ "$PARALLEL_ENABLED" = "true" ]; then
    echo "Checking for stale worktrees..."
    local stale_count=$(git worktree list --porcelain | grep -c "^worktree" || echo "0")
    if [ "$stale_count" -gt 5 ]; then
      echo "Found $stale_count worktrees. Consider running: ./parallel-explorer.sh cleanup --all"
    else
      echo "Worktree count is healthy: $stale_count"
    fi
  fi
  
  log_thought "Maintenance" "Complete" "Maintenance tasks completed."
  
  echo ""
  echo "Maintenance complete."
}

# Phase 1: Vision Analysis
run_vision_phase() {
  echo "=== Phase 1: Vision Analysis ==="
  echo ""
  
  # Check for vision file
  if [ ! -f "$VISION_FILE" ]; then
    echo "project.vision.md not found."
    echo ""
    
    # Offer to build vision interactively
    local use_builder=$(jq -r '.vision.useVisionBuilder // true' "$CONFIG_FILE" 2>/dev/null)
    
    if [ "$use_builder" = "true" ]; then
      echo "Would you like to build a vision interactively? (Y/n)"
      read -r response
      if [[ ! "$response" =~ ^[Nn] ]]; then
        run_vision_builder
      else
        echo "Please create project.vision.md manually."
        echo "See: scripts/aha-loop/templates/project.vision.template.md"
        exit 1
      fi
    else
      echo "Please create a project.vision.md file with your project goals."
      echo "See scripts/aha-loop/templates/project.vision.template.md for format."
      exit 1
    fi
  fi
  
  echo "Found: $VISION_FILE"
  
  log_thought "Vision" "Analysis" "### Starting Vision Analysis

Found vision file, beginning analysis."
  
  # Check if analysis already exists and is recent
  if file_exists_and_recent "$VISION_ANALYSIS" 168; then  # 1 week
    echo "Vision analysis exists and is recent. Skipping."
    echo "Delete $VISION_ANALYSIS to regenerate."
    return 0
  fi
  
  echo "Analyzing project vision..."
  
  local prompt="Load the vision skill from .claude/skills/vision/SKILL.md and analyze the project vision in project.vision.md. Save the analysis to project.vision-analysis.md.

Also load the observability skill and log your thoughts to logs/ai-thoughts.md."
  
  run_ai "$prompt"
  
  if [ -f "$VISION_ANALYSIS" ]; then
    echo "Vision analysis complete: $VISION_ANALYSIS"
    log_thought "Vision" "Complete" "Vision analysis completed successfully."
  else
    echo "Warning: Vision analysis file not created"
    log_thought "Vision" "Warning" "Vision analysis file was not created."
  fi
}

# Phase 2: Architecture Design
run_architect_phase() {
  echo ""
  echo "=== Phase 2: Architecture Design ==="
  echo ""
  
  # Check prerequisites
  if [ ! -f "$VISION_ANALYSIS" ]; then
    echo "Error: Vision analysis not found. Run vision phase first."
    exit 1
  fi
  
  log_thought "Architect" "Starting" "### Architecture Design Phase

Beginning technology research and architecture design."
  
  # Check if architecture already exists
  if file_exists_and_recent "$ARCHITECTURE_FILE" 168; then
    echo "Architecture document exists and is recent. Skipping."
    echo "Delete $ARCHITECTURE_FILE to regenerate."
    return 0
  fi
  
  echo "Designing system architecture..."
  
  local prompt="Load the architect skill from .claude/skills/architect/SKILL.md. Read project.vision-analysis.md and design the system architecture. 

IMPORTANT: Research and select the LATEST STABLE VERSIONS of all technologies.
Check crates.io, npm, or relevant package registries for current versions.

Save to project.architecture.md and log your decision process to logs/ai-thoughts.md."
  
  run_ai "$prompt"
  
  if [ -f "$ARCHITECTURE_FILE" ]; then
    echo "Architecture design complete: $ARCHITECTURE_FILE"
    log_thought "Architect" "Complete" "Architecture design completed."
  else
    echo "Warning: Architecture file not created"
  fi
}

# Phase 3: Roadmap Planning
run_roadmap_phase() {
  echo ""
  echo "=== Phase 3: Roadmap Planning ==="
  echo ""
  
  # Check prerequisites
  if [ ! -f "$ARCHITECTURE_FILE" ]; then
    echo "Error: Architecture document not found. Run architect phase first."
    exit 1
  fi
  
  log_thought "Roadmap" "Starting" "### Roadmap Planning Phase

Creating project milestones and PRD queue."
  
  # Check if roadmap already exists
  if [ -f "$ROADMAP_FILE" ]; then
    local status=$(jq -r '.status' "$ROADMAP_FILE" 2>/dev/null)
    if [ "$status" = "completed" ]; then
      echo "Project already completed!"
      return 0
    fi
    echo "Roadmap exists. Checking for updates needed..."
  else
    echo "Creating project roadmap..."
  fi
  
  local prompt="Load the roadmap skill from .claude/skills/roadmap/SKILL.md. Read project.vision-analysis.md and project.architecture.md. Create or update project.roadmap.json with milestones and PRDs. Generate PRD stub files in tasks/ directory."
  
  run_ai "$prompt"
  
  if [ -f "$ROADMAP_FILE" ]; then
    echo "Roadmap planning complete: $ROADMAP_FILE"
    echo ""
    echo "Milestones:"
    jq -r '.milestones[] | "  \(.id): \(.title) [\(.status)]"' "$ROADMAP_FILE"
    log_thought "Roadmap" "Complete" "Roadmap created with milestones."
  else
    echo "Warning: Roadmap file not created"
  fi
}

# Phase 4: Execute PRDs
run_execute_phase() {
  echo ""
  echo "=== Phase 4: PRD Execution ==="
  echo ""
  
  # Check prerequisites
  if [ ! -f "$ROADMAP_FILE" ]; then
    echo "Error: Roadmap not found. Run roadmap phase first."
    exit 1
  fi
  
  local prds_executed=0
  
  while [ $prds_executed -lt $MAX_PRDS ]; do
    # Get current PRD from roadmap
    local current_prd=$(jq -r '.currentPRD // empty' "$ROADMAP_FILE")
    
    if [ -z "$current_prd" ]; then
      # Find next pending PRD
      current_prd=$(jq -r '
        .milestones[] | 
        select(.status != "completed") | 
        .prds[] | 
        select(.status == "pending" or .status == "in_progress") | 
        .id
      ' "$ROADMAP_FILE" | head -1)
    fi
    
    if [ -z "$current_prd" ]; then
      echo "No pending PRDs found. Project may be complete!"
      
      # Check if all milestones are complete
      local incomplete=$(jq -r '.milestones[] | select(.status != "completed") | .id' "$ROADMAP_FILE" | head -1)
      if [ -z "$incomplete" ]; then
        echo ""
        echo "=========================================="
        echo "  PROJECT COMPLETE!"
        echo "=========================================="
        jq '.status = "completed"' "$ROADMAP_FILE" > "$ROADMAP_FILE.tmp" && mv "$ROADMAP_FILE.tmp" "$ROADMAP_FILE"
        
        log_thought "Project" "Complete" "### Project Completed!

All milestones and PRDs have been completed successfully."
        
        # Run maintenance after project completion
        if [ "$DOC_MAINTENANCE_ENABLED" = "true" ]; then
          echo ""
          echo "Running post-project maintenance..."
          run_maintenance
        fi
      fi
      break
    fi
    
    echo "Executing PRD: $current_prd"
    echo ""
    
    log_thought "$current_prd" "Starting" "### PRD Execution Starting

Beginning work on PRD: $current_prd"
    
    # Get PRD file path
    local prd_file=$(jq -r --arg id "$current_prd" '
      .milestones[].prds[] | 
      select(.id == $id) | 
      .prdFile
    ' "$ROADMAP_FILE")
    
    if [ -z "$prd_file" ] || [ ! -f "$PROJECT_ROOT/$prd_file" ]; then
      echo "Error: PRD file not found: $prd_file"
      echo "Generating PRD content..."
      
      local directives_ctx=$(build_directives_context "$current_prd")
      local prompt="Load the prd skill. Read the roadmap entry for $current_prd in project.roadmap.json and generate the full PRD content. Save to $prd_file.

${directives_ctx}"
      run_ai "$prompt"
    fi
    
    # Convert PRD to prd.json if needed
    echo "Converting PRD to executable format..."
    local directives_ctx=$(build_directives_context "$current_prd")
    local prompt="Load the prd-converter skill. Convert $prd_file to scripts/aha-loop/prd.json format.

${directives_ctx}"
    run_ai "$prompt"
    
    # Update roadmap to mark PRD as in_progress
    jq --arg id "$current_prd" '
      .currentPRD = $id |
      (.milestones[].prds[] | select(.id == $id)).status = "in_progress"
    ' "$ROADMAP_FILE" > "$ROADMAP_FILE.tmp" && mv "$ROADMAP_FILE.tmp" "$ROADMAP_FILE"
    
    # Execute the PRD with aha-loop.sh
    echo "Running Aha Loop for $current_prd..."
    "$SCRIPT_DIR/aha-loop.sh" --tool "$TOOL" --max-iterations "$MAX_ITERATIONS"
    local aha_loop_exit=$?
    
    if [ $aha_loop_exit -eq 0 ]; then
      echo "PRD $current_prd completed successfully!"
      
      # Update roadmap
      local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      jq --arg id "$current_prd" --arg ts "$timestamp" '
        (.milestones[].prds[] | select(.id == $id)).status = "completed" |
        (.milestones[].prds[] | select(.id == $id)).completedAt = $ts |
        .currentPRD = null |
        .changelog += [{
          "timestamp": $ts,
          "action": "prd_completed",
          "prdId": $id,
          "description": "PRD completed successfully"
        }]
      ' "$ROADMAP_FILE" > "$ROADMAP_FILE.tmp" && mv "$ROADMAP_FILE.tmp" "$ROADMAP_FILE"
      
      log_thought "$current_prd" "Complete" "### PRD Completed

PRD $current_prd completed successfully."
      
      # Check if milestone is complete
      local milestone_id=$(jq -r --arg id "$current_prd" '
        .milestones[] | 
        select(.prds[].id == $id) | 
        .id
      ' "$ROADMAP_FILE")
      
      local pending_in_milestone=$(jq -r --arg mid "$milestone_id" '
        .milestones[] | 
        select(.id == $mid) | 
        .prds[] | 
        select(.status != "completed") | 
        .id
      ' "$ROADMAP_FILE" | head -1)
      
      if [ -z "$pending_in_milestone" ]; then
        echo "Milestone $milestone_id completed!"
        jq --arg mid "$milestone_id" --arg ts "$timestamp" '
          (.milestones[] | select(.id == $mid)).status = "completed" |
          (.milestones[] | select(.id == $mid)).completedAt = $ts |
          .changelog += [{
            "timestamp": $ts,
            "action": "milestone_completed",
            "milestoneId": $mid,
            "description": "Milestone completed"
          }]
        ' "$ROADMAP_FILE" > "$ROADMAP_FILE.tmp" && mv "$ROADMAP_FILE.tmp" "$ROADMAP_FILE"
        
        log_thought "$milestone_id" "Milestone Complete" "### Milestone Completed!

Milestone $milestone_id has been completed."
        
        # Trigger roadmap review after milestone completion
        echo "Reviewing roadmap after milestone completion..."
        local prompt="Load the roadmap skill. Review project.roadmap.json after completing milestone $milestone_id. Update if new PRDs are needed based on learnings."
        run_ai "$prompt"
        
        # Run doc maintenance after milestone
        if [ "$DOC_MAINTENANCE_ENABLED" = "true" ]; then
          echo "Running post-milestone maintenance..."
          "$SCRIPT_DIR/doc-cleaner.sh" --report 2>/dev/null || true
        fi
      fi
      
      prds_executed=$((prds_executed + 1))
    else
      echo "PRD $current_prd did not complete. Check progress.txt for details."
      log_thought "$current_prd" "Failed" "### PRD Execution Failed

PRD $current_prd did not complete successfully. Check progress.txt for details."
      break
    fi
    
    echo ""
  done
  
  echo ""
  echo "Executed $prds_executed PRDs in this run."
}

# Handle special modes first
if [ "$BUILD_VISION" = true ]; then
  run_vision_builder
  exit 0
fi

if [ -n "$EXPLORE_TASK" ]; then
  run_parallel_exploration "$EXPLORE_TASK"
  exit 0
fi

if [ "$MAINTENANCE" = true ]; then
  run_maintenance
  exit 0
fi

# Main execution
case $PHASE in
  vision)
    run_vision_phase
    ;;
  architect)
    run_architect_phase
    ;;
  roadmap)
    run_roadmap_phase
    ;;
  execute)
    run_execute_phase
    ;;
  all)
    run_vision_phase
    run_architect_phase
    run_roadmap_phase
    run_execute_phase
    ;;
esac

echo ""
echo "Orchestrator finished."
