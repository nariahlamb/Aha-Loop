# Aha Loop - Claude Code Instructions

## Project Overview

This is the **Aha Loop** project - a fully autonomous AI development system that extends [Ralph](https://github.com/snarktank/ralph) with planning, research, and oversight capabilities.

## Aha Loop Autonomous Development System

This project uses Aha Loop, a fully autonomous AI development system with:
- Interactive vision building
- Parallel exploration via git worktrees
- Full observability and thought logging
- Automatic skill creation and maintenance
- Unlimited resource access
- **God Committee** - Independent oversight layer with supreme authority

### Starting a New Project

#### Interactive Vision Building (Recommended)

```bash
./scripts/aha-loop/orchestrator.sh --build-vision
```

You'll be guided through questions to build a complete vision.

#### Manual Vision

```bash
cp scripts/aha-loop/templates/project.vision.template.md project.vision.md
# Edit the file
./scripts/aha-loop/orchestrator.sh --tool claude
```

### Workflow Phases

```
Vision → Architecture → Roadmap → [PRD Execution Loop]
                                         │
                         Research → Plan Review → Implement → QA
                              ▲                              │
                              └──────────────────────────────┘
```

### Parallel Exploration

When facing significant decisions, explore multiple approaches:

```bash
# Let AI suggest approaches
./scripts/aha-loop/parallel-explorer.sh explore "authentication strategy"

# Specify approaches
./scripts/aha-loop/parallel-explorer.sh explore "database layer" --approaches "sqlx,diesel,sea-orm"

# Evaluate results
./scripts/aha-loop/parallel-explorer.sh evaluate explore-xxx

# Merge best approach
./scripts/aha-loop/parallel-explorer.sh merge explore-xxx chosen-approach
```

### Skills Location

All skills are in `.claude/skills/`:

| Skill | File | Purpose |
|-------|------|---------|
| vision | `vision/SKILL.md` | Parse project goals |
| vision-builder | `vision-builder/SKILL.md` | Interactive vision building |
| architect | `architect/SKILL.md` | Design tech stack |
| roadmap | `roadmap/SKILL.md` | Plan milestones |
| parallel-explore | `parallel-explore/SKILL.md` | Guide parallel exploration |
| skill-creator | `skill-creator/SKILL.md` | Create new skills |
| doc-review | `doc-review/SKILL.md` | Review documentation |
| observability | `observability/SKILL.md` | Log AI thoughts |
| god-member | `god-member/SKILL.md` | God Committee member behavior |
| god-consensus | `god-consensus/SKILL.md` | Consensus building |
| god-intervention | `god-intervention/SKILL.md` | Intervention execution |

### Key Commands

```bash
# Main orchestrator
./scripts/aha-loop/orchestrator.sh --tool claude
./scripts/aha-loop/orchestrator.sh --build-vision
./scripts/aha-loop/orchestrator.sh --explore "task"
./scripts/aha-loop/orchestrator.sh --maintenance

# Parallel exploration
./scripts/aha-loop/parallel-explorer.sh explore "task"
./scripts/aha-loop/parallel-explorer.sh status
./scripts/aha-loop/parallel-explorer.sh evaluate explore-xxx
./scripts/aha-loop/parallel-explorer.sh cleanup --all

# Skill management
./scripts/aha-loop/skill-manager.sh list
./scripts/aha-loop/skill-manager.sh create my-skill
./scripts/aha-loop/skill-manager.sh review

# Documentation
./scripts/aha-loop/doc-cleaner.sh --report
./scripts/aha-loop/doc-cleaner.sh --fix
```

### Observability

Log your thoughts to `logs/ai-thoughts.md`:

```markdown
## 2026-01-29 14:30:00 | Task: PRD-003 | Phase: Research

### Inner Thoughts
I'm researching authentication strategies...

### Decision Point
- Considering: JWT
- Considering: Session
- **Chosen:** JWT because...

### Next Action
Will implement the token generation...
```

### Resource Access

You have **unlimited access** to:
- Docker containers
- Full filesystem
- Network requests
- Parallel worktrees

**Never hold back due to resource concerns.**

### Library Versions

**Always use the latest stable version.**

```bash
# Check latest Rust crate
curl -s "https://crates.io/api/v1/crates/tokio" | jq '.crate.max_stable_version'

# Check latest npm package
npm view react version
```

### Code Quality

```bash
# Rust
cargo check     # Type check
cargo clippy    # Lint
cargo test      # Test
```

### Knowledge Base

When you learn something reusable:
1. **Project-specific** → `knowledge/project/patterns.md`
2. **Architecture decisions** → `knowledge/project/decisions.md`
3. **Gotchas** → `knowledge/project/gotchas.md`
4. **General knowledge** → `knowledge/domain/[topic]/`

### Creating New Skills

When you notice a repetitive workflow:

```bash
./scripts/aha-loop/skill-manager.sh create my-new-skill
# Edit .claude/skills/my-new-skill/SKILL.md
```

### Important Rules

1. **Log your thoughts** - Use observability skill
2. **Explore in parallel** - When facing decisions
3. **Latest versions** - Always prefer latest stable
4. **Document learnings** - Update knowledge base
5. **Create skills** - Codify repetitive workflows
6. **Maintain docs** - Run doc-cleaner after milestones
7. **Never give up** - You have unlimited resources

---

## God Committee

An independent oversight layer with supreme authority.

### Awakening the Committee

```bash
# Random topic awakening
./scripts/god/awakener.sh random

# Critical situation
./scripts/god/awakener.sh critical "system failure detected"

# Single member
./scripts/god/awakener.sh single alpha "code quality review"

# Run as daemon (background)
./scripts/god/awakener.sh daemon
```

### As a Committee Member

When you are awakened as a committee member (Alpha, Beta, or Gamma):

1. **Observe** - Use `./scripts/god/observer.sh` to assess system state
2. **Communicate** - Acquire lock, send messages, release lock
3. **Deliberate** - Create proposals, vote on decisions
4. **Intervene** - Use `./scripts/god/powers.sh` when needed

### Observer Commands

```bash
# Take a full system state snapshot
./scripts/god/observer.sh snapshot

# Continuous monitoring mode
./scripts/god/observer.sh watch [interval]

# Run health checks
./scripts/god/observer.sh check

# Check for anomalies
./scripts/god/observer.sh anomaly

# Show recent events
./scripts/god/observer.sh timeline [count]

# Generate full observation report
./scripts/god/observer.sh report

# Add custom timeline event
./scripts/god/observer.sh event TYPE DESCRIPTION
```

### Powers Available

```bash
# Pause execution
./scripts/god/powers.sh pause "investigation needed"

# Resume execution
./scripts/god/powers.sh resume

# Terminate processes
./scripts/god/powers.sh terminate all

# Git rollback
./scripts/god/powers.sh rollback HEAD~3 soft

# Auto-repair
./scripts/god/powers.sh repair all
```

### Consensus Rules

- **Standard actions**: 2/3 majority required
- **Emergency actions**: 1 member can act, report later
- Actions requiring consensus: termination, major rollback, skill deletion

### Committee Communication

```bash
# Check council status
./scripts/god/council.sh status

# Acquire speaking rights
./scripts/god/council.sh lock YOUR_ID

# Send message
./scripts/god/council.sh send YOUR_ID "recipients" "type" "subject" "body"

# Create proposal
./scripts/god/council.sh propose YOUR_ID "type" "description" "rationale"

# Vote
./scripts/god/council.sh vote YOUR_ID "decision-id" "approve|reject|abstain" "comment"

# Release speaking rights
./scripts/god/council.sh unlock YOUR_ID
```

### Directives System

Communicate decisions to the execution layer:

```bash
# Publish directive (mandatory - critical ones pause execution)
./scripts/god/council.sh publish YOUR_ID directive critical "Security issue found in X"

# Publish guidance (suggestion - included in AI context)
./scripts/god/council.sh publish YOUR_ID guidance normal "Consider approach Y for Z"

# Publish summary (context from discussions)
./scripts/god/council.sh publish YOUR_ID summary normal "Decided to use pattern X"

# Mark directive complete
./scripts/god/council.sh complete DIRECTIVE_ID

# View all directives
./scripts/god/council.sh directives
```

### Git Hook Integration

Auto-awaken committee on commits:

```bash
./scripts/god/install-hooks.sh        # Install
./scripts/god/install-hooks.sh --uninstall  # Remove
```

Read the full skills at `.claude/skills/god-member/SKILL.md`, `.claude/skills/god-consensus/SKILL.md`, and `.claude/skills/god-intervention/SKILL.md`.
