# Quality Review Report: [STORY_ID] - [STORY_TITLE]

**Date:** [DATE]
**Reviewer:** Aha Loop (automated)
**Status:** Passed | Failed | Needs Revision

---

## Acceptance Criteria Verification

| Criterion | Status | Notes |
|-----------|--------|-------|
| [Criterion 1] | ✅ Pass / ❌ Fail | [Details] |
| [Criterion 2] | ✅ Pass / ❌ Fail | [Details] |
| Typecheck passes | ✅ Pass / ❌ Fail | [Command output] |
| Tests pass | ✅ Pass / ❌ Fail / ⏭ Skipped | [Command output] |

---

## Quality Checks

### Type Checking

**Command:** `[typecheck command, e.g., cargo check, tsc --noEmit]`

**Result:** ✅ Pass / ❌ Fail

```
[Command output]
```

### Linting

**Command:** `[lint command, e.g., cargo clippy, eslint]`

**Result:** ✅ Pass / ❌ Fail

**Issues Found:** [count]

```
[Lint output if any issues]
```

### Tests

**Command:** `[test command, e.g., cargo test, npm test]`

**Result:** ✅ Pass / ❌ Fail / ⏭ Skipped

```
[Test output summary]
```

### Browser Verification (UI stories only)

**Verified:** ✅ Yes / ❌ No / ⏭ N/A

**Pages Checked:**
- [URL 1]: [Description of what was verified]
- [URL 2]: [Description]

**Screenshots:** (if taken)
- [Link or description]

---

## Code Quality Assessment

### Adherence to Research Recommendations

| Recommendation | Followed | Notes |
|----------------|----------|-------|
| [From research report] | ✅ / ❌ | [Details] |

### Code Patterns

**Existing patterns followed:** ✅ Yes / ❌ No

**Patterns referenced:**
- `knowledge/project/patterns.md` - [Pattern name]
- [Existing code file] - [What was followed]

### Potential Issues

- [ ] [Issue 1 if any]
- [ ] [Issue 2 if any]

---

## Files Changed

| File | Change Type | Lines Changed |
|------|-------------|---------------|
| [path/to/file.rs] | Added / Modified / Deleted | +[add] / -[remove] |

---

## Learnings for Future Stories

### Patterns Discovered

Add to `knowledge/project/patterns.md`:

```markdown
[Pattern description if any new patterns discovered]
```

### Gotchas Encountered

Add to `knowledge/project/gotchas.md`:

```markdown
[Gotcha description if any issues encountered]
```

### Implementation Notes

Update story's `learnings` field with:

```
[Key learnings from this implementation]
```

---

## Summary

**Overall Status:** ✅ Ready to Commit / ❌ Needs Fixes / ⚠️ Commit with Notes

**Commit Message:**
```
feat: [STORY_ID] - [STORY_TITLE]

[Brief description of what was implemented]

Research: scripts/aha-loop/research/[STORY_ID]-research.md
```

**Next Story:** [NEXT_STORY_ID] - [NEXT_STORY_TITLE]

---

## Checklist

- [ ] All acceptance criteria verified
- [ ] Typecheck passes
- [ ] Lint passes (or issues are acceptable)
- [ ] Tests pass (or not applicable)
- [ ] Browser verification done (for UI stories)
- [ ] Research recommendations followed
- [ ] Learnings documented
- [ ] Ready for commit
