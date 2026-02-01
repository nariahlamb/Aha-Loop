# Research Report: [STORY_ID] - [STORY_TITLE]

**Date:** [DATE]
**Status:** Complete | Needs Follow-up

---

## Research Topics

From prd.json `researchTopics`:

1. [Topic 1]
2. [Topic 2]
3. ...

---

## Findings

### Topic 1: [Topic Name]

**Summary:** [Brief answer to the research question]

**Sources Consulted:**
- [ ] Library source code (`.vendor/...`)
- [ ] Official documentation
- [ ] Web search results
- [ ] Existing codebase patterns

**Source Code Analysis:** (if applicable)
- Library: [name] v[version]
- Key File: `.vendor/[ecosystem]/[lib]-[version]/[path]`
- Relevant Code: Lines [start]-[end]
- Pattern Observed: [description]

**Documentation Notes:**
- [Key insight from docs]
- [Another insight]

**Code Example:**
```[language]
// Example from source or docs showing recommended usage
```

### Topic 2: [Topic Name]

[Repeat structure above]

---

## Alternatives Comparison (if applicable)

| Criterion | Option A | Option B | Option C |
|-----------|----------|----------|----------|
| Performance | ... | ... | ... |
| API Ergonomics | ... | ... | ... |
| Maintenance Status | ... | ... | ... |
| Bundle/Binary Size | ... | ... | ... |
| Learning Curve | ... | ... | ... |
| Community Support | ... | ... | ... |

**Recommendation:** [Option X]

**Reasoning:** [Why this option is preferred for this project]

---

## Implementation Recommendations

Based on research, implement the story as follows:

1. **Approach:** [High-level approach to take]
2. **Pattern to Follow:** [Reference to existing code or documented pattern]
3. **Key Files to Modify:** [List of files]
4. **Dependencies:** [Any new dependencies needed]

### Pitfalls to Avoid

- [Gotcha 1 discovered during research]
- [Gotcha 2]

### Sample Implementation

```[language]
// Pseudocode or actual code snippet showing recommended approach
```

---

## Follow-up Research Needed

- [ ] [Topic that needs deeper investigation]
- [ ] [Question that emerged during research]

---

## Knowledge Base Updates

### To `knowledge/project/patterns.md`:

```markdown
### [Pattern Name]
- Context: [When to use this pattern]
- Implementation: [How to implement]
- Example: [Code reference]
```

### To `knowledge/project/gotchas.md`:

```markdown
### [Component]: [Issue]
- Problem: [What went wrong]
- Solution: [How to avoid]
```

### To `knowledge/domain/[topic]/`:

Create new file if this knowledge is reusable across projects:
- `[topic]/README.md` - Overview
- `[topic]/patterns.md` - Common patterns
- `[topic]/examples/` - Code examples

---

## Checklist

- [ ] All research topics investigated
- [ ] Library source code read (if applicable)
- [ ] Documentation consulted
- [ ] Alternatives compared (if applicable)
- [ ] Implementation recommendations documented
- [ ] Pitfalls identified
- [ ] Knowledge base updates drafted
- [ ] Follow-up items noted
