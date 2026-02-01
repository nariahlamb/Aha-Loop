# The Story Behind Aha Loop

> How I extended Ralph into a fully autonomous AI development system

## From Tab to Agent: How Far Have We Come?

AI has evolved rapidly in recent years:

- **Tab Era**: GitHub Copilot emerged, and we first experienced the magic of AI code completion. Press Tab, code auto-completes.
- **Chat Era**: Cursor, Windsurf let us converse with AI. "Write me a login feature" — and it actually could.
- **Agent Era**: Claude Code, Codex, OpenCode... AI no longer just answers questions — it starts to think, plan, and execute autonomously.

Anyone who has truly experienced these tools knows the efficiency gap between "traditional coding" and "vibe coding." Without exaggeration, what used to take a week can now be done in the time it takes to write one sentence and drink a cup of coffee.

**But I kept wondering: Is this really AI's limit?**

Remember Devin, which briefly captured everyone's attention? It promised to complete entire projects independently but ultimately couldn't deliver. Over a year later, could I perhaps build something similar? Even just a minimal MVP?

## Standing on the Shoulders of Giants

Before starting, I studied [Ralph](https://github.com/snarktank/ralph), a project that's been gaining attention recently. Its core idea is elegant:

> Write requirements as PRD → Break into User Stories → Let AI loop through each Story → Until all complete

```
PRD → Stories → AI Loop → Done
```

This is brilliant. Each iteration is a **fresh AI instance** with clean context; memory is maintained through `prd.json` and `progress.txt`; Stories are tackled one by one until everything is complete.

But after using it for a while, I found several issues:

1. **Where does the PRD come from?** Ralph assumes you already have a written PRD, but what about projects starting from zero?
2. **Who decides the architecture?** Tech stack selection, system design — these decisions need to be made before the PRD is even written.
3. **What if AI doesn't know the technology?** If a Story involves an unfamiliar library, it might write outdated or incorrect code.
4. **How to choose between multiple approaches?** If there are several implementation options, on what basis does AI pick one?
5. **Who supervises the AI?** If it goes off track, gets stuck in loops, or writes disastrous code — what then?

These questions led me to think deeper and extend beyond Ralph's foundation.

## I Created a New Folder

One afternoon a few days ago, I stopped what I was doing and created an empty directory.

I started thinking: **What's needed before the PRD?**

I typed the first word — **"Vision"**.

What is a vision? I believe a vision answers two "whys":
- Why do we need it?
- Why should it be this way?

I call this **value alignment**. Just like humans working on projects — if you don't know why you're building something, you won't know what it should become.

## From Vision to Roadmap: Completing the Pre-PRD Phases

With vision in place, I asked myself: **What's next?**

I recalled my own project workflow. After getting requirements, what do I do first?

**Architecture design.**

What tech stack? Which database? Which frontend framework? These decisions shape the entire project's direction.

So I added the second phase — **"Architecture"**.

But architecture alone isn't enough. A large project can't have just one PRD; it needs to be broken into multiple phases.

I added the third phase — **"Roadmap"**.

Breaking the project into milestones, each milestone containing several PRDs, each PRD then handed to Ralph's execution loop.

At this point, a complete workflow took shape in my mind:

```
               Original Ralph
                     ↓
Vision → Architecture → Roadmap → [PRD → Execute]
                                        ↑
                                Borrowed from Ralph
```

**On top of Ralph's execution engine, I completed the three pre-launch phases.**

Looks complete? No, the challenges were just beginning.

## When AI Encounters the Unknown

During execution testing, I hit the first major problem:

**What if AI encounters technology it doesn't understand?**

For example, a PRD requires using a certain library for a specific feature, but AI's training data might only have outdated version information. Will it use wrong APIs? Will it write obsolete code?

The traditional approach is to tell AI: "Go check the documentation." But that's far from enough.

I added a **"Research Phase"** to Ralph's execution loop.

Before implementing each Story, the system checks: What technologies does this task involve? Are there topics that need research?

If yes, AI will:
1. **Fetch the latest library source code** (not documentation — actual source!)
2. **Read key modules** to understand the real implementation
3. **Consult official docs and best practices**
4. **Generate a research report** documenting findings and recommendations

Only after research is complete does it enter the implementation phase.

This led me to a deeper question: **What if research shows the original plan isn't feasible?**

So I added the **"Plan Review"** phase. After research, the system evaluates:
- Is the original Story design reasonable?
- Do acceptance criteria need adjustment?
- Should tasks be split or merged?

Now, the execution phase evolved from Ralph's simple loop to a five-step cycle:

```
Original Ralph:  Pick Story → Implement → Check → Next
        ↓ Improved
Research → Exploration → Plan Review → Implement → Quality Review
```

**AI no longer executes blindly — it researches, explores alternatives, plans, then implements.**

## When You Don't Know Which Path Is Right

At this point in the design, I encountered the second major problem:

**If there are multiple technical approaches, how does AI choose?**

For example, building an authentication system — JWT, Session, OAuth are all options. On what basis does AI pick one? Gut feeling?

My answer: **Try them all.**

I designed a **"Parallel Exploration"** mechanism:

When facing major technical decisions, the system will:
1. Create an independent **Git Worktree** for each approach
2. **Run multiple AI Agents in parallel**, each implementing one approach
3. Each Agent generates an **exploration report** upon completion: what was implemented, pros, cons, scores
4. Deploy **3 evaluation Agents** to independently review all approaches
5. Finally **synthesize recommendations**, select the optimal approach and merge

```
Option A ──→ Agent A implements ──→ Report A ─┐
Option B ──→ Agent B implements ──→ Report B ─┼──→ Evaluation Team ──→ Best Solution
Option C ──→ Agent C implements ──→ Report C ─┘
```

This isn't theoretical "comparison" — it's **actually implementing each path before comparing**.

Only by walking each road yourself do you know which one is best.

## Who Supervises the AI?

As the system grew more complete, a concern lingered in my mind:

**What if AI goes off track?**

It might get stuck in loops, write disastrous code, or lead the entire project in the wrong direction. And since it runs automatically, by the time you notice problems, it might be too late.

I needed a **supervision mechanism**.

But human supervision? That defeats the purpose of "autonomous" and can't achieve 24/7 operation.

Another AI to supervise? Then who supervises the supervisor?

After much thought, I came up with a somewhat crazy solution:

**Establish a "God Committee".**

This is an **oversight body independent of the execution layer**, consisting of three AI members: **Alpha, Beta, Gamma**.

They:
- **Don't participate in coding** — only observe and supervise
- **Automatically awaken periodically** (random 2-8 hour intervals) to patrol project status
- **Respond immediately to anomalies**: emergency intervention on errors, test failures, stuck processes
- **Major decisions require consensus**: terminating processes, rolling back code, deleting features require 2/3 member approval

They possess **supreme authority**:
- Pause all execution
- Rollback any commit
- Modify any code
- Terminate any process
- Repair system issues

This wasn't made up on a whim. It draws from:
- **Distributed systems** consensus mechanisms
- **Corporate governance** supervisory boards
- **AI safety** multi-agent review

I named it **"God Committee"**.

```
┌─────────────────────────────────────────────────┐
│              GOD COMMITTEE                      │
│   ┌───────┐   ┌───────┐   ┌───────┐            │
│   │ Alpha │───│ Beta  │───│ Gamma │            │
│   └───────┘   └───────┘   └───────┘            │
│         │         │           │                │
│         └────────┬────────────┘                │
│                  ↓                             │
│         Observe · Discuss · Intervene          │
└─────────────────────────────────────────────────┘
                   ↓ Supervise
┌─────────────────────────────────────────────────┐
│              Execution Layer                    │
│   Orchestrator → Execution Engine → Skills      │
└─────────────────────────────────────────────────┘
```

## Making Everything Transparent and Traceable

One more issue: **Can humans understand AI's decision-making process?**

If AI just works silently, we can't troubleshoot when problems arise; even when successful, we don't know why it succeeded.

So I added an **"Observability"** mechanism.

Every decision, every thought, every choice AI makes is logged:

```markdown
## 2026-01-30 14:30:00 | Task: PRD-003 | Phase: Research

### Thinking
I'm researching authentication strategies. The vision mentions "simple and fast" —
traditional username/password might add friction...

### Decision Point
- Considering: Traditional email/password
- Considering: Magic Link (passwordless)
- Considering: OAuth only
- **Final choice:** Magic Link + OAuth fallback
- **Reason:** Aligns with "simple" goal, reduces password fatigue

### Next Step
Research email service providers (Resend, SendGrid) free tiers...
```

These logs aren't for AI — they're for **humans**.

You can open `logs/ai-thoughts.md` at any time and see AI's complete thought process. Why it chose this approach, what it's worried about, what it's uncertain about — all transparent.

## Real World Test: One Paragraph, One API Gateway

After completing the system design, I decided to test it with a real project.

I gave AI just this paragraph as the vision:

> I need to implement an AI (LLM) gateway. The major LLM providers today — OpenAI, Anthropic, Google — all have different API implementations. OpenAI has the early `v1/chat/completions` and now `v1/responses`, Anthropic has `v1/messages`, Google's is even more complex. Each has different request interfaces, response structures, streaming and non-streaming variants — all over the place.
>
> I want a solution: Can we build an AI gateway supporting formats X, Y, Z, where given any upstream A, regardless of A's format type, users can always interact through any X, Y, Z format request, and responses are also in the user's expected X, Y, Z format?

**Just that one paragraph.**

No detailed technical specs, no API documentation, no architecture diagrams.

Then, I pressed Enter.

### The Results

Honestly, I surprised myself:

1. **Vision Analysis**: AI accurately identified this as a "protocol conversion gateway" project with "multi-protocol compatibility" as the core problem
2. **Architecture Design**: Chose Rust as the development language (for performance and easy verification), designed a layered architecture with protocol layer, conversion layer, and upstream layer
3. **Roadmap Planning**: Split into multiple milestones, from basic framework to protocol support to streaming processing
4. **Story-by-Story Implementation**: AI completed each Story independently, including:
   - OpenAI Chat Completions protocol support
   - OpenAI Responses protocol support
   - Anthropic Messages protocol support
   - Streaming response handling
   - Protocol interconversion
   - Configuration system
   - Error handling

In the end, it delivered a **nearly usable AI gateway system**.

Why "nearly"? There were still some issues:

- Core functionality implemented
- Multi-protocol conversion works
- Both streaming and non-streaming supported
- A few bugs need fixing
- Plugin system not implemented (an extension capability mentioned in the vision)

From a vague requirement description to a basically functional system — this process was completed autonomously by AI.

### An Interesting Discovery

After the project completed, I checked the system logs and found something unexpected:

**The God Committee never actually ran properly.**

Due to some bugs in the supervision scripts, the three "Gods" remained dormant throughout, never awakened.

This means the entire AI-Gateway development process had **no supervision intervention**.

This tells us two things:

**First**, Aha Loop's core execution flow (Vision → Architecture → Roadmap → Execute) is stable enough that even without the supervision layer, it can produce a basically usable result.

**Second**, the supervision mechanism is indeed necessary — if the God Committee had worked properly, those bugs might have been caught and fixed earlier.

This was an accidental "ablation study": removing the supervision layer, Aha Loop still works, but does miss some issues.

## What Aha Loop Adds to Ralph

I named this extended system **Aha Loop**.

Why this name? Because I hope AI achieves an **"Aha" moment** in each loop — gaining understanding through research, finding optimal solutions through exploration, rather than executing blindly.

In summary, compared to [Ralph](https://github.com/snarktank/ralph), Aha Loop adds:

| Original Ralph | Aha Loop Extensions |
|----------------|---------------------|
| Starts from PRD | Added Vision → Architecture → Roadmap pre-phases |
| Direct Story execution | Added five-phase workflow: Research → Exploration → Plan Review → Implement → Quality Review |
| Single execution path | Added autonomous parallel exploration (AI decides when to explore, creates worktrees, evaluates) |
| No oversight | Added God Committee independent supervision |
| Result-oriented | Added complete observability logging |

If Ralph is an **execution engine**, Aha Loop adds the **brain** (planning layer) and **eyes** (oversight layer).

## Looking Forward

Perhaps in the future, each of us could have an AI team: some responsible for coding, some for research, some for supervision — and you, just need to tell them your vision.

**That day will come sooner than any of us imagine.**

---

*Back to [README](../README.md)*
